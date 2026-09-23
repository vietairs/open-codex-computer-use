## [2026-04-20 18:28] | Task: Fix release codesign identity resolution

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5.4`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> Commit the related changes, then add a version-numbered git tag and push it to trigger a run and see.

### 🛠 Changes Overview
**Scope:** `.github/workflows/`, `docs/`

**Key Actions:**
- **[CI Signing Resolution]**: Change the release workflow's signing config from "trust the identity name stored directly in the repo secret" to "after importing the `.p12`, resolve the first available codesigning identity directly from the temporary keychain", avoiding `codesign: no identity found` on the runner.
- **[Runner Keychain Compatibility]**: Add a step that adds the temporary keychain to the user search list and sets it as the default keychain, so that `security find-identity` and the subsequent `codesign` calls both go through the default search chain, avoiding the instability of looking up an identity directly by `.keychain-db` path on the GitHub macOS runner.
- **[Failure Recording]**: Add a history entry recording why `package-npm` failed at the `Build npm release artifacts` stage on the first `v0.1.15` tag push, and how it was fixed.

### 🧠 Design Intent (Why)
This time the problem wasn't that the certificate failed to import, but that the workflow's resolution of the identity name was too fragile. Since the `.p12` is already the true source of the signature, the most robust approach is to let CI discover the available identity itself after importing, rather than continuing to depend on a manually maintained CN string.

### 📁 Files Modified
- `.github/workflows/release.yml`
- `docs/histories/2026-04/20260420-1828-fix-release-codesign-identity-resolution.md`
