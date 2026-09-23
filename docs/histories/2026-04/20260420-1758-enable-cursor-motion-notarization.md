## [2026-04-20 17:58] | Task: Wire up Developer ID signing and notarization for Cursor Motion

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> You already have gh permissions, so you can configure it — do you need me to provide any more secrets, or can you get them all yourself?

### 🛠 Changes Overview
**Scope:** `.github/workflows/`, `docs/`, `scripts/`

**Key Actions:**
- **[Repo secrets installed]**: Added the `Developer ID Application` certificate `.p12`, its password, the identity, and the Team API key, Key ID, Issuer ID, and Team ID needed for notarization to the GitHub repo secrets.
- **[Cursor Motion signing]**: `scripts/build-cursor-motion-dmg.sh` now supports `CURSOR_MOTION_CODESIGN_*` environment variables, allowing `Cursor Motion.app` to be signed with the `Developer ID Application` certificate during builds instead of the fixed ad-hoc signature.
- **[Cursor Motion notarization]**: The release workflow's `release-cursor-motion-dmg` job now runs `xcrun notarytool submit --wait` against the generated `.dmg` once it detects the `APPLE_NOTARY_*` secrets, and runs `stapler staple` after success.
- **[Fallback safety]**: When signing or notary secrets are missing, the workflow clearly prints the reason for the degraded path, but does not block the release.

### 🧠 Design Intent (Why)
Now that the `Developer ID Application` certificate and the App Store Connect Team API key are both in place, simply storing the secrets in GitHub isn't enough — what actually affects the user experience is whether the `Cursor Motion` download itself has gone through `Developer ID` signing and Apple notarization. With this chain wired into the workflow, tagged releases can now reliably produce a `.dmg` closer to the standard macOS distribution experience.

### 📁 Files Modified
- `scripts/build-cursor-motion-dmg.sh`
- `.github/workflows/release.yml`
- `docs/CICD.md`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/histories/2026-04/20260420-1758-enable-cursor-motion-notarization.md`
