## [2026-10-15 15:00] | Task: Reject degenerate Windows screenshots

### Execution Context
* **Agent ID**: `hvn-implementer`
* **Base Model**: `Claude Sonnet 5.5`
* **Runtime**: `Claude Code / macOS arm64` (Go host tests only; no Windows desktop available)

### User Query
> Port the upstream Windows fix so Computer Use no longer returns a 1x1 or otherwise unusable screenshot; in extreme cases no screenshot is acceptable, but a fake one is not.

### Changes Overview
**Scope:** Windows Go runtime, PowerShell UI Automation bridge, tests, and screenshot-behavior docs.

**Key Actions:**
- **Window capture gate**: before capturing, the main window must be visible, not minimized, not DWM-cloaked, and intersect the virtual screen, with width and height of at least 64 pixels and an area of at least 20,000 pixels. `list_apps` keeps listing every running app with a main window and annotates the ones that fail the same rule with `screenshot=unavailable (<reason>)`, so a minimized or other-desktop app is never reported as not running.
- **PNG defense in depth**: the Go layer reads the PNG header (streamed, not fully decoded) again before building the MCP result and applies the same size threshold together with the window bounds. An invalid image is removed from both the snapshot cache and the image content; nothing is upscaled, padded, or replaced by a placeholder.
- **Fail-closed coordinates**: without a usable screenshot the accessibility tree and an explanatory note are still returned, but coordinate click / drag fail with a clear error; element-targeted UI Automation actions are still attempted, and the PowerShell bridge re-checks the snapshot bounds and the live window state (visible, not minimized, not cloaked) before any coordinate fallback. The scroll request now carries the snapshot window bounds, so the window-message scroll fallback keeps working on a healthy visible window, and wheel messages are posted with screen coordinates as Windows expects.
- **Resource safety**: bitmap, graphics, and memory stream are released in `finally` on both success and failure paths.
- **Regression coverage**: new tests for PNG size/format validation, snapshot image omission, coordinate-action refusal, and the PowerShell guard snippets.

### Design Intent (Why)
Screenshot coordinates only mean something when the frame is real, visible, and large enough to act on. A well-formed PNG for a 1x1 or invalid window would defer a window-state problem into an upstream model error and could land coordinate actions in the wrong place. Keeping the usable semantic tree, omitting the image, and blocking coordinate actions is safer than fabricating visual state.

### Files Modified
- `apps/OpenComputerUseWindows/main.go`
- `apps/OpenComputerUseWindows/main_test.go`
- `apps/OpenComputerUseWindows/runtime.ps1`
- `docs/ARCHITECTURE.md`
- `docs/QUALITY_SCORE.md`
- `docs/RELIABILITY.md`
- `docs/SECURITY.md`
- `docs/releases/feature-release-notes.md`
- `skills/open-computer-use/references/troubleshooting.md`

### Validation
- `(cd apps/OpenComputerUseWindows && go test ./...)` passes on the macOS host; `go vet` passes for the host and for `GOOS=windows GOARCH=amd64`.
- Not run: the PowerShell bridge itself and the interactive-desktop checks (normal window returns an image; 1x1, minimized, and cloaked windows return none), because they need a Windows desktop session. The bridge is covered only by the snippet-presence tests; the Go service is covered by tests that stub the PowerShell bridge and assert the scroll request fields and the element-click and coordinate-click pass-through behavior.
