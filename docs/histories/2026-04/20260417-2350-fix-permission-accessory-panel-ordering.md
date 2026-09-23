## [2026-04-17 23:50] | Task: Fix the permission drag panel being obscured by the System Settings window

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> The drag-hint bar in the permission onboarding flow is still covered by the `System Settings` window; it needs to stay displayed above the System Settings window.

### 🛠 Changes Overview
**Scope:** `apps/OpenComputerUse`, `docs/`

**Key Actions:**
- **[Window Ordering]**: Changed the permission accessory panel to the `.floating` level, and explicitly `order(.above, relativeTo:)` the current `System Settings` main window when shown.
- **[Window Targeting]**: Read both the bounds and `windowNumber` of `System Settings` from `CGWindowList`, so positioning logic and ordering logic are both based on the same real window context.
- **[AX Polling Tuning]**: Changed the AX scan of the controls row to a low-frequency cache, forcing a refresh only on scroll/drag, to avoid high-frequency traversal of the `System Settings` AX tree triggering repeated jitter in the left-hand scrollbar.
- **[Anchor Clamp & Reorder Debounce]**: Only re-`order(.above)` when the target `System Settings` window number changes, and added an upward-lift cap for the controls row it follows; after scrolling to the middle section, the hint bar no longer follows into the middle of the list and instead falls back to sitting near the bottom edge of the window.
- **[Remove AX Anchor Scanning]**: Ultimately removed the timed/event-driven AX probing of the `+ / -` control row inside `System Settings`; the accessory bar now sticks to the bottom purely based on window bounds, fully cutting off the continuous cross-process access to the System Settings UI tree.
- **[Coordinate System Fix]**: Convert the Quartz window bounds returned by `CGWindowList` into AppKit screen coordinates before using them for panel positioning, fixing the accessory bar drifting in the wrong direction when the window is dragged up or down.
- **[Drag Bundle Fallback]**: When the permission onboarding flow is launched via `swift run OpenComputerUse`, the drag tile now automatically falls back to the in-repo `dist/Open Computer Use.app`, avoiding a failure to drag out the permission entry just because the current process isn't a `.app` bundle.
- **[Permission Identity Alignment]**: Permission-state queries no longer look only at `Bundle.main.bundleIdentifier`; when onboarding actually guides the user to drag in the packaged `.app` from the repo, the TCC query switches to that real app bundle's identifier, avoiding the situation where `Open Computer Use` already shows up in the list but the UI still doesn't display `Done`.
- **[Valid Bundle Guard]**: When falling back to `dist/Open Computer Use.app`, it first verifies the bundle contains `Info.plist`, has an executable, and has the correct bundle id, avoiding dragging an empty shell directory into System Settings and ending up with a missing icon, a broken drag badge, or a permission state that never converges.
- **[Path-Based TCC Detection]**: Adapted to the case where macOS TCC stores the `Open Computer Use.app` authorization record as a `client_type=1` path entry; the permission query now checks both the app path and the bundle identifier, so it no longer gets stuck on `Allow` just because the entry is authorized in System Settings but the database key isn't the bundle id.
- **[Cold Launch Bootstrap Retry]**: When `Allow` triggers a first cold launch of `System Settings`, the accessory panel now retries mounting for a short period until the System Settings window is actually ready, avoiding the timing issue where "the floating panel isn't visible the first time System Settings comes up, and only appears after switching away and back."
- **[Docs Sync]**: Updated the architecture docs to note that this permission onboarding panel now stays above the `System Settings` window.

### 🧠 Design Intent (Why)
This problem is half about window level, half about refresh strategy. The panel originally sat at `.normal` and only did `orderFront`, which made it easy for a foreground `System Settings` window at the same level to cover it; at the same time, in order to stay anchored to the `+ / -` control row, we were continuously reading `System Settings`'s internal UI tree over the Accessibility IPC channel. For a SwiftUI system page like this, that "read" is not fully static or side-effect-free — it was enough to disturb the repaint cadence of the scroll area and overlay scrollbar. The final converged approach was to promote the panel to an accessory floating layer, explicitly order it relative to the target window, and fully drop the internal AX anchor scanning, sticking to the bottom purely by window bounds — only that combination reliably satisfies "always stay above the window without disturbing System Settings' own scrolling behavior."

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260417-2350-fix-permission-accessory-panel-ordering.md`
