#!/usr/bin/env bash
#
# Stop the llama-server sidecar started by start-sidecar.sh. Only ever signals
# the pid recorded in the pid file, and only if that pid's command line still
# names llama-server, so it never kills an unrelated process that reused the
# pid.
#
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
state_dir="${HOME}/Library/Application Support/OpenComputerUse/decision-model"
pid_file="${state_dir}/run/llama-server.pid"

usage() {
  cat <<'USAGE'
Usage: scripts/decision-model/stop-sidecar.sh

Stops the llama-server sidecar recorded in
  "$HOME/Library/Application Support/OpenComputerUse/decision-model/run/llama-server.pid"
with SIGTERM, waiting up to 10s, then SIGKILL if still alive. Removes the pid
file afterward. Exits 0 whether or not a process was actually running.
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ ! -f "${pid_file}" ]; then
  echo "stop-sidecar.sh: no pid file at ${pid_file}; nothing to stop."
  exit 0
fi

pid="$(cat "${pid_file}")"

if [ -z "${pid}" ] || ! kill -0 "${pid}" 2>/dev/null; then
  echo "stop-sidecar.sh: pid ${pid:-<empty>} is not running; removing stale pid file."
  rm -f "${pid_file}"
  exit 0
fi

if ! ps -p "${pid}" -o command= 2>/dev/null | grep -q "llama-server"; then
  echo "stop-sidecar.sh: pid ${pid} is running but is not llama-server; refusing to signal it." >&2
  rm -f "${pid_file}"
  exit 0
fi

echo "stop-sidecar.sh: stopping llama-server pid ${pid}"
kill -TERM "${pid}" 2>/dev/null || true

for _ in $(seq 1 10); do
  kill -0 "${pid}" 2>/dev/null || break
  sleep 1
done

if kill -0 "${pid}" 2>/dev/null; then
  echo "stop-sidecar.sh: pid ${pid} still alive after SIGTERM; sending SIGKILL"
  kill -KILL "${pid}" 2>/dev/null || true
fi

rm -f "${pid_file}"
echo "stop-sidecar.sh: stopped."
exit 0
