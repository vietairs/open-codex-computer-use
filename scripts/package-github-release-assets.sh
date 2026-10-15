#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && /bin/pwd -P)"
dist_dir="${repo_root}/dist"
output_dir="${dist_dir}/release/github"
requested_version=""

usage() {
  cat <<'EOF'
Usage: ./scripts/package-github-release-assets.sh [--version X.Y.Z] [--output-dir <dir>]

Packages already-built Open Computer Use runtimes and the repository skill as
direct-download GitHub Release assets. Run scripts/release-package.sh when the
native runtimes have not been built yet.

--output-dir is resolved against the repository root when relative and, after
symlinks are resolved, must be a directory inside dist/release (the default
dist/release/github included); anything else is refused. It is only wiped when it
is empty or was created by an earlier run of this script (it holds the
.ocu-release-assets marker file).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      requested_version="${2:-}"
      if [[ -z "${requested_version}" ]]; then
        echo "--version requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      if [[ -z "${output_dir}" ]]; then
        echo "--output-dir requires a value" >&2
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

# Marker file written into every output directory this script creates; a
# non-empty directory without it is never wiped.
output_marker=".ocu-release-assets"

# Normalize the requested path: collapse repeated slashes, drop leading './'
# and trailing slashes, then anchor relative paths at the repository root.
while [[ "${output_dir}" == *//* ]]; do
  output_dir="${output_dir//\/\//\/}"
done
while [[ "${output_dir}" == ./?* ]]; do
  output_dir="${output_dir#./}"
done
while [[ "${output_dir}" == ?*/ ]]; do
  output_dir="${output_dir%/}"
done
if [[ "${output_dir}" != /* ]]; then
  output_dir="${repo_root}/${output_dir}"
fi

for command in node ditto lipo codesign tar zip unzip shasum; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "${command} is required to package GitHub Release assets" >&2
    exit 1
  fi
done

manifest_version="$(node -p "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')).version" "${repo_root}/plugins/open-computer-use/.codex-plugin/plugin.json")"
version="${requested_version:-${manifest_version}}"
version="${version#v}"

if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]]; then
  echo "Release version must look like X.Y.Z: ${version}" >&2
  exit 1
fi

if [[ "${version}" != "${manifest_version}" ]]; then
  echo "Release version ${version} does not match plugin manifest version ${manifest_version}" >&2
  exit 1
fi

app_path="${dist_dir}/Open Computer Use.app"
linux_arm64="${dist_dir}/linux/arm64/open-computer-use"
linux_amd64="${dist_dir}/linux/amd64/open-computer-use"
windows_arm64="${dist_dir}/windows/arm64/open-computer-use.exe"
windows_amd64="${dist_dir}/windows/amd64/open-computer-use.exe"

if [[ ! -d "${app_path}" ]]; then
  echo "Missing macOS app bundle: ${app_path}" >&2
  exit 1
fi

for executable in "${linux_arm64}" "${linux_amd64}" "${windows_arm64}" "${windows_amd64}"; do
  if [[ ! -f "${executable}" ]]; then
    echo "Missing native runtime: ${executable}" >&2
    exit 1
  fi
done

app_archs="$(lipo -archs "${app_path}/Contents/MacOS/OpenComputerUse")"
if [[ " ${app_archs} " != *" arm64 "* || " ${app_archs} " != *" x86_64 "* ]]; then
  echo "Expected a universal macOS app, found architectures: ${app_archs}" >&2
  exit 1
fi
codesign --verify --deep --strict "${app_path}"

# The output directory is wiped before packaging, so it is confined by an
# allowlist: after symlinks are resolved it must lie strictly inside
# <repository>/dist/release, which excludes the git directory, the app bundle,
# the native runtimes and the staged skill by construction. An existing
# non-empty directory is only wiped when this script created it (marker file).
refuse_output_dir() {
  echo "Refusing --output-dir ${output_dir}: $1" >&2
  exit 1
}

case "/${output_dir}/" in
  */../*|*/./*) refuse_output_dir "path must not contain . or .. segments" ;;
esac

# Resolve symlinks through the nearest existing ancestor before anything is
# created, so a link inside the repository cannot redirect the output elsewhere.
# /bin/pwd reports the case stored on disk, which the shell builtin does not on
# a case-insensitive filesystem.
missing_suffix=""
existing_ancestor="${output_dir}"
while [[ ! -e "${existing_ancestor}" ]]; do
  if [[ -L "${existing_ancestor}" ]]; then
    refuse_output_dir "${existing_ancestor} is a dangling symlink"
  fi
  missing_suffix="/$(basename "${existing_ancestor}")${missing_suffix}"
  existing_ancestor="$(dirname "${existing_ancestor}")"
done
if [[ ! -d "${existing_ancestor}" ]]; then
  refuse_output_dir "${existing_ancestor} exists and is not a directory"
fi
resolved_ancestor="$(cd "${existing_ancestor}" && /bin/pwd -P)" ||
  refuse_output_dir "cannot resolve ${existing_ancestor}"
canonical_output_dir="${resolved_ancestor}${missing_suffix}"

release_root="${repo_root}/dist/release"
if [[ "${canonical_output_dir}" != "${release_root}"/?* ]]; then
  refuse_output_dir "it must resolve to a directory inside ${release_root}"
fi

# Only wipe a directory that is empty or that an earlier run created. A listing
# failure (for example an unreadable directory) refuses instead of reading as empty.
if [[ -e "${canonical_output_dir}" ]]; then
  if [[ ! -d "${canonical_output_dir}" ]]; then
    refuse_output_dir "it exists and is not a directory"
  fi
  existing_entries="$(ls -A -- "${canonical_output_dir}")" ||
    refuse_output_dir "it cannot be listed"
  if [[ -n "${existing_entries}" && ! -f "${canonical_output_dir}/${output_marker}" ]]; then
    refuse_output_dir "it is not empty and was not created by this script (no ${output_marker} marker file)"
  fi
fi

# From here on use the resolved path, so a symlink swapped in later cannot
# redirect the wipe.
output_dir="${canonical_output_dir}"
rm -rf "${output_dir}"
mkdir -p "${output_dir}"
printf '%s\n' "Created by scripts/package-github-release-assets.sh; this directory is wiped on the next run." > "${output_dir}/${output_marker}"

app_archive="${output_dir}/Open-Computer-Use-${version}-macOS-universal.app.zip"
ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${app_archive}"

# Temp work directories created by the packaging helpers, removed on any exit.
work_dirs=()
cleanup_work_dirs() {
  local dir
  for dir in ${work_dirs[@]+"${work_dirs[@]}"}; do
    rm -rf "${dir}"
  done
}
trap cleanup_work_dirs EXIT

package_unix_cli() {
  local source_path="$1"
  local platform="$2"
  local arch="$3"
  local archive_path="${output_dir}/open-computer-use-cli-${version}-${platform}-${arch}.tar.gz"
  local work_dir
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/open-computer-use-release.XXXXXX")"
  work_dirs+=("${work_dir}")
  cp "${source_path}" "${work_dir}/open-computer-use"
  chmod +x "${work_dir}/open-computer-use"
  tar --no-xattrs --no-acls --no-fflags --no-mac-metadata -czf "${archive_path}" -C "${work_dir}" open-computer-use
}

package_windows_cli() {
  local source_path="$1"
  local arch="$2"
  local archive_path="${output_dir}/open-computer-use-cli-${version}-windows-${arch}.zip"
  local work_dir
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/open-computer-use-release.XXXXXX")"
  work_dirs+=("${work_dir}")
  cp "${source_path}" "${work_dir}/open-computer-use.exe"
  (
    cd "${work_dir}"
    zip -q -X "${archive_path}" open-computer-use.exe
  )
}

package_unix_cli "${linux_arm64}" linux arm64
package_unix_cli "${linux_amd64}" linux amd64
package_windows_cli "${windows_arm64}" arm64
package_windows_cli "${windows_amd64}" amd64

"${repo_root}/scripts/package-skill.sh" >/dev/null
cp "${dist_dir}/skills/open-computer-use-skill.zip" "${output_dir}/"
cp "${dist_dir}/skills/open-computer-use.skill" "${output_dir}/"

app_entry_list="${output_dir}/.macos-app-entries"
unzip -Z1 "${app_archive}" > "${app_entry_list}"
if ! grep -Fxq 'Open Computer Use.app/Contents/MacOS/OpenComputerUse' "${app_entry_list}"; then
  echo "macOS app archive is missing its CLI executable" >&2
  exit 1
fi
rm -f "${app_entry_list}"

for archive in "${output_dir}"/open-computer-use-cli-*.tar.gz; do
  if [[ "$(tar -tzf "${archive}")" != "open-computer-use" ]]; then
    echo "Unexpected Linux CLI archive contents: ${archive}" >&2
    exit 1
  fi
done

for archive in "${output_dir}"/open-computer-use-cli-*.zip; do
  if [[ "$(unzip -Z1 "${archive}")" != "open-computer-use.exe" ]]; then
    echo "Unexpected Windows CLI archive contents: ${archive}" >&2
    exit 1
  fi
done

(
  cd "${output_dir}"
  shasum -a 256 \
    "$(basename "${app_archive}")" \
    open-computer-use-cli-*.tar.gz \
    open-computer-use-cli-*.zip \
    open-computer-use-skill.zip \
    open-computer-use.skill \
    > SHA256SUMS
)

node - "${output_dir}" "${version}" "${repo_root}" "${output_marker}" <<'NODE'
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const outputDir = process.argv[2];
const version = process.argv[3];
const repoRoot = process.argv[4];
const marker = process.argv[5];
const files = fs.readdirSync(outputDir)
  .filter((name) => name !== "release-assets-manifest.json" && name !== marker)
  .sort();

const artifacts = files.map((name) => {
  const contents = fs.readFileSync(path.join(outputDir, name));
  return {
    name,
    size_bytes: contents.byteLength,
    sha256: crypto.createHash("sha256").update(contents).digest("hex")
  };
});

const manifest = {
  repository: process.env.GITHUB_REPOSITORY || "local",
  git_sha: process.env.GITHUB_SHA || require("child_process")
    .execFileSync("git", ["-C", repoRoot, "rev-parse", "HEAD"], { encoding: "utf8" })
    .trim(),
  version,
  generated_at_utc: new Date().toISOString(),
  artifacts
};

fs.writeFileSync(
  path.join(outputDir, "release-assets-manifest.json"),
  `${JSON.stringify(manifest, null, 2)}\n`
);
NODE

echo "${output_dir}"
