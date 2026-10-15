# Persistent screenshot configuration

Port of the persistent screenshot settings and output formats from the upstream project (iFurySt/open-codex-computer-use),
adapted to the fork's current code.

## Changes

- New `ImageCaptureConfig` (macOS) resolves screenshot settings per capture with environment > file > defaults: format
  (`png` default, `jpg`), JPEG quality, maximum long edge, over-limit policy, minimum total pixel count, ScreenCaptureKit
  timeout (capped at 30 seconds). Every value is range-checked; an invalid file or environment value is ignored with a
  stderr warning. A config path that is not a regular file, a file over 64 KiB, malformed JSON and relative paths all
  fall back to the defaults. The file is opened once without blocking and checked on the descriptor, so a swapped or
  growing file cannot block the reader or exceed the limit. The key set carries no permission, lock-screen or safety
  setting. The file is read only when a screenshot is taken, so the snapshot behind `decide_next_action` reads nothing.
- Screenshot encoding moved to `ScreenshotEncoding.swift`. The long-edge cap now applies even when it is far below the
  byte-cap floor (previously a cap that needed a scale under 0.25 skipped resizing). The fork's 900 KB result byte cap
  is kept for both formats. A screenshot omitted by the settings sets `AppSnapshot.screenshotNote`; `get_app_state`
  adds the reason as text and coordinate `click` / `drag` are refused until one is delivered.
- `AppSnapshot.screenshotPNGData` became `screenshotData` (PNG or JPEG); a deprecated PNG-only accessor remains. Image
  content items choose the MIME type from the bytes.
- App agent: the proxy, in the calling host's process, reads and validates the config and forwards only the validated
  `OPEN_COMPUTER_USE_IMAGE_*` values, and only with calls that can take a screenshot. The agent never opens a path a
  caller names (`OPEN_COMPUTER_USE_CONFIG_FILE` is dropped by `sanitizePeerEnvironment`), applies the values to the one
  call through `ComputerUseService.withForwardedImageSettings`, ignores its own launch environment for them, and does
  not write them to its process environment. A call whose only per-call values are screenshot settings therefore takes
  no process-wide lock, as before the feature. The lock-screen and scripting opt-ins are untouched; `docs/SECURITY.md`
  records the new per-call keys.
- `ocu config` (list, get, set, reset, path, `--json`) lives in `scripts/ocu-config.mjs` and is dispatched from the npm
  launcher rendered by `scripts/npm/build-packages.mjs`; the module is staged into the package. It writes atomically with
  mode 0600, preserves unknown fields, writes through a symlinked config to its target, and reads through one bounded
  descriptor. `scripts/ci.sh` runs its tests.
- Docs: `docs/configuration.md`, README, architecture, security, the skill usage reference and the feature notes.

## Not ported

- WebP output and the libwebp Swift package (`Package.swift`, `Package.resolved`, `THIRD_PARTY_NOTICES.md`, app and npm
  notice copying, supply-chain note): it adds a third-party native dependency to the shared agent.
- Removal of the screenshot byte cap: the fork keeps it.
- Chinese docs, the completed upstream exec plan and live-test edits (not needed to compile).
- The upstream Node REPL launcher does not exist in the fork, so the config command is wired into the generated npm
  launcher instead.

## Verification

- `swift test`: 873 tests, 2 skipped, 0 failures (41 in `ImageCaptureConfigTests`).
- `node --test scripts/ocu-config.test.mjs`: 13 tests passed, including a staged launcher run that must not start the
  native runtime.
- Mutation checks: encoding JPG as PNG, dropping the over-limit omission and dropping the regular-file check each made
  tests fail. So did removing the service-level coordinate refusal, raising the result byte cap, passing the process
  environment or the config file path through the forwarded form, keeping the config file path in the peer
  environment, leaving raw settings in the relayed environment, and reading the configuration for a snapshot with no
  screenshot.
- Not verified: a real capture through ScreenCaptureKit with a JPG config, and the proxy and agent glue in
  `MacOSAppAgentProxy.swift` against a live signed agent. The pure parts it relies on (`relayedEnvironment`,
  `processOverrides`, `forwarded`) are covered in the Kit.
