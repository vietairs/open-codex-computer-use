## [2026-04-20 16:20] | Task: Release 0.1.14

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Commit the related changes and cut another version

### 🛠 Changes Overview
**Scope:** `apps/`, `docs/`, `experiments/`, `packages/`, `plugins/`, `scripts/`

**Key Actions:**
- **[Packaged Glyph Fix]**: Fixed an issue where the packaged `Cursor Motion` app did not ship with the official cursor PNG; the release app now prefers reading `official-software-cursor-window-252.png` from bundle resources, no longer silently falling back to the lower-fidelity procedural glyph.
- **[DMG Script Sync]**: `scripts/build-cursor-motion-dmg.sh` now copies the official cursor PNG into `Contents/Resources/`, and explicitly writes `NSHighResolutionCapable=true`, so the packaged build looks more consistent with `swift run CursorMotion`.
- **[Version Bump]**: Uniformly raised the plugin manifest, Swift/Go version constants, the smoke suite's initialization version, the client version in unit tests, and the CLI doc path to `0.1.14`.
- **[Release Notes]**: Appended `0.1.14` to `docs/releases/feature-release-notes.md`, documenting this round's fix for visual consistency of the packaged `Cursor Motion`.
- **[Validation]**: Re-ran `swift test`, the npm staging build, and the `Cursor Motion` DMG packaging, and directly checked the staging package version and the `CursorMotion-0.1.14.dmg` artifact, confirming the release inputs are fully settled on `0.1.14`.

### 🧠 Design Intent (Why)
This round is not about further changing the curve algorithm itself, but about fixing the resource-environment gap between the release app and the source-run version. The user had already clearly seen the DMG build show a more jagged cursor with the wrong orientation; without settling the bundle resources and the version together, the release page would keep distributing a build with a visibly degraded result.

### 📁 Files Modified
- `experiments/CursorMotion/Sources/CursorMotion/SynthesizedCursorGlyphView.swift`
- `scripts/build-cursor-motion-dmg.sh`
- `plugins/open-computer-use/.codex-plugin/plugin.json`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/OpenComputerUseVersion.swift`
- `apps/OpenComputerUseSmokeSuite/Sources/OpenComputerUseSmokeSuite/main.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/computer-use-cli/main.go`
- `scripts/computer-use-cli/README.md`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/releases/feature-release-notes.md`
- `docs/exec-plans/active/20260418-standalone-cursor-lab.md`
- `docs/histories/2026-04/20260418-1430-standalone-cursor-lab.md`
- `docs/histories/2026-04/20260420-1620-bump-open-computer-use-to-0.1.14.md`
