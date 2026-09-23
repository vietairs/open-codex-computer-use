## [2026-09-23 10:25] | Task: Notarize the Open Computer Use.app bundle

### Execution Context
* **Agent ID**: `fullstack-developer`
* **Base Model**: `claude-sonnet-5`
* **Runtime**: `Claude Code, macOS arm64, git worktree`

### User Query
> Add notarization for `Open Computer Use.app`: extend `scripts/build-open-computer-use-app.sh` to notarize the final signed bundle with `xcrun notarytool` and staple the ticket, controlled by `OPEN_COMPUTER_USE_NOTARIZE=auto|required|skip`; wire the `package-npm` release job to pass notary credentials; translate `docs/releases/RELEASE_GUIDE.md` to English and document notarization.

### Changes Overview
**Scope:** macOS app bundle build script, release CI workflow, release documentation.

**Key Actions:**
- **Notarization step**: Added `notarize_app_bundle()` to `scripts/build-open-computer-use-app.sh`, run once against the final `${app_root}` bundle after `codesign_app_bundle` (covers `--arch universal` automatically, since arch selection only changes which architectures get `lipo`'d into that one bundle before signing). Only proceeds when the resolved signing identity starts with `Developer ID Application:`; otherwise prints a skip notice in `auto` or exits non-zero in `required`.
- **Credential resolution**: `resolve_notary_auth()` tries, in order, `OPEN_COMPUTER_USE_NOTARY_PROFILE`, then an API key (`APPLE_NOTARY_KEY_PATH` or a base64 `APPLE_NOTARY_API_KEY_P8_BASE64` decoded to a `chmod 600` mktemp file cleaned up by the existing `trap cleanup EXIT`), then, `auto`-only, the keychain profile `open-computer-use-notary` if `xcrun notarytool history --keychain-profile ... ` succeeds locally.
- **mktemp portability fix**: caught during local verification of the API-key path — BSD `mktemp` (macOS `/usr/bin/mktemp`) leaves a literal suffix after `XXXXXX` (e.g. `template.XXXXXX.p8`) unsubstituted, unlike GNU `mktemp --suffix`; the key temp file template dropped the `.p8` suffix (notarytool does not require one) to stay portable.
- **Secure timestamp**: `codesign_app_bundle()` now adds `--timestamp` when signing with a "Developer ID Application" identity, since notarization requires a hardened runtime and a secure timestamp on the signature. Other identities (such as Apple Development) are not timestamped, so offline local signing keeps working.
- **Submission and evidence**: `ditto -c -k --keepParent` to zip, `xcrun notarytool submit --wait --output-format json`, fetching and printing `notarytool log` for the submission id on failure, then `stapler staple`, `stapler validate` (fatal via `set -e`), and `spctl -a -vvv -t exec` (informational only).
- **CI wiring**: `.github/workflows/release.yml`'s `package-npm` job gained a "Prepare Open Computer Use notarization config" step that decodes `APPLE_NOTARY_API_KEY_P8_BASE64` into a `0600` file under `RUNNER_TEMP` (mirroring the existing Cursor Motion DMG notarization step) and exports `APPLE_NOTARY_KEY_PATH` / `APPLE_NOTARY_KEY_ID` / `APPLE_NOTARY_ISSUER_ID` / `APPLE_DEVELOPER_TEAM_ID` plus `OPEN_COMPUTER_USE_NOTARIZE=auto`; missing secrets fall back to the existing ad-hoc/skip behavior without blocking the release. `scripts/npm/build-packages.mjs` needed no change: its `run()` helper already inherits the parent process environment via `spawnSync`'s default `env`.
- **Docs**: Translated `docs/releases/RELEASE_GUIDE.md` from Chinese to English in full, and added a "Notarization" section covering the one-time `notarytool store-credentials` setup, the env var resolution order, the CI secrets, and `stapler validate` / `spctl` verification.

### Design Intent (Why)
The app bundle previously shipped Developer ID-signed but never notarized, so a fresh download would still trip Gatekeeper on other machines. Reusing the existing Cursor Motion DMG notarization pattern (API key or keychain profile, decode-to-RUNNER_TEMP, `notarytool submit --wait`) keeps the two notarization paths consistent instead of inventing a second convention, while keeping `auto` mode's no-credentials behavior byte-for-byte identical to today (just one added skip line) so unrelated local/dev builds are unaffected.

### Files Modified
- `scripts/build-open-computer-use-app.sh`
- `.github/workflows/release.yml`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/histories/2026-09/20260923-1025-notarize-open-computer-use-app.md`
