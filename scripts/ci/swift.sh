#!/usr/bin/env bash
# Job body for the `swift` check (ci.yml): compile and test the Swift package.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

swift build
swift test
