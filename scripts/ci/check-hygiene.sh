#!/usr/bin/env bash
# Job body for the `check-hygiene` check (repo-hygiene.yml).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

./scripts/check-repo-hygiene.sh
./scripts/check-action-pinning.sh
