#!/usr/bin/env bash
#
# Stop the llama-server sidecar started by start-sidecar.sh. Only ever signals
# the exact pid recorded in the pid file, and only while that pid still has the
# recorded start time and the kernel reports it running the recorded
# llama-server binary (see sidecar-pid-lib.sh), so it never kills an unrelated
# process that reused the pid or merely mentions llama-server in its argv.
#
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sidecar-pid-lib.sh
. "${script_dir}/sidecar-pid-lib.sh"
state_dir="${HOME}/Library/Application Support/OpenComputerUse/decision-model"
pid_file="${state_dir}/run/llama-server.pid"

usage() {
  cat <<'USAGE'
Usage: scripts/decision-model/stop-sidecar.sh

Stops the llama-server sidecar recorded in
  "$HOME/Library/Application Support/OpenComputerUse/decision-model/run/llama-server.pid"
with SIGTERM, waiting up to 10s, then SIGKILL if still alive, and removes the
pid file.

Exit codes:
  0  stopped, or nothing recorded is running (a stale pid file is removed)
  1  the recorded pid is running but cannot be verified as the sidecar; nothing
     was signalled and the pid file was left for inspection
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

if ! sidecar_pid_file_read "${pid_file}"; then
  legacy_pid="$(sidecar_pid_file_legacy_pid "${pid_file}")"
  if [ -n "${legacy_pid}" ] && kill -0 "${legacy_pid}" 2>/dev/null; then
    echo "stop-sidecar.sh: ${pid_file} is in an old or unreadable format and names running pid ${legacy_pid}; refusing to signal it." >&2
    echo "Stop it yourself if it is a sidecar, then delete the pid file." >&2
    exit 1
  fi
  echo "stop-sidecar.sh: ${pid_file} is unreadable and names no running process; removing it."
  rm -f "${pid_file}"
  exit 0
fi

sidecar_pid_state
case "${pf_state}" in
  stale)
    echo "stop-sidecar.sh: the recorded sidecar (pid ${pf_pid}) is no longer running; removing stale pid file."
    rm -f "${pid_file}"
    exit 0
    ;;
  unverified)
    echo "stop-sidecar.sh: pid ${pf_pid} does not run the recorded binary ${pf_binary}; refusing to signal it." >&2
    echo "The pid file was left at ${pid_file} for inspection." >&2
    exit 1
    ;;
esac

pid="${pf_pid}"
echo "stop-sidecar.sh: stopping llama-server pid ${pid}"
kill -TERM "${pid}" 2>/dev/null || true

for _ in $(seq 1 10); do
  kill -0 "${pid}" 2>/dev/null || break
  sleep 1
done

if kill -0 "${pid}" 2>/dev/null; then
  # Re-verify before escalating: 10 s is long enough for the pid to be reused.
  sidecar_pid_state
  if [ "${pf_state}" = "owned" ]; then
    echo "stop-sidecar.sh: pid ${pid} still alive after SIGTERM; sending SIGKILL"
    kill -KILL "${pid}" 2>/dev/null || true
  fi
fi

rm -f "${pid_file}"
echo "stop-sidecar.sh: stopped."
exit 0
