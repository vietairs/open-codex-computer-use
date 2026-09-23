## [2026-04-20 16:08] | Task: Converge Open Computer Use's cross-channel app identity

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> The authorization prompted by `npm i -g open-computer-use && open-computer-use`, and the authorization prompted by `./scripts/build-open-computer-use-app.sh debug` / `./dist/Open Computer Use.app/Contents/MacOS/OpenComputerUse` in the repo, get recognized by the system as two different apps. Regardless of the install channel — npm / brew / dmg / whatever — the identity should be the same; it shouldn't keep splitting into multiple authorization objects. Also need to further confirm whether the package built via GitHub Actions on npmjs is affected by this same issue.

### 🛠 Changes Overview
**Scope:** `packages/OpenComputerUseKit`, `scripts/`, `.github/workflows/`, `README`, `docs/`

**Key Actions:**
- **[Unified Codesign Path]**: Added a unified codesign entry point to `scripts/build-open-computer-use-app.sh`, supporting an explicit identity, auto-discovery of a local Apple signing identity, and ad-hoc/skip fallback, with an explicit warning in the ad-hoc case that TCC may still recognize different builds as different apps.
- **[Channel-Agnostic Bundle Discovery]**: Changed permission-target discovery from "prefer the npm global path" to "uniformly discover the same-bundle app across the currently running copy, `/Applications`, npm, Homebrew, and other channels, then prefer the stable installed copy as the permission target" — reducing channel bias while avoiding a transient running copy taking priority over the long-lived authorized target.
- **[CI Release Signing]**: Added an optional certificate-import step to `release.yml`; when the `OPEN_COMPUTER_USE_CODESIGN_*` secrets are configured, the npm package built by GitHub Actions is packaged with a unified codesign identity, preventing the `.app` on npmjs from continuing to split TCC identity due to being ad-hoc/unsigned.
- **[Docs Sync]**: Updated the README, architecture, and CI/CD docs to say that the official release channels converge via the same bundle id + the same signing identity, rather than writing the npm path as the sole long-term authorization target.

### 🧠 Design Intent (Why)
macOS's TCC doesn't look only at `CFBundleIdentifier` — it also factors the code requirement into identity determination. Unifying only the bundle id while each channel keeps producing ad-hoc or unofficially-signed `.app` bundles still leaves the permission entries split. To truly converge npm / brew / dmg into a single app, they must share the same bundle identifier and the same official signing chain; when the source-debug build doesn't have that signing chain, the user needs to be told explicitly that this is a degraded mode, rather than pretending it's "already the same app."

### 📁 Files Modified
- `.github/workflows/release.yml`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Permissions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/build-open-computer-use-app.sh`
- `README.md`
- `README.zh-CN.md`
- `docs/ARCHITECTURE.md`
- `docs/CICD.md`
- `docs/histories/2026-04/20260420-1608-unify-open-computer-use-app-identity.md`
