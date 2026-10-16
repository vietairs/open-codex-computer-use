#!/usr/bin/env bash
# Installs the newest go1.27.x linux-amd64 toolchain from go.dev and puts it on
# PATH. SOURCE this script (`. scripts/ci/install-go-linux.sh`) from a leg's
# `setup` so the PATH export reaches the job body; local-ci.mjs legs use it in
# place of actions/setup-go, which the container cannot run.
#
# The go.dev ?mode=json listing already carries the sha256 of every archive, so
# the download is verified with `sha256sum -c` before it is extracted. Needs
# node (for the JSON), curl, tar and write access to /usr/local.
#
# Runs in a subshell-free style on purpose (it must export PATH into the
# caller), so it sets no shell options of its own; each step is checked.

_go_minor="go1.27"
_go_json="$(curl -fsSL 'https://go.dev/dl/?mode=json')" || { echo "go.dev listing fetch failed" >&2; return 1; }
_go_pick="$(printf '%s' "${_go_json}" | node -e '
let s = "";
process.stdin.on("data", (d) => (s += d)).on("end", () => {
  const rel = JSON.parse(s).find((r) => r.version.startsWith(process.argv[1]));
  const f = rel && rel.files.find((x) => x.os === "linux" && x.arch === "amd64" && x.kind === "archive");
  if (!f) { console.error("no linux-amd64 archive for " + process.argv[1]); process.exit(1); }
  console.log(f.filename + " " + f.sha256);
});' "${_go_minor}")" || return 1
_go_file="${_go_pick%% *}"
_go_sha="${_go_pick##* }"
_go_tmp="$(mktemp -d)" || return 1
curl -fsSL -o "${_go_tmp}/${_go_file}" "https://go.dev/dl/${_go_file}" || { rm -rf "${_go_tmp}"; return 1; }
( cd "${_go_tmp}" && echo "${_go_sha}  ${_go_file}" | sha256sum -c - ) || { rm -rf "${_go_tmp}"; return 1; }
tar -C /usr/local -xzf "${_go_tmp}/${_go_file}" || { rm -rf "${_go_tmp}"; return 1; }
rm -rf "${_go_tmp}"
export PATH="${PATH}:/usr/local/go/bin"
unset _go_minor _go_json _go_pick _go_file _go_sha _go_tmp
