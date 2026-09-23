## [2026-04-20 17:40] | Task: Prepare Developer ID signing assets and restore the optional CI signing path

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> Just go ahead and do it, call me back when you can't proceed or need me.

### 🛠 Changes Overview
**Scope:** `.github/workflows/`, `docs/`, `scripts/`

**Key Actions:**
- **[Developer ID Asset Prep]**: Imported the `Developer ID Application` certificate the user issued locally from a CSR into `login.keychain-db`, confirmed a usable codesigning identity exists, and exported a reusable local `.p12` asset.
- **[CI Signing Fix]**: Fixed an issue in `scripts/build-open-computer-use-app.sh` where, when using a temporary keychain, only passing the keychain to `codesign --keychain` without adding it to the user's search list caused "item could not be found in the keychain."
- **[Workflow Restore]**: Restored the release workflow's optional certificate import step; when `OPEN_COMPUTER_USE_CODESIGN_*` is configured in repo secrets, CI imports the `.p12` and uniformly signs the npm release `.app` with the `Developer ID Application` identity, falling back to ad-hoc signing when not configured.
- **[Docs Sync]**: Synced the CI/CD and release guides to clarify the current state: "Open Computer Use has optional Developer ID signing, Cursor Motion is still ad-hoc, and notarization is not yet wired up."

### 🧠 Design Intent (Why)
The user has already completed the CSR on their own machine and issued a `Developer ID Application` certificate on the Apple Developer website using the team account. At this point, the priority is not to keep dwelling on "how to obtain the materials," but to actually turn this certificate into a usable `.p12` asset for CI, and restore the repo's signing path to a state where "signing is unified when a secret is present, and releases aren't blocked when it isn't." This leaves only two external dependencies remaining: GitHub secrets and notarization.

### 📁 Files Modified
- `scripts/build-open-computer-use-app.sh`
- `.github/workflows/release.yml`
- `docs/CICD.md`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/histories/2026-04/20260420-1740-prepare-developer-id-signing-assets.md`
