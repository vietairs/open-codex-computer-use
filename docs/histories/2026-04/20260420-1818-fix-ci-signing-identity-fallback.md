## [2026-04-20 18:18] | Task: Fix the fallback logic where CI failed to resolve the signing identity after importing the Developer ID certificate

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> Sure, bump the patch version, push the tag, then check the result.

### 🛠 Changes Overview
**Scope:** `.github/workflows/`, `docs/`

**Key Actions:**
- **[Failure Triage]**: Inspected the `v0.1.17` GitHub Actions failure logs and confirmed both `package-npm` and `release-cursor-motion-dmg` exited during the "Prepare ... signing config" stage, because the current parsing logic did not recognize the runner's `security find-identity` output.
- **[Identity Fallback Fix]**: The release workflow now prefers the configured `OPEN_COMPUTER_USE_CODESIGN_IDENTITY` secret as the signing identity, and only attempts to auto-resolve it from the keychain after import when that secret is missing.
- **[Retry Preparation]**: Prepared the fix for re-running the release on the same version, avoiding the case where the `.p12` was correctly imported but the workflow still misjudged "no usable codesigning identity" due to an output-format mismatch.

### 🧠 Design Intent (Why)
This failure wasn't because the certificate itself was unusable — it was because CI's assumptions about `security find-identity` output were too brittle. Since the repo secret already explicitly stores the target `Developer ID Application` CN, the most robust approach is to trust that configuration first, rather than tying the entire release's success to the runner's tool output format.

### 📁 Files Modified
- `.github/workflows/release.yml`
- `docs/histories/2026-04/20260420-1818-fix-ci-signing-identity-fallback.md`
