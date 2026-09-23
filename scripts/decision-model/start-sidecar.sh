#!/usr/bin/env bash
#
# Start llama-server as a user-controlled sidecar on a deterministic loopback
# port, then run check-readout.mjs against it. Never spawned automatically by
# the app-agent or any other script; a user runs this by hand.
#
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest_path="${script_dir}/model-manifest.json"
state_dir="${HOME}/Library/Application Support/OpenComputerUse/decision-model"
models_dir="${state_dir}/models"
run_dir="${state_dir}/run"
logs_dir="${state_dir}/logs"
pid_file="${run_dir}/llama-server.pid"
log_file="${logs_dir}/llama-server.log"

usage() {
  cat <<'USAGE'
Usage: scripts/decision-model/start-sidecar.sh [--model <key>] [--port <n>]

Starts llama-server on 127.0.0.1:<port> for the pinned model named by <key>
(default: the manifest's "active" model), waits for /health, runs
check-readout.mjs against it, then prints:
  export OPEN_COMPUTER_USE_DECISION_MODEL_URL=http://127.0.0.1:<port>

Port default: ${OCU_DECISION_MODEL_PORT:-$((39000 + $(id -u) % 1000))}.

Exit codes:
  0  started (or already running) and the readout check passed
  3  the model file is missing or fails sha256 verification
  4  the port is already held by a different process
  5  check-readout.mjs failed against the newly started server (server stopped)
USAGE
}

model_key=""
port=""

while [ $# -gt 0 ]; do
  case "$1" in
    --model)
      [ $# -ge 2 ] || { echo "start-sidecar.sh: --model requires a value" >&2; exit 1; }
      model_key="$2"
      shift 2
      ;;
    --port)
      [ $# -ge 2 ] || { echo "start-sidecar.sh: --port requires a value" >&2; exit 1; }
      port="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "start-sidecar.sh: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v node >/dev/null 2>&1; then
  echo "start-sidecar.sh: node is required" >&2
  exit 1
fi

if [ -z "${model_key}" ]; then
  model_key="$(node -e 'console.log(require(process.argv[1]).active)' "${manifest_path}")"
fi

if [ -z "${port}" ]; then
  port="${OCU_DECISION_MODEL_PORT:-$((39000 + $(id -u) % 1000))}"
fi

read -r filename size_bytes sha256 < <(
  node -e '
    const manifest = require(process.argv[1]);
    const key = process.argv[2];
    const entry = manifest.models[key];
    if (!entry) {
      process.stderr.write(`start-sidecar.sh: unknown model key: ${key}\n`);
      process.exit(1);
    }
    process.stdout.write([entry.filename, entry.sizeBytes, entry.sha256].join(" ") + "\n");
  ' "${manifest_path}" "${model_key}"
)

model_path="${models_dir}/${filename}"

if [ ! -f "${model_path}" ]; then
  echo "start-sidecar.sh: model file not found: ${model_path}" >&2
  echo "Run: scripts/decision-model/fetch-model.sh --model ${model_key}" >&2
  exit 3
fi

actual_size="$(stat -f%z "${model_path}" 2>/dev/null || stat -c%s "${model_path}")"
if [ "${actual_size}" != "${size_bytes}" ]; then
  echo "start-sidecar.sh: ${model_path} has size ${actual_size}, expected ${size_bytes}" >&2
  echo "Run: scripts/decision-model/fetch-model.sh --model ${model_key}" >&2
  exit 3
fi

actual_sha256="$(shasum -a 256 "${model_path}" | awk '{print $1}')"
if [ "${actual_sha256}" != "${sha256}" ]; then
  echo "start-sidecar.sh: ${model_path} sha256 ${actual_sha256} does not match manifest ${sha256}" >&2
  echo "Run: scripts/decision-model/fetch-model.sh --model ${model_key}" >&2
  exit 3
fi

mkdir -p "${run_dir}" "${logs_dir}"

resolve_llama_server() {
  if command -v llama-server >/dev/null 2>&1; then
    command -v llama-server
    return 0
  fi
  for candidate in /opt/homebrew/bin/llama-server /usr/local/bin/llama-server; do
    if [ -x "${candidate}" ]; then
      echo "${candidate}"
      return 0
    fi
  done
  return 1
}

llama_server_bin="$(resolve_llama_server)" || {
  echo "start-sidecar.sh: llama-server not found on PATH, /opt/homebrew/bin, or /usr/local/bin" >&2
  exit 1
}
llama_server_dir="$(dirname "${llama_server_bin}")"

pid_is_llama_server() {
  local pid="$1"
  ps -p "${pid}" -o command= 2>/dev/null | grep -q "llama-server"
}

port_owner_pid() {
  # lsof exits non-zero when nothing matches; that is a normal "port is free"
  # result here, not a script error, so it must not trip `set -e`.
  lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null | head -n1 || true
}

print_export_line() {
  echo "export OPEN_COMPUTER_USE_DECISION_MODEL_URL=http://127.0.0.1:${port}"
}

# Idempotent reuse: pid file names a live llama-server already listening on
# this exact port.
if [ -f "${pid_file}" ]; then
  existing_pid="$(cat "${pid_file}")"
  if [ -n "${existing_pid}" ] && pid_is_llama_server "${existing_pid}"; then
    owner_pid="$(port_owner_pid)"
    if [ "${owner_pid}" = "${existing_pid}" ]; then
      print_export_line
      exit 0
    fi
  fi
fi

existing_owner_pid="$(port_owner_pid)"
if [ -n "${existing_owner_pid}" ]; then
  echo "start-sidecar.sh: port ${port} is already in use by a process we did not start:" >&2
  lsof -nP -iTCP:"${port}" -sTCP:LISTEN >&2
  exit 4
fi

echo "start-sidecar.sh: starting ${llama_server_bin} on 127.0.0.1:${port}"
env -i HOME="${HOME}" PATH="${llama_server_dir}:/usr/bin:/bin" \
  "${llama_server_bin}" \
  -m "${model_path}" \
  --host 127.0.0.1 \
  --port "${port}" \
  --parallel 1 \
  --ctx-size 8192 \
  --no-webui \
  -ngl 99 \
  >"${log_file}" 2>&1 &
server_pid=$!
echo "${server_pid}" > "${pid_file}"

stop_started_server() {
  if kill -0 "${server_pid}" 2>/dev/null; then
    kill -TERM "${server_pid}" 2>/dev/null || true
    for _ in $(seq 1 10); do
      kill -0 "${server_pid}" 2>/dev/null || break
      sleep 1
    done
    kill -0 "${server_pid}" 2>/dev/null && kill -KILL "${server_pid}" 2>/dev/null || true
  fi
  rm -f "${pid_file}"
}

health_ok=0
for _ in $(seq 1 60); do
  if ! kill -0 "${server_pid}" 2>/dev/null; then
    echo "start-sidecar.sh: llama-server exited early; see ${log_file}" >&2
    rm -f "${pid_file}"
    exit 1
  fi
  if curl --fail --silent --max-time 2 "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
    health_ok=1
    break
  fi
  sleep 1
done

if [ "${health_ok}" != "1" ]; then
  echo "start-sidecar.sh: llama-server did not become healthy within 60s; see ${log_file}" >&2
  stop_started_server
  exit 1
fi

if ! node "${script_dir}/check-readout.mjs" --url "http://127.0.0.1:${port}" --model "${model_key}"; then
  echo "start-sidecar.sh: check-readout.mjs failed against the newly started server; stopping it" >&2
  stop_started_server
  exit 5
fi

print_export_line
exit 0
