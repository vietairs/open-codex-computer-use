#!/usr/bin/env bash
# Job body for the `swift` check (ci.yml): compile and test the Swift package.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# Live-desktop tests are opt-in through these variables; make sure a stray value
# in the runner user's environment cannot make CI drive the real desktop.
unset OPEN_COMPUTER_USE_RUN_SKY_CLICK_LIVE_TEST OPEN_COMPUTER_USE_LIVE_PROBE

swift build
swift test
