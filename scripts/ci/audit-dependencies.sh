#!/usr/bin/env bash
# Job body for the `audit-dependencies` check (supply-chain-security.yml).
# See the header of that workflow for why the Go toolchain pin must match
# ci.yml and release.yml.
#
# GOVULNCHECK_VERSION is pinned rather than a floating @latest tag: this
# repository requires SHA-pinned actions, and check-action-pinning.sh only
# inspects action reference lines, so an unpinned tool fetched inside a script
# would slip past the gate it exists to enforce. Each govulncheck release
# carries its own minimum go directive (v1.2.0 already needs 1.25, v1.8.0 needs
# 1.26), which is why the go-version minor cannot drop below 1.26. Verified
# against the module proxy; when raising this, check that minimum still holds.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

GOVULNCHECK_VERSION="${GOVULNCHECK_VERSION:-v1.8.0}"

if [ -f package-lock.json ]; then
  npm audit --audit-level=high
else
  echo "No package-lock.json in this repo; nothing for npm audit to check."
fi

# Enumerate into a file so a failure of `find` itself is visible.
# In `for x in $(find ...)` the command substitution's exit status is
# discarded, so a broken path would silently produce an empty list
# and a reassuring "nothing to check".
gomods_file="$(mktemp)"
trap 'rm -f "${gomods_file}"' EXIT
find . -name go.mod -not -path './.build/*' -not -path './node_modules/*' | sort > "${gomods_file}"
if [ ! -s "${gomods_file}" ]; then
  echo "No go.mod found anywhere in the repository." >&2
  exit 1
fi

echo "Go modules discovered:"
cat "${gomods_file}"

# Every module is scanned, including ones with no `require` at all.
# A module with no third-party dependency is NOT uninteresting: it
# still links the standard library, and the standard library is where
# this repository's actual exposure has been. apps/OpenComputerUseLinux
# and apps/OpenComputerUseWindows declare zero requirements and ship as
# the bundled runtimes inside the npm tarballs; scanned under the
# toolchain that builds them they reported three call-reachable stdlib
# advisories (GO-2025-3956 in os/exec, GO-2025-3750 in syscall,
# GO-2026-4602). An earlier revision skipped exactly those two modules
# on the theory that "no require" means "nothing to check".
while IFS= read -r gomod; do
  module_dir="$(dirname "${gomod}")"
  echo "Running govulncheck in ${module_dir}"
  (
    cd "${module_dir}"
    go run "golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION}" ./...
  )
done < "${gomods_file}"
