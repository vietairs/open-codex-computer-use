#!/usr/bin/env bash
# Job body for the `repo-checks` check (ci.yml). The single source of truth for
# what "passing CI" means locally -- `make ci` runs the same script. It re-runs
# check-docs.sh, check-repo-hygiene.sh and check-action-pinning.sh, duplicating
# docs-check.yml and repo-hygiene.yml; that overlap is intentional so a
# contributor running `make ci` sees exactly what CI checks.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

./scripts/ci.sh
