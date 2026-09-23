## [2026-04-22 10:50] | Task: Align with the official `set_value` settable boundary

### User Request

> Handle the `set_value` failure path for apps like Sublime the "official" way.

### This Change

- **Tighten the `set_value` boundary**: for real apps, `set_value` now first checks `AXUIElementIsAttributeSettable(kAXValueAttribute)`, and only calls `AXUIElementSetAttributeValue` once the target is confirmed settable.
- **Official-style error**: for elements like Sublime's, where `AXValue` is readable but not settable, return `Cannot set a value for an element that is not settable` instead of exposing the raw `AXUIElementSetAttributeValue failed with -25200`.
- **Avoid semantic drift**: `set_value` does not fall back internally to `type_text`, the clipboard, or the undocumented `AXReplaceRangeWithText`, keeping its semantics scoped to "set a settable accessibility element".
- **Add regression tests and architecture notes**: add unit tests for the settable gate, and sync the action-tool boundary in `docs/ARCHITECTURE.md`.

### Design Intent

The official bundled app's tool description and its binary error text both indicate that `set_value` targets settable accessibility elements. Sublime's body node can have its `AXValue` read, but `AXUIElementIsAttributeSettable(kAXValueAttribute)` returns success + false; forcing `AXUIElementSetAttributeValue` in that case only produces the underlying `kAXErrorFailure(-25200)`. Gating on settability up front lets the failure be explained as a capability boundary, rather than disguised as an input-simulation failure.

### Files Affected

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
