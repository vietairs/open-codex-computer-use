# Fix the CLI's numeric element_index argument

## User Request

Fix Issue #18: `open-computer-use call click --args '{"app":"TextEdit","element_index":0}'` incorrectly reports `click requires either element_index or x/y`, because the CLI's JSON parses `0` as a number while the dispatcher only accepts a string.

## Main Changes

- Added `element_index`-specific normalization logic to the Swift `ComputerUseToolDispatcher`, allowing a JSON numeric index to be converted to a string index, while keeping the tool schema's `string` type unchanged.
- `click`, `perform_secondary_action`, `scroll`, and `set_value` all now use this dedicated read logic.
- The Windows and Linux Go runtimes likewise accept a numeric `element_index`, keeping CLI argument behavior consistent across all three platforms.
- Updated the skill doc examples to use the canonical string form, so they stop steering users toward passing numbers.
- Added Swift / Go unit tests covering string indices, numeric indices, and rejection of fractional indices.

## Design Intent

The official tool surface exposes `element_index` as a string, and this repo should keep following that schema; but when hand-writing CLI JSON, users naturally write the index as a number. Having the parsing layer tolerantly convert an integer number to a string is compatible with commands produced by the existing misleading docs, without widening the accepted type for other string arguments.

## Files Affected

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseToolDispatcher.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `apps/OpenComputerUseWindows/main.go`
- `apps/OpenComputerUseWindows/main_test.go`
- `apps/OpenComputerUseLinux/main.go`
- `apps/OpenComputerUseLinux/main_test.go`
- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/usage.md`
