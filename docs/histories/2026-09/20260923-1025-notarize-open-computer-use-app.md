## [2026-09-23 10:25] | Task: Notarize the Open Computer Use.app bundle

### Execution Context
* **Agent ID**: `fullstack-developer`
* **Base Model**: `claude-sonnet-5`
* **Runtime**: `Claude Code, macOS arm64, git worktree`

### User Query
> Add notarization for `Open Computer Use.app`: extend `scripts/build-open-computer-use-app.sh` to notarize the final signed bundle with `xcrun notarytool` and staple the ticket, controlled by `OPEN_COMPUTER_USE_NOTARIZE=auto|required|skip`; wire the `package-npm` release job to pass notary credentials; translate `docs/releases/RELEASE_GUIDE.md` to English and document notarization.

A second review round then tightened when notarization runs, how the result is judged, and how CI hands over the credentials.

### Changes Overview
**Scope:** macOS app bundle build script, release CI workflow, release documentation.

**Key Actions:**
- **One decision, made before signing**: `decide_notarization()` runs before the Swift build and sets `will_notarize`. It is `1` only when the mode is not `skip`, the configuration is `release` (or the mode is `required`, which applies to any configuration), the signing identity is "Developer ID Application", and credentials resolve. `auto` therefore notarizes release builds only. `required` fails fast, before anything is compiled, when the identity or credentials are missing.
- **Timestamp tied to that decision**: `codesign_app_bundle()` passes `--timestamp` only when `will_notarize=1`, and `--timestamp=none` for every other non-ad-hoc signature. codesign requests a secure timestamp by default for Developer ID signatures, so the explicit `none` is what keeps debug builds, `skip`, and credential-less `auto` builds from contacting Apple.
- **Developer ID detection**: a 40-hex SHA-1 in `OPEN_COMPUTER_USE_CODESIGN_IDENTITY` is mapped to its certificate name via `security find-identity -v -p codesigning` (against `OPEN_COMPUTER_USE_CODESIGN_KEYCHAIN` when set). After signing, `notarize_app_bundle()` also requires `Authority=Developer ID Application:` in `codesign -dvv` before submitting; in `required` mode a mismatch is fatal.
- **Credential resolution**: `resolve_notary_auth()` tries `OPEN_COMPUTER_USE_NOTARY_PROFILE`, then an API key (`APPLE_NOTARY_KEY_PATH`, which must be a readable file, or `APPLE_NOTARY_API_KEY_P8_BASE64`), then, in `auto` only, the keychain profile `open-computer-use-notary`. That `notarytool history` probe only happens for an `auto` release build signed with Developer ID. Because the function runs inside an `if` condition (errexit is off), each step is checked explicitly: `mktemp`/`chmod` failures exit, the base64 key is decoded with `validate=True` after stripping whitespace (invalid input fails with "APPLE_NOTARY_API_KEY_P8_BASE64 is not valid base64"), and an empty decoded file fails. The `EXIT` trap is now installed before this runs, so the decoded key file is always removed. The key is never echoed.
- **mktemp portability**: BSD `mktemp` (macOS `/usr/bin/mktemp`) leaves a literal suffix after `XXXXXX` unsubstituted, so the key template has no `.p8` suffix (notarytool does not need one).
- **Submission result**: `notarytool submit --wait --output-format json` writes stdout and stderr to separate files. The script parses `id` and `status` from the JSON and treats anything other than `status == "Accepted"` (or a non-zero exit) as a failure: it prints the id and status, fetches `xcrun notarytool log <id>` with the same credentials, and exits 1.
- **Stapling**: `stapler staple` is retried up to 3 attempts, sleeping 10s and then 20s, to allow for ticket propagation. `stapler validate` stays fatal; `spctl -a -vvv -t exec` is informational.
- **CI wiring**: the "Prepare Open Computer Use notarization config" step in `.github/workflows/release.yml` now only chooses the mode. It sets `OPEN_COMPUTER_USE_NOTARIZE=required` when `APPLE_NOTARY_API_KEY_P8_BASE64`, `APPLE_NOTARY_KEY_ID` and `APPLE_NOTARY_ISSUER_ID` are all set, `auto` with a `::notice::` when none is set, and fails with an `::error::` naming the missing secrets when only some are set. It no longer decodes the key into `RUNNER_TEMP` or writes any secret value to `GITHUB_ENV`. The secrets (plus the optional `APPLE_DEVELOPER_TEAM_ID`) are passed as `env:` only on the "Build npm release artifacts" step, and the build script decodes the key itself. `scripts/npm/build-packages.mjs` needed no change because its `run()` helper inherits the parent environment.
- **Docs**: translated `docs/releases/RELEASE_GUIDE.md` from Chinese to English, and rewrote its "Notarization" section to describe the behaviour above, including the need to set `OPEN_COMPUTER_USE_NOTARY_PROFILE=open-computer-use-notary` explicitly in `required` mode.

### Design Intent (Why)
The app bundle shipped Developer ID-signed but never notarized, so a fresh download still tripped Gatekeeper on other machines. Tying the timestamp to a single up-front notarization decision keeps every build that is not going to be notarized fully offline, rather than inferring intent from the identity name alone. Treating the JSON status as authoritative avoids shipping a rejected submission just because `notarytool` exited 0. In CI, configured credentials switch the build to `required`, so a release cannot silently ship unnotarized once the secrets exist. Keeping secret values out of `GITHUB_ENV` limits their exposure to the one step that needs them.

### Files Modified
- `scripts/build-open-computer-use-app.sh`
- `.github/workflows/release.yml`
- `docs/releases/RELEASE_GUIDE.md`
- `docs/histories/2026-09/20260923-1025-notarize-open-computer-use-app.md`
