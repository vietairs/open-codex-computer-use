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
will_notarize=0

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
    ticket. "auto" notarizes release builds only; "required" notarizes any
    configuration and fails the build when notarization cannot happen;
    "skip" never notarizes. Notarization needs a "Developer ID Application"
    signing identity (a 40-hex SHA-1 identity is mapped to its name) and
    credentials; otherwise "auto" skips and "required" fails. The decision is
    made before signing, and codesign only requests a secure timestamp
    (--timestamp, which contacts Apple) when the build will be notarized.
    Credentials are resolved in this order:
      1. OPEN_COMPUTER_USE_NOTARY_PROFILE=<keychain profile name>
      2. An App Store Connect API key: APPLE_NOTARY_KEY_PATH=/path/to/key.p8
         or APPLE_NOTARY_API_KEY_P8_BASE64=<base64 .p8 contents>, plus
         APPLE_NOTARY_KEY_ID and APPLE_NOTARY_ISSUER_ID (APPLE_DEVELOPER_TEAM_ID optional)
      3. In "auto" mode only, when neither of the above is set: the keychain
         profile "open-computer-use-notary", if one has been stored locally
         with `xcrun notarytool store-credentials open-computer-use-notary`.
         "required" never probes for it; set
         OPEN_COMPUTER_USE_NOTARY_PROFILE=open-computer-use-notary explicitly.
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

# Prints the human-readable name of the identity the bundle will be signed
# with, or nothing when signing is disabled. A 40-hex SHA-1 identity is mapped
# to its certificate name through `security find-identity`, so a hash-pinned
# Developer ID identity is still recognized as one.
resolve_signing_identity_name() {
  local identity=""

  if ! identity="$(resolve_codesign_identity)"; then
    return 0
  fi

  if [[ ! "${identity}" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    printf '%s\n' "${identity}"
    return 0
  fi

  local -a args=(find-identity -v -p codesigning)
  if [[ -n "${codesign_keychain}" ]]; then
    args+=("${codesign_keychain}")
  fi

  local identities=""
  identities="$(security "${args[@]}" 2>/dev/null || true)"

  local sha1_upper=""
  sha1_upper="$(printf '%s' "${identity}" | tr '[:lower:]' '[:upper:]')"

  printf '%s\n' "${identities}" | awk -v sha1="${sha1_upper}" '
    $2 == sha1 {
      line = $0
      sub(/^[^"]*"/, "", line)
      sub(/"[^"]*$/, "", line)
      print line
      exit
    }
  '
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
#
# Callers invoke this inside an `if` condition, which disables errexit for
# the whole function body, so every step that can fail is checked explicitly.
# Key material is never echoed.
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

    local resolved_key_path=""
    if [[ -n "${notary_key_path}" ]]; then
      if [[ ! -f "${notary_key_path}" || ! -r "${notary_key_path}" ]]; then
        echo "APPLE_NOTARY_KEY_PATH does not point to a readable file: ${notary_key_path}" >&2
        exit 1
      fi
      resolved_key_path="${notary_key_path}"
    else
      # BSD mktemp (macOS /usr/bin/mktemp) requires the Xs to be the trailing
      # characters of the template; unlike GNU mktemp --suffix, a literal
      # suffix after XXXXXX (e.g. ".p8") is left unsubstituted. notarytool
      # does not require a .p8 extension, so the template omits one.
      if ! notary_key_tmp_path="$(mktemp "${TMPDIR:-/tmp}/open-computer-use-notary-key.XXXXXX")" || [[ -z "${notary_key_tmp_path}" ]]; then
        notary_key_tmp_path=""
        echo "Failed to create a temporary file for the notary API key" >&2
        exit 1
      fi
      if ! chmod 600 "${notary_key_tmp_path}"; then
        echo "Failed to restrict permissions on the temporary notary API key file" >&2
        exit 1
      fi
      # Whitespace (e.g. the line wrapping GNU base64 adds) is stripped first;
      # anything else outside the base64 alphabet is rejected by validate=True.
      if ! CERT_PATH="${notary_key_tmp_path}" python3 -c '
import base64, binascii, os, pathlib, sys
encoded = "".join(os.environ["APPLE_NOTARY_API_KEY_P8_BASE64"].split())
try:
    decoded = base64.b64decode(encoded, validate=True)
except (binascii.Error, ValueError):
    sys.exit(1)
pathlib.Path(os.environ["CERT_PATH"]).write_bytes(decoded)
' 2>/dev/null; then
        echo "APPLE_NOTARY_API_KEY_P8_BASE64 is not valid base64" >&2
        exit 1
      fi
      if [[ ! -s "${notary_key_tmp_path}" ]]; then
        echo "APPLE_NOTARY_API_KEY_P8_BASE64 decoded to an empty notary API key" >&2
        exit 1
      fi
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

# Decides, before anything is signed, whether this build will be notarized,
# and records the answer in the global will_notarize (0 or 1). Notarization
# needs a secure timestamp, and requesting one contacts Apple, so this single
# decision also controls codesign's --timestamp flag: a build that will not be
# notarized (skip mode, an "auto" debug build, a non-Developer-ID identity, or
# no credentials) never talks to Apple.
decide_notarization() {
  will_notarize=0

  if [[ "${notarize_mode}" == "skip" ]]; then
    return 0
  fi

  # "auto" notarizes release builds only; "required" applies to any configuration.
  if [[ "${notarize_mode}" == "auto" && "${configuration}" != "release" ]]; then
    return 0
  fi

  local identity_name=""
  identity_name="$(resolve_signing_identity_name)"

  if [[ "${identity_name}" != "Developer ID Application:"* ]]; then
    if [[ "${notarize_mode}" == "required" ]]; then
      echo "OPEN_COMPUTER_USE_NOTARIZE=required but the app bundle will not be signed with a \"Developer ID Application\" identity (resolved identity: ${identity_name:-none}, OPEN_COMPUTER_USE_CODESIGN_MODE=${codesign_mode}); notarization requires Developer ID Application signing with hardened runtime and a secure timestamp." >&2
      exit 1
    fi
    echo "Skipping notarization: the app bundle will not be signed with a \"Developer ID Application\" identity (OPEN_COMPUTER_USE_CODESIGN_MODE=${codesign_mode})." >&2
    return 0
  fi

  if ! resolve_notary_auth; then
    if [[ "${notarize_mode}" == "required" ]]; then
      echo "OPEN_COMPUTER_USE_NOTARIZE=required but no notarization credentials were found. Set OPEN_COMPUTER_USE_NOTARY_PROFILE (to use the locally stored keychain profile, set OPEN_COMPUTER_USE_NOTARY_PROFILE=${notary_auto_profile_name} explicitly; required mode never probes for it), or APPLE_NOTARY_KEY_PATH/APPLE_NOTARY_API_KEY_P8_BASE64 together with APPLE_NOTARY_KEY_ID and APPLE_NOTARY_ISSUER_ID." >&2
      exit 1
    fi
    echo "Skipping notarization: no notarization credentials configured (set OPEN_COMPUTER_USE_NOTARY_PROFILE, APPLE_NOTARY_KEY_PATH, or APPLE_NOTARY_API_KEY_P8_BASE64 with APPLE_NOTARY_KEY_ID/APPLE_NOTARY_ISSUER_ID, or store a keychain profile named \"${notary_auto_profile_name}\")." >&2
    return 0
  fi

  will_notarize=1
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

  # A secure timestamp requires contacting Apple's timestamp server, and
  # codesign requests one by default for Developer ID signatures. Ask for it
  # only when this build will be notarized; otherwise disable it explicitly so
  # debug builds and offline dev loops never touch the network.
  if [[ "${will_notarize}" -eq 1 ]]; then
    args+=(--timestamp)
  elif [[ "${identity}" != "-" ]]; then
    args+=(--timestamp=none)
  fi

  run_with_codesign_keychain "${codesign_keychain}" \
    codesign "${args[@]}" "${app_path}" >/dev/null

  if [[ "${identity}" == "-" ]]; then
    echo "Signed ${app_path} with ad-hoc identity; macOS TCC may still treat separately built copies as different app identities until a stable Apple signing identity is configured." >&2
  else
    echo "Signed ${app_path} with ${identity}" >&2
  fi
}

# Prints one top-level field ("id" or "status") from notarytool's JSON output.
# Tolerates non-JSON lines around the JSON object; prints nothing when absent.
read_notary_submit_field() {
  local json_path="${1:-}"
  local field="${2:-}"

  python3 - "${json_path}" "${field}" <<'PY' 2>/dev/null || true
import json
import sys

path, field = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8", errors="replace") as fh:
    text = fh.read()

data = None
try:
    data = json.loads(text)
except ValueError:
    for line in reversed(text.splitlines()):
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            data = json.loads(line)
            break
        except ValueError:
            continue

if isinstance(data, dict):
    value = data.get(field, "")
    print(value if isinstance(value, str) else "")
PY
}

notarize_app_bundle() {
  local app_path="${1:-}"

  # Confirm from the actual signature, not the configured identity, that the
  # bundle carries a Developer ID Application authority before submitting.
  local signature_details=""
  signature_details="$(codesign -dvv "${app_path}" 2>&1 || true)"
  if ! printf '%s\n' "${signature_details}" | grep -q '^Authority=Developer ID Application:'; then
    if [[ "${notarize_mode}" == "required" ]]; then
      echo "OPEN_COMPUTER_USE_NOTARIZE=required but the signature on ${app_path} has no \"Authority=Developer ID Application:\" entry; refusing to submit it for notarization." >&2
      exit 1
    fi
    echo "Skipping notarization for ${app_path}: its signature has no \"Developer ID Application\" authority." >&2
    return 0
  fi

  echo "Notarizing ${app_path} (credentials: ${notary_auth_source})..." >&2

  notary_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/open-computer-use-notarize.XXXXXX")"
  local zip_path
  zip_path="${notary_work_dir}/$(basename "${app_path%.app}").zip"
  local submit_stdout_path="${notary_work_dir}/submit.json"
  local submit_stderr_path="${notary_work_dir}/submit.stderr"

  ditto -c -k --keepParent "${app_path}" "${zip_path}"

  local submit_status=0
  xcrun notarytool submit "${zip_path}" "${notary_auth_args[@]}" --wait --output-format json --no-progress \
    >"${submit_stdout_path}" 2>"${submit_stderr_path}" || submit_status=$?
  cat "${submit_stderr_path}" >&2
  cat "${submit_stdout_path}" >&2

  local submission_id=""
  local submission_status=""
  submission_id="$(read_notary_submit_field "${submit_stdout_path}" id)"
  submission_status="$(read_notary_submit_field "${submit_stdout_path}" status)"

  # notarytool can exit 0 for a submission Apple rejected, so the JSON status
  # is authoritative: anything other than "Accepted" is a failure.
  if [[ "${submit_status}" -ne 0 || "${submission_status}" != "Accepted" ]]; then
    echo "Notarization failed for ${app_path}: submission id=${submission_id:-unknown}, status=${submission_status:-unknown}, notarytool exit code=${submit_status}" >&2
    if [[ -n "${submission_id}" ]]; then
      echo "Fetching notarytool log for submission ${submission_id}..." >&2
      xcrun notarytool log "${submission_id}" "${notary_auth_args[@]}" >&2 || true
    fi
    exit 1
  fi

  echo "Notarization accepted (submission id ${submission_id})." >&2

  # The ticket can take a moment to propagate to Apple's CDN after acceptance,
  # so stapling is retried a bounded number of times before giving up.
  local -a staple_retry_delays=(10 20)
  local staple_max_attempts=3
  local staple_attempt=1
  while ! xcrun stapler staple "${app_path}"; do
    if [[ "${staple_attempt}" -ge "${staple_max_attempts}" ]]; then
      echo "stapler staple failed for ${app_path} after ${staple_max_attempts} attempts" >&2
      exit 1
    fi
    local staple_delay="${staple_retry_delays[$((staple_attempt - 1))]}"
    echo "stapler staple failed (attempt ${staple_attempt}/${staple_max_attempts}); retrying in ${staple_delay}s..." >&2
    sleep "${staple_delay}"
    staple_attempt=$((staple_attempt + 1))
  done

  xcrun stapler validate "${app_path}"
  spctl -a -vvv -t exec "${app_path}" 2>&1 | sed 's/^/spctl: /' >&2 || true

  echo "Notarized and stapled ${app_path}" >&2
}

cd "${repo_root}"

icon_work_dir=""
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
# Installed before decide_notarization, which may decode an API key into a
# temporary file that must be removed however the script exits.
trap cleanup EXIT

enforce_release_signing_policy
decide_notarization

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
if [[ "${will_notarize}" -eq 1 ]]; then
  notarize_app_bundle "${app_root}"
fi

echo "Built ${app_root} (${arch_mode}, ${configuration})"
