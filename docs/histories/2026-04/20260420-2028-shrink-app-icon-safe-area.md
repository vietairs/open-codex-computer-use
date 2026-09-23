## [2026-04-20 20:28] | Task: Adjust Cursor Motion's Dock icon size

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI / zsh / macOS`

### 📥 User Query
> "Let's adjust it so it's the same width and height as other apps."

### 🛠 Changes Overview
**Scope:** `scripts/`, `apps/`, `docs/`

**Key Actions:**
- **[Shrink the icon's effective canvas]**: `scripts/render-open-computer-use-icon.swift` now leaves a `92px` transparent safe margin around the `1024x1024` app icon master, instead of letting the background tile fill the entire canvas.
- **[Sync in-app branding geometry]**: `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`'s `Branding.makeAppIconImage` now uses the same inset, so the packaged icon and the in-app brand graphic geometry no longer diverge.
- **[Calibrate against system icon scale]**: Also compared the `.icns` content boundaries of local `Terminal` / `Notes` / `QuickTime Player`, confirming that the standard Apple icon's horizontal safe margin is roughly `7.8%`, so adjusted the inset from the initial `6%` to a more system-scale-matching `8%`.
- **[Land a checked-in 1024 master]**: Added a `1024x1024` master PNG to the repo, and switched the build script to a `master PNG -> .iconset -> .icns` CLI chain, so future Dock appearance tweaks only require editing this one master.
- **[Fine-tune 2px optical inset]**: Based on subsequent visual inspection, further tightened the `1024x1024` master's effective content boundary from roughly `81...942` to `83...940`, equivalent to shaving another ~`2px` off each side.
- **[Fine-tune 1px optical inset]**: Based on Dock review feedback, further tightened the master's effective content boundary from `83...940` to `84...939`, equivalent to shaving another `1px` off each side.
- **[Switch to a visible step size to keep shrinking]**: Since a `1px` change in the `1024` master is nearly imperceptible once mapped to the Dock, tightened the effective content boundary directly from `84...939` to `92...931`, so the Dock shows a clearly noticeable shrink.
- **[Archive the change]**: Added this history entry documenting the convergence on the Dock icon's effective size.

### 🧠 Design Intent (Why)
The Dock uniformly scales the whole icon canvas, but doesn't apply extra optical correction per app. Previously our icon background filled the canvas edge-to-edge, which made it look noticeably taller than neighboring icons in the same Dock row. Uniformly insetting the effective graphic and aligning it to the common safe-margin scale of local Apple app icons is more stable than continuing to eyeball the Dock rendering; consolidating the icon asset chain down to a single checked-in `1024x1024` master also avoids chasing untraceable micro-adjustments across ad-hoc geometry scripts in the future.

### 📁 Files Modified
- `assets/app-icons/open-computer-use-1024.png`
- `scripts/build-apple-iconset.sh`
- `scripts/render-open-computer-use-icon.swift`
- `scripts/build-open-computer-use-app.sh`
- `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`
- `docs/histories/2026-04/20260420-2028-shrink-app-icon-safe-area.md`
