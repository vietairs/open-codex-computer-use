#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="${repo_root}/dist"
output_dir="${dist_dir}/release/github"
requested_version=""

usage() {
  cat <<'EOF'
Usage: ./scripts/package-github-release-assets.sh [--version X.Y.Z] [--output-dir <dir>]

Packages already-built Open Computer Use runtimes and the repository skill as
direct-download GitHub Release assets. Run scripts/release-package.sh when the
native runtimes have not been built yet.
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

# The output directory is wiped before packaging, so refuse anything that is not
# a strict subdirectory of the repository, anything containing parent-directory
# segments, and anything that is, or contains, a build input (the dist directory,
# the app bundle or the native runtimes).
path_is_within() {
  local child="$1"
  local parent="$2"
  [[ "${child}" == "${parent}"/* ]]
}

refuse_output_dir() {
  echo "Refusing --output-dir ${output_dir}: $1" >&2
  exit 1
}

canonical_repo_root="$(cd "${repo_root}" && pwd -P)"

case "/${output_dir}/" in
  */../*|*/./*) refuse_output_dir "path must not contain . or .. segments" ;;
esac
if ! path_is_within "${output_dir%/}" "${repo_root}"; then
  refuse_output_dir "path must be a subdirectory of ${repo_root}"
fi

mkdir -p "${output_dir}"
canonical_output_dir="$(cd "${output_dir}" && pwd -P)"
if ! path_is_within "${canonical_output_dir}" "${canonical_repo_root}"; then
  refuse_output_dir "resolves outside the repository"
fi
for build_input in "${dist_dir}" "${app_path}" "${linux_arm64}" "${linux_amd64}" "${windows_arm64}" "${windows_amd64}"; do
  canonical_input="$(cd "$(dirname "${build_input}")" && pwd -P)/$(basename "${build_input}")"
  if [[ "${canonical_output_dir}" == "${canonical_input}" ]] || path_is_within "${canonical_input}" "${canonical_output_dir}"; then
    refuse_output_dir "it is, or contains, the build input ${build_input}"
  fi
done

rm -rf "${output_dir}"
mkdir -p "${output_dir}"

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
  tar --no-xattrs --no-mac-metadata -czf "${archive_path}" -C "${work_dir}" open-computer-use
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

node - "${output_dir}" "${version}" "${repo_root}" <<'NODE'
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const outputDir = process.argv[2];
const version = process.argv[3];
const repoRoot = process.argv[4];
const files = fs.readdirSync(outputDir)
  .filter((name) => name !== "release-assets-manifest.json")
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
