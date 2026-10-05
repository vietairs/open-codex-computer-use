#!/usr/bin/env bash
# Job body for the `check-docs` check (docs-check.yml).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

./scripts/check-docs.sh
