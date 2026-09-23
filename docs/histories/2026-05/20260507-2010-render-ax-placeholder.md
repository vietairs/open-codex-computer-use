# Render the AX placeholder value

## User Ask

Continue aligning the open-source `open-computer-use`'s app-state output with the official `computer-use`, especially the output shape for complex AX trees like Electron / Browser.

## Main Changes

- Read `AXPlaceholderValue` / `AXPlaceholder` in the AX renderer.
- When the placeholder differs from title, description, or value, append `Placeholder: ...` to the corresponding element row.
- Added a unit test for the placeholder segment, to avoid re-rendering a description or an existing value redundantly.

## Design Intent

The official Chrome output keeps the placeholder on address-bar elements, e.g. `Ask Google or type a URL`. The open-source version previously only output description and value, missing this semantic field, so browser / Electron app-state info was less complete than the official one.

## Verification

- Local Chrome regression confirms the address-bar row includes `Placeholder: Ask Google or type a URL`.
- `swift test --filter AccessibilityRendererFormatsPlaceholderSegment`
- `./scripts/build-open-computer-use-app.sh debug`

## Files Affected

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
