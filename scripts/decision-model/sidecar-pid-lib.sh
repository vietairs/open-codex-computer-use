#!/usr/bin/env bash
#
# Sourced by start-sidecar.sh and stop-sidecar.sh. Reads the sidecar pid file and decides whether the pid it names is
# still the llama-server that start-sidecar.sh launched.
#
# Ownership needs all three of: the exact recorded pid, an unchanged process start time (so a reused pid never
# matches), and the kernel's executable path for that pid equal to the recorded llama-server binary. The executable
# path comes from lsof's first txt entry, which a process cannot rename; argv and `ps -o comm=` are not used, because
# `exec -a` sets both to anything.
#
# The pid file holds key=value lines (pid, port, lstart, binary, model). The Swift client reads the same file before
# it sends anything to the sidecar (DecisionSidecarVerifier.swift), so keep the two in step.

# `ps -o lstart=` output depends on the locale; pin it so writer and reader always agree.
sidecar_process_start_time() {
  { LC_ALL=C ps -p "$1" -o lstart= 2>/dev/null || true; } | sed -e 's/[[:space:]]*$//'
}

# lsof -Fn prints a "p<pid>" line, then "f<fd>" / "n<name>" pairs; the first txt name is the program image.
# Both helpers print nothing (and succeed) for a pid that is gone, so callers under `set -eo pipefail` keep going.
sidecar_process_executable() {
  { lsof -a -p "$1" -d txt -Fn 2>/dev/null || true; } | awk '/^n/ { print substr($0, 2); exit }' || true
}

sidecar_canonical_path() {
  realpath "$1" 2>/dev/null
}

# Writes the pid file atomically with mode 0600.
sidecar_pid_file_write() {
  local file="$1" pid="$2" port="$3" binary="$4" model="$5" lstart
  lstart="$(sidecar_process_start_time "${pid}")"
  (
    umask 077
    printf 'pid=%s\nport=%s\nlstart=%s\nbinary=%s\nmodel=%s\n' "${pid}" "${port}" "${lstart}" "${binary}" "${model}" \
      > "${file}.tmp"
  )
  mv -f "${file}.tmp" "${file}"
}

# Sets pf_pid, pf_port, pf_lstart, pf_binary, pf_model. Returns 1 when the file is missing or not in this format.
sidecar_pid_file_read() {
  local file="$1" line
  pf_pid=""
  pf_port=""
  pf_lstart=""
  pf_binary=""
  pf_model=""
  [ -f "${file}" ] || return 1
  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
      pid=*) pf_pid="${line#pid=}" ;;
      port=*) pf_port="${line#port=}" ;;
      lstart=*) pf_lstart="${line#lstart=}" ;;
      binary=*) pf_binary="${line#binary=}" ;;
      model=*) pf_model="${line#model=}" ;;
    esac
  done < "${file}"
  [[ "${pf_pid}" =~ ^[0-9]+$ ]] && [ "${pf_pid}" -gt 1 ] \
    && [[ "${pf_port}" =~ ^[0-9]+$ ]] \
    && [ -n "${pf_lstart}" ] \
    && [[ "${pf_binary}" == /* ]]
}

# Sets pf_state for the pid file, after sidecar_pid_file_read has filled pf_*:
#   owned       the recorded pid is alive, started at the recorded time, and runs the recorded llama-server binary
#   stale       the recorded process is gone: the pid is dead, belongs to another user, or was reused (start time
#               differs), so the record can be discarded without signalling anything
#   unverified  the same process instance (pid and start time match) no longer runs the recorded binary; never
#               signal it and never discard the record automatically
sidecar_pid_state() {
  local actual_start actual_executable recorded_binary
  if ! kill -0 "${pf_pid}" 2>/dev/null; then
    pf_state="stale"
    return 0
  fi
  actual_start="$(sidecar_process_start_time "${pf_pid}")"
  if [ -z "${actual_start}" ] || [ "${actual_start}" != "${pf_lstart}" ]; then
    pf_state="stale"
    return 0
  fi
  pf_state="unverified"
  [ "$(basename "${pf_binary}")" = "llama-server" ] || return 0
  actual_executable="$(sidecar_process_executable "${pf_pid}")"
  [ -n "${actual_executable}" ] || return 0
  recorded_binary="$(sidecar_canonical_path "${pf_binary}")" || return 0
  [ -n "${recorded_binary}" ] || return 0
  if [ "$(sidecar_canonical_path "${actual_executable}")" = "${recorded_binary}" ]; then
    pf_state="owned"
  fi
}

# The first number on the first line of an unreadable (for example old, pid-only) pid file, or empty.
sidecar_pid_file_legacy_pid() {
  { head -n1 "$1" 2>/dev/null || true; } | tr -cd '0-9'
}
