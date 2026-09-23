#!/usr/bin/env bash
#
# Fetch the pinned decision-model GGUF weights and verify them against
# scripts/decision-model/model-manifest.json. Never invoked implicitly by any
# other script; a user (or the sidecar's failure message) runs this by hand.
#
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest_path="${script_dir}/model-manifest.json"
models_dir="${HOME}/Library/Application Support/OpenComputerUse/decision-model/models"

usage() {
  cat <<'USAGE'
Usage: scripts/decision-model/fetch-model.sh [--model <key>]

Downloads the pinned GGUF file named by <key> (default: the manifest's
"active" model) into
  "$HOME/Library/Application Support/OpenComputerUse/decision-model/models/"
and verifies its size and sha256 against scripts/decision-model/model-manifest.json.

Exit codes:
  0  verified file already in place, or newly downloaded and verified
  1  other error (missing manifest key, network failure, curl failure, ...)
  2  hash or size mismatch (the partial download is deleted)
USAGE
}

model_key=""

while [ $# -gt 0 ]; do
  case "$1" in
    --model)
      [ $# -ge 2 ] || { echo "fetch-model.sh: --model requires a value" >&2; exit 1; }
      model_key="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "fetch-model.sh: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v node >/dev/null 2>&1; then
  echo "fetch-model.sh: node is required to read the manifest" >&2
  exit 1
fi

if [ -z "${model_key}" ]; then
  model_key="$(node -e 'console.log(require(process.argv[1]).active)' "${manifest_path}")"
fi

read -r repo revision filename size_bytes sha256 < <(
  node -e '
    const manifest = require(process.argv[1]);
    const key = process.argv[2];
    const entry = manifest.models[key];
    if (!entry) {
      process.stderr.write(`fetch-model.sh: unknown model key: ${key}\n`);
      process.exit(1);
    }
    process.stdout.write([entry.repo, entry.revision, entry.filename, entry.sizeBytes, entry.sha256].join(" ") + "\n");
  ' "${manifest_path}" "${model_key}"
)

mkdir -p "${models_dir}"
final_path="${models_dir}/${filename}"
partial_path="${final_path}.partial"

verify_file() {
  local path="$1"
  local actual_size
  actual_size="$(stat -f%z "${path}" 2>/dev/null || stat -c%s "${path}")"
  if [ "${actual_size}" != "${size_bytes}" ]; then
    echo "fetch-model.sh: size mismatch for ${path}: expected ${size_bytes}, got ${actual_size}" >&2
    return 1
  fi
  local actual_sha256
  actual_sha256="$(shasum -a 256 "${path}" | awk '{print $1}')"
  if [ "${actual_sha256}" != "${sha256}" ]; then
    echo "fetch-model.sh: sha256 mismatch for ${path}: expected ${sha256}, got ${actual_sha256}" >&2
    return 1
  fi
  echo "fetch-model.sh: verified ${path} (sha256 ${actual_sha256})"
  return 0
}

if [ -f "${final_path}" ]; then
  if verify_file "${final_path}"; then
    echo "fetch-model.sh: ${filename} already present and verified; no download."
    exit 0
  fi
  echo "fetch-model.sh: existing ${final_path} failed verification; re-downloading." >&2
  rm -f "${final_path}"
fi

rm -f "${partial_path}"

url="https://huggingface.co/${repo}/resolve/${revision}/${filename}"
echo "fetch-model.sh: downloading ${url}"
if ! curl --fail --location --proto '=https' --tlsv1.2 --output "${partial_path}" "${url}"; then
  echo "fetch-model.sh: download failed" >&2
  rm -f "${partial_path}"
  exit 1
fi

if ! verify_file "${partial_path}"; then
  rm -f "${partial_path}"
  exit 2
fi

mv "${partial_path}" "${final_path}"
echo "fetch-model.sh: downloaded and verified ${final_path}"
exit 0
