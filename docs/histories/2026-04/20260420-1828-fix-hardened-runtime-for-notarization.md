## [2026-04-20 18:28] | Task: Fix missing hardened runtime for Cursor Motion notarization

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> Sure, bump the patch version, tag and push it, then check the result.

### 🛠 Changes Overview
**Scope:** `docs/`, `scripts/`

**Key Actions:**
- **[Failure triage]**: Pulled the Apple notary log for `v0.1.17` and confirmed the direct reason the `.dmg` was marked `Invalid` was that `Cursor Motion.app/Contents/MacOS/CursorMotion` didn't have hardened runtime enabled on either the `arm64` or `x86_64` architecture.
- **[Runtime signing fix]**: `build-open-computer-use-app.sh` and `build-cursor-motion-dmg.sh` now explicitly pass `codesign --options runtime` when signing with a non-ad-hoc identity.
- **[Next release prep]**: Prepared for a subsequent new patch release, to avoid continuing to reuse the `0.1.17` publish result, which had already been published to npm successfully but had failed notarization.

### 🧠 Design Intent (Why)
The Apple notary service requires hardened runtime for executables distributed via Developer ID. The repo had already switched to `Developer ID Application` signing, but had not turned on `--options runtime` at the same time, so it was directly rejected during notarization by Apple. Adding this signing flag now satisfies the minimum bar for notarization.

### 📁 Files Modified
- `scripts/build-open-computer-use-app.sh`
- `scripts/build-cursor-motion-dmg.sh`
- `docs/histories/2026-04/20260420-1828-fix-hardened-runtime-for-notarization.md`
