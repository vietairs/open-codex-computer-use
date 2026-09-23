#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="debug"
arch_mode="native"
codesign_mode="${OPEN_COMPUTER_USE_CODESIGN_MODE:-auto}"
codesign_identity="${OPEN_COMPUTER_USE_CODESIGN_IDENTITY:-}"
codesign_keychain="${OPEN_COMPUTER_USE_CODESIGN_KEYCHAIN:-}"
allow_adhoc_release="${OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE:-0}"
notarize_mode="${OPEN_COMPUTER_USE_NOTARIZE:-auto}"
notary_profile="${OPEN_COMPUTER_USE_NOTARY_PROFILE:-}"
notary_key_path="${APPLE_NOTARY_KEY_PATH:-}"
notary_key_p8_base64="${APPLE_NOTARY_API_KEY_P8_BASE64:-}"
notary_key_id="${APPLE_NOTARY_KEY_ID:-}"
notary_issuer_id="${APPLE_NOTARY_ISSUER_ID:-}"
notary_team_id="${APPLE_DEVELOPER_TEAM_ID:-}"
notary_auto_profile_name="open-computer-use-notary"
notary_key_tmp_path=""
notary_work_dir=""

usage() {
  cat <<'EOF'
Usage: ./scripts/build-open-computer-use-app.sh [debug|release] [--configuration debug|release] [--arch native|arm64|x86_64|universal]

Examples:
  ./scripts/build-open-computer-use-app.sh debug
  ./scripts/build-open-computer-use-app.sh --configuration release --arch universal

Environment:
  OPEN_COMPUTER_USE_CODESIGN_MODE=auto|identity|adhoc|none
  OPEN_COMPUTER_USE_CODESIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID)"
  OPEN_COMPUTER_USE_CODESIGN_KEYCHAIN=/path/to/signing.keychain-db
  OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1  (permit ad-hoc/unsigned RELEASE builds — peer authentication will be inactive)

  OPEN_COMPUTER_USE_NOTARIZE=auto|required|skip  (default auto)
    Notarizes the final app bundle with `xcrun notarytool` and staples the
    ticket. Only runs against a bundle signed with a "Developer ID
    Application" identity (hardened runtime + secure timestamp); any other
    signing outcome is skipped in "auto" and fails the build in "required".
    Credentials are resolved in this order:
      1. OPEN_COMPUTER_USE_NOTARY_PROFILE=<keychain profile name>
      2. An App Store Connect API key: APPLE_NOTARY_KEY_PATH=/path/to/key.p8
         or APPLE_NOTARY_API_KEY_P8_BASE64=<base64 .p8 contents>, plus
         APPLE_NOTARY_KEY_ID and APPLE_NOTARY_ISSUER_ID (APPLE_DEVELOPER_TEAM_ID optional)
      3. In "auto" mode only, when neither of the above is set: the keychain
         profile "open-computer-use-notary", if one has been stored locally
         with `xcrun notarytool store-credentials open-computer-use-notary`.
    With no credentials configured, "auto" behaves exactly like today (skips
    notarization) apart from one informational line on stderr.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    debug|release)
      configuration="$1"
      shift
      ;;
    --configuration)
      configuration="${2:-}"
      if [[ -z "${configuration}" ]]; then
        echo "--configuration requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --arch)
      arch_mode="${2:-}"
      if [[ -z "${arch_mode}" ]]; then
        echo "--arch requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "${configuration}" != "debug" && "${configuration}" != "release" ]]; then
  echo "Unsupported configuration: ${configuration}" >&2
  exit 1
fi

if [[ "${arch_mode}" != "native" && "${arch_mode}" != "arm64" && "${arch_mode}" != "x86_64" && "${arch_mode}" != "universal" ]]; then
  echo "Unsupported arch mode: ${arch_mode}" >&2
  exit 1
fi

if [[ "${codesign_mode}" != "auto" && "${codesign_mode}" != "identity" && "${codesign_mode}" != "adhoc" && "${codesign_mode}" != "none" ]]; then
  echo "Unsupported OPEN_COMPUTER_USE_CODESIGN_MODE: ${codesign_mode}" >&2
  exit 1
fi

if [[ "${notarize_mode}" != "auto" && "${notarize_mode}" != "required" && "${notarize_mode}" != "skip" ]]; then
  echo "Unsupported OPEN_COMPUTER_USE_NOTARIZE: ${notarize_mode}" >&2
  exit 1
fi

read_package_version() {
  python3 - "${repo_root}/plugins/open-computer-use/.codex-plugin/plugin.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    manifest = json.load(fh)

print(manifest["version"])
PY
}

build_binary() {
  local triple="${1:-}"
  local scratch_path="${2:-}"
  local -a args=(-c "${configuration}")

  if [[ -n "${triple}" ]]; then
    args+=(--triple "${triple}")
  fi

  if [[ -n "${scratch_path}" ]]; then
    args+=(--scratch-path "${scratch_path}")
  fi

  local binary_dir
  binary_dir="$(swift build "${args[@]}" --show-bin-path)"
  swift build "${args[@]}" --product OpenComputerUse >&2
  printf '%s/OpenComputerUse\n' "${binary_dir}"
}

find_codesign_identity() {
  local prefix="${1:-}"
  local -a args=(find-identity -v -p codesigning)

  if [[ -n "${codesign_keychain}" ]]; then
    args+=("${codesign_keychain}")
  fi

  security "${args[@]}" 2>/dev/null \
    | sed -n "s/.*\"\\(${prefix}: .*\\)\"/\1/p" \
    | head -n 1
}

list_user_keychains() {
  security list-keychains -d user \
    | sed -n 's/^[[:space:]]*"\(.*\)"$/\1/p'
}

run_with_codesign_keychain() {
  local keychain_path="${1:-}"
  shift

  if [[ -z "${keychain_path}" ]]; then
    "$@"
    return
  fi

  local -a existing_keychains=()
  while IFS= read -r keychain; do
    if [[ -n "${keychain}" ]]; then
      existing_keychains+=("${keychain}")
    fi
  done < <(list_user_keychains)

  local -a desired_keychains=("${keychain_path}")
  local existing=""
  for existing in "${existing_keychains[@]}"; do
    if [[ "${existing}" != "${keychain_path}" ]]; then
      desired_keychains+=("${existing}")
    fi
  done

  security list-keychains -d user -s "${desired_keychains[@]}" >/dev/null

  local status=0
  "$@" || status=$?

  if [[ ${#existing_keychains[@]} -gt 0 ]]; then
    security list-keychains -d user -s "${existing_keychains[@]}" >/dev/null
  else
    security list-keychains -d user -s >/dev/null
  fi

  return "${status}"
}

resolve_codesign_identity() {
  case "${codesign_mode}" in
    none)
      return 1
      ;;
    adhoc)
      printf '%s\n' "-"
      return 0
      ;;
    identity)
      if [[ -z "${codesign_identity}" ]]; then
        echo "OPEN_COMPUTER_USE_CODESIGN_IDENTITY is required when OPEN_COMPUTER_USE_CODESIGN_MODE=identity" >&2
        exit 1
      fi
      printf '%s\n' "${codesign_identity}"
      return 0
      ;;
    auto)
      if [[ -n "${codesign_identity}" ]]; then
        printf '%s\n' "${codesign_identity}"
        return 0
      fi

      local discovered_identity
      discovered_identity="$(find_codesign_identity "Developer ID Application")"
      if [[ -n "${discovered_identity}" ]]; then
        printf '%s\n' "${discovered_identity}"
        return 0
      fi

      discovered_identity="$(find_codesign_identity "Apple Development")"
      if [[ -n "${discovered_identity}" ]]; then
        printf '%s\n' "${discovered_identity}"
        return 0
      fi

      printf '%s\n' "-"
      return 0
      ;;
  esac
}

enforce_release_signing_policy() {
  if [[ "${configuration}" != "release" ]]; then
    return
  fi

  local identity=""
  local will_be_adhoc=0

  if ! identity="$(resolve_codesign_identity)"; then
    will_be_adhoc=1
  elif [[ "${identity}" == "-" ]]; then
    will_be_adhoc=1
  fi

  if [[ "${will_be_adhoc}" -ne 1 ]]; then
    return
  fi

  if [[ "${allow_adhoc_release}" != "1" ]]; then
    cat >&2 <<'EOF'
Refusing to produce a release build: the app bundle would be ad-hoc-signed
or unsigned, which ships with socket peer authentication INACTIVE (the
agent falls back to same-uid trust only).

Remedies:
  - Install a "Developer ID Application" signing identity, or
  - Set OPEN_COMPUTER_USE_CODESIGN_IDENTITY / OPEN_COMPUTER_USE_CODESIGN_MODE=identity, or
  - Intentionally override with OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1
EOF
    exit 1
  fi

  cat >&2 <<'EOF'
WARNING: proceeding with an ad-hoc-signed/unsigned release build because
OPEN_COMPUTER_USE_ALLOW_ADHOC_RELEASE=1 is set. This release will ship
with socket peer authentication INACTIVE (same-uid trust only).
EOF
}

codesign_app_bundle() {
  local app_path="${1:-}"
  local identity=""

  if ! identity="$(resolve_codesign_identity)"; then
    echo "Skipping codesign for ${app_path} (OPEN_COMPUTER_USE_CODESIGN_MODE=none)" >&2
    return
  fi

  local -a args=(--force --deep --sign "${identity}")

  if [[ -n "${codesign_keychain}" && "${identity}" != "-" ]]; then
    args+=(--keychain "${codesign_keychain}")
  fi

  if [[ "${identity}" != "-" ]]; then
    args+=(--options runtime)
  fi

  # Notarization needs a secure timestamp, which requires network access to
  # Apple's timestamp server. Only Developer ID signatures are ever notarized,
  # so other identities (e.g. Apple Development) keep signing offline.
  if [[ "${identity}" == "Developer ID Application:"* ]]; then
    args+=(--timestamp)
  fi

  run_with_codesign_keychain "${codesign_keychain}" \
    codesign "${args[@]}" "${app_path}" >/dev/null

  if [[ "${identity}" == "-" ]]; then
    echo "Signed ${app_path} with ad-hoc identity; macOS TCC may still treat separately built copies as different app identities until a stable Apple signing identity is configured." >&2
  else
    echo "Signed ${app_path} with ${identity}" >&2
  fi
}

notary_profile_exists() {
  local profile="${1:-}"

  if [[ -z "${profile}" ]]; then
    return 1
  fi

  xcrun notarytool history --keychain-profile "${profile}" --output-format json >/dev/null 2>&1
}

# Resolves notarization credentials into the global notary_auth_args array
# and notary_auth_source string. Returns 1 (with no output) when no
# credentials are configured. Bash on macOS defaults to 3.2 (no namerefs),
# so results are communicated through global variables rather than returned.
resolve_notary_auth() {
  notary_auth_args=()
  notary_auth_source="none"

  if [[ -n "${notary_profile}" ]]; then
    notary_auth_args=(--keychain-profile "${notary_profile}")
    notary_auth_source="profile"
    return 0
  fi

  if [[ -n "${notary_key_path}" || -n "${notary_key_p8_base64}" ]]; then
    if [[ -z "${notary_key_id}" || -z "${notary_issuer_id}" ]]; then
      echo "APPLE_NOTARY_KEY_ID and APPLE_NOTARY_ISSUER_ID are required when APPLE_NOTARY_KEY_PATH or APPLE_NOTARY_API_KEY_P8_BASE64 is set" >&2
      exit 1
    fi

    local resolved_key_path="${notary_key_path}"
    if [[ -z "${resolved_key_path}" ]]; then
      # BSD mktemp (macOS /usr/bin/mktemp) requires the Xs to be the trailing
      # characters of the template; unlike GNU mktemp --suffix, a literal
      # suffix after XXXXXX (e.g. ".p8") is left unsubstituted. notarytool
      # does not require a .p8 extension, so the template omits one.
      notary_key_tmp_path="$(mktemp "${TMPDIR:-/tmp}/open-computer-use-notary-key.XXXXXX")"
      chmod 600 "${notary_key_tmp_path}"
      CERT_PATH="${notary_key_tmp_path}" python3 -c 'import base64, os, pathlib; pathlib.Path(os.environ["CERT_PATH"]).write_bytes(base64.b64decode(os.environ["APPLE_NOTARY_API_KEY_P8_BASE64"]))'
      resolved_key_path="${notary_key_tmp_path}"
    fi

    notary_auth_args=(--key "${resolved_key_path}" --key-id "${notary_key_id}" --issuer "${notary_issuer_id}")
    if [[ -n "${notary_team_id}" ]]; then
      notary_auth_args+=(--team-id "${notary_team_id}")
    fi
    notary_auth_source="apikey"
    return 0
  fi

  if [[ "${notarize_mode}" == "auto" ]] && notary_profile_exists "${notary_auto_profile_name}"; then
    notary_auth_args=(--keychain-profile "${notary_auto_profile_name}")
    notary_auth_source="profile"
    return 0
  fi

  return 1
}

notarize_app_bundle() {
  local app_path="${1:-}"
  local identity="${2:-}"

  if [[ "${notarize_mode}" == "skip" ]]; then
    return 0
  fi

  if [[ "${identity}" != "Developer ID Application:"* ]]; then
    if [[ "${notarize_mode}" == "required" ]]; then
      echo "OPEN_COMPUTER_USE_NOTARIZE=required but ${app_path} is not signed with a \"Developer ID Application\" identity (resolved identity: ${identity:-none}); notarization requires Developer ID Application signing with hardened runtime and a secure timestamp." >&2
      exit 1
    fi
    echo "Skipping notarization for ${app_path}: not signed with a \"Developer ID Application\" identity (OPEN_COMPUTER_USE_CODESIGN_MODE=${codesign_mode})." >&2
    return 0
  fi

  if ! resolve_notary_auth; then
    if [[ "${notarize_mode}" == "required" ]]; then
      echo "OPEN_COMPUTER_USE_NOTARIZE=required but no notarization credentials were found. Set OPEN_COMPUTER_USE_NOTARY_PROFILE, or APPLE_NOTARY_KEY_PATH/APPLE_NOTARY_API_KEY_P8_BASE64 together with APPLE_NOTARY_KEY_ID and APPLE_NOTARY_ISSUER_ID." >&2
      exit 1
    fi
    echo "Skipping notarization for ${app_path}: no notarization credentials configured (set OPEN_COMPUTER_USE_NOTARY_PROFILE, APPLE_NOTARY_KEY_PATH, or APPLE_NOTARY_API_KEY_P8_BASE64 with APPLE_NOTARY_KEY_ID/APPLE_NOTARY_ISSUER_ID, or store a keychain profile named \"${notary_auto_profile_name}\")." >&2
    return 0
  fi

  echo "Notarizing ${app_path} (credentials: ${notary_auth_source})..." >&2

  notary_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/open-computer-use-notarize.XXXXXX")"
  local zip_path
  zip_path="${notary_work_dir}/$(basename "${app_path%.app}").zip"

  ditto -c -k --keepParent "${app_path}" "${zip_path}"

  local submit_output=""
  local submit_status=0
  submit_output="$(xcrun notarytool submit "${zip_path}" "${notary_auth_args[@]}" --wait --output-format json --no-progress 2>&1)" || submit_status=$?
  printf '%s\n' "${submit_output}" >&2

  if [[ "${submit_status}" -ne 0 ]]; then
    local submission_id=""
    submission_id="$(printf '%s' "${submit_output}" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(data.get("id", ""))
' 2>/dev/null || true)"
    if [[ -n "${submission_id}" ]]; then
      echo "Fetching notarytool log for submission ${submission_id}..." >&2
      xcrun notarytool log "${submission_id}" "${notary_auth_args[@]}" >&2 || true
    fi
    echo "Notarization failed for ${app_path}" >&2
    exit 1
  fi

  xcrun stapler staple "${app_path}"
  xcrun stapler validate "${app_path}"
  spctl -a -vvv -t exec "${app_path}" 2>&1 | sed 's/^/spctl: /' >&2 || true

  echo "Notarized and stapled ${app_path}" >&2
}

cd "${repo_root}"

enforce_release_signing_policy

package_version="$(read_package_version)"
bundle_version="${OPEN_COMPUTER_USE_BUNDLE_VERSION:-$(git -C "${repo_root}" rev-list --count HEAD 2>/dev/null || echo 1)}"
release_app_bundle_name="Open Computer Use.app"
development_app_bundle_name="Open Computer Use (Dev).app"
legacy_app_bundle_name="OpenComputerUse.app"
bundle_icon_name="OpenComputerUse.icns"
icon_master_png="${repo_root}/assets/app-icons/open-computer-use-1024.png"
iconset_build_script="${repo_root}/scripts/build-apple-iconset.sh"
cursor_reference_source="${repo_root}/docs/references/codex-computer-use-reverse-engineering/assets/extracted-2026-04-19/official-software-cursor-window-252.png"

bundle_display_name="Open Computer Use"
bundle_identifier="com.ifuryst.opencomputeruse"
app_variant="release"
app_bundle_name="${release_app_bundle_name}"

if [[ "${configuration}" != "release" ]]; then
  bundle_display_name="Open Computer Use (Dev)"
  bundle_identifier="com.ifuryst.opencomputeruse.dev"
  app_variant="dev"
  app_bundle_name="${development_app_bundle_name}"
fi

app_root="${repo_root}/dist/${app_bundle_name}"
release_app_root="${repo_root}/dist/${release_app_bundle_name}"
development_app_root="${repo_root}/dist/${development_app_bundle_name}"
legacy_app_root="${repo_root}/dist/${legacy_app_bundle_name}"
contents_dir="${app_root}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"

rm -rf "${app_root}" "${legacy_app_root}"
if [[ "${app_variant}" == "release" ]]; then
  rm -rf "${development_app_root}"
else
  rm -rf "${release_app_root}"
fi
mkdir -p "${macos_dir}" "${resources_dir}"

case "${arch_mode}" in
  native)
    cp "$(build_binary "" "")" "${macos_dir}/OpenComputerUse"
    ;;
  arm64)
    cp "$(build_binary "arm64-apple-macosx14.0" ".build/arm64-${configuration}")" "${macos_dir}/OpenComputerUse"
    ;;
  x86_64)
    cp "$(build_binary "x86_64-apple-macosx14.0" ".build/x86_64-${configuration}")" "${macos_dir}/OpenComputerUse"
    ;;
  universal)
    arm_binary="$(build_binary "arm64-apple-macosx14.0" ".build/arm64-${configuration}")"
    x86_binary="$(build_binary "x86_64-apple-macosx14.0" ".build/x86_64-${configuration}")"
    lipo -create -output "${macos_dir}/OpenComputerUse" "${arm_binary}" "${x86_binary}"
    ;;
esac

chmod +x "${macos_dir}/OpenComputerUse"

if [[ ! -f "${icon_master_png}" ]]; then
  echo "Missing icon master PNG: ${icon_master_png}" >&2
  exit 1
fi

if [[ ! -f "${iconset_build_script}" ]]; then
  echo "Missing iconset build script: ${iconset_build_script}" >&2
  exit 1
fi

if [[ ! -f "${cursor_reference_source}" ]]; then
  echo "Missing cursor reference PNG: ${cursor_reference_source}" >&2
  exit 1
fi

icon_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/open-computer-use-icon.XXXXXX")"
cleanup() {
  if [[ -n "${icon_work_dir:-}" ]]; then
    rm -rf "${icon_work_dir}"
  fi
  if [[ -n "${notary_key_tmp_path:-}" ]]; then
    rm -f "${notary_key_tmp_path}"
  fi
  if [[ -n "${notary_work_dir:-}" ]]; then
    rm -rf "${notary_work_dir}"
  fi
}
trap cleanup EXIT
iconset_dir="${icon_work_dir}/OpenComputerUse.iconset"
mkdir -p "${iconset_dir}"
"${iconset_build_script}" "${icon_master_png}" "${iconset_dir}"
iconutil -c icns "${iconset_dir}" -o "${resources_dir}/${bundle_icon_name}"
cp "${cursor_reference_source}" "${resources_dir}/official-software-cursor-window-252.png"

cat > "${contents_dir}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>OpenComputerUse</string>
  <key>CFBundleIconFile</key>
  <string>${bundle_icon_name}</string>
  <key>CFBundleIdentifier</key>
  <string>${bundle_identifier}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${bundle_display_name}</string>
  <key>CFBundleDisplayName</key>
  <string>${bundle_display_name}</string>
  <key>OpenComputerUseAppVariant</key>
  <string>${app_variant}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${package_version}</string>
  <key>CFBundleVersion</key>
  <string>${bundle_version}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "${contents_dir}/Info.plist" >/dev/null
codesign_app_bundle "${app_root}"

# arch_mode only selects which architectures are compiled into the single
# executable above (see the arch_mode case block); there is exactly one
# ${app_root} bundle regardless of arch_mode, so notarizing here already
# covers the universal build in one pass.
resolved_bundle_identity=""
if ! resolved_bundle_identity="$(resolve_codesign_identity)"; then
  resolved_bundle_identity=""
fi
notarize_app_bundle "${app_root}" "${resolved_bundle_identity}"

echo "Built ${app_root} (${arch_mode}, ${configuration})"
