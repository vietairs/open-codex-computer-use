## [2026-04-19 21:35] | Task: Tighten the permission accessory panel's entrance animation and back interaction

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Take a look at permiso for reference. Let's improve the permission accessory panel — mainly the entrance animation after clicking allow, and a back button inside the panel.

### 🛠 Changes Overview
**Scope:** `apps/OpenComputerUse`, `docs/`

**Key Actions:**
- **[Allow Source Tracking]**: Propagated the `Allow` button's screen coordinates from the main onboarding card through the delegate chain to the accessory panel controller, so the panel can get an explicit source frame the first time it appears.
- **[Launch Transition]**: Added a spring + curved-frame entrance animation for the permission panel, modeled after `permiso`; this transition still runs the first time the panel actually attaches to the target window, even when `System Settings` cold-starts or its window becomes ready only later.
- **[Post-Launch Reanchor]**: Changed panel positioning from "stop retrying after a few attempts on cold start" to continuously tracking `System Settings`' window frame via a `.common` run loop timer throughout guidance, with a few extra settle passes before and after launch completes, fixing the issue where the panel would be left at a stale position after the system window settles again post-animation, requiring a manual click to realign.
- **[Back Affordance]**: Added a material-style back button to the accessory panel and wired its click action back to the onboarding main window: hide the current guidance, restore the card list, and reactivate the app.
- **[Drag Polish]**: The drag tile now springs back to its initial position on cancel or failure, reducing the disjointed feel against the new panel transition.
- **[Docs Sync]**: Updated the architecture doc to record that the permission panel now has a source-to-target entrance and an explicit back button.

### 🧠 Design Intent (Why)
This round isn't about expanding the permission feature's scope further, but about tightening the interaction feel. The existing implementation can already jump pages, track the window, and drag, but the panel after `Allow` still appeared with a "hard cut," falling short of the guided feel of the official implementation / `permiso`, which flies in from the trigger point into `System Settings`; meanwhile the panel lacked a back affordance, so once a user wanted to interrupt the current step, they had to switch back to the main window themselves. With the source-tracked transition and back button filled in, the pacing of permission guidance is more coherent, and it's easier to switch back and forth between the two permissions.

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260419-2135-refine-permission-panel-transition-and-back-button.md`
