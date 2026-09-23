# Permission Onboarding App

## Goal

Add a genuinely usable macOS permission onboarding experience for `OpenComputerUse`: expand the current pure-CLI entry point into a runnable app mode, providing a permission status window, System Settings deep links, and a draggable app proxy view, so users can more easily add `OpenComputerUse` to `Accessibility` and `Screen & System Audio Recording`.

## Scope

- In scope:
  - Add an app-mode entry point for `OpenComputerUse`.
  - Implement the permission status window, polling updates, and button state.
  - Implement System Settings deep links for `Accessibility` and `Screen & System Audio Recording`.
  - Implement the draggable app bundle accessory panel / draggable app tile.
  - Add a `.app` packaging script and a local verification path.
  - Sync architecture, README, quality scoring, and history.
- Out of scope:
  - This phase does not replicate all of the official transition animations, blur overlays, or multi-window choreography.
  - This phase does not wire up notarization, code signing, or release-channel distribution.

## Background

- Related docs:
  - `docs/references/codex-computer-use-reverse-engineering/permission-onboarding.md`
  - `docs/ARCHITECTURE.md`
  - `docs/SECURITY.md`
- Related code paths:
  - `apps/OpenComputerUse/`
  - `packages/OpenComputerUseKit/Permissions.swift`
  - `scripts/`
- Known constraints:
  - Only a genuine `.app` bundle lets the user grant permission by "dragging it into the list."
  - This round still keeps the CLI / MCP mode; the existing `mcp` entry point must not be broken.
  - In some scenarios, `Screen Recording` authorization state only stabilizes after the app is relaunched.

## Risks

- Risk: building only the window UI without `.app` packaging, so it can't actually be dragged into the system settings list.
  - Mitigation: fill in a minimal `.app` packaging script in the same round and verify in bundle mode.
- Risk: an incorrect System Settings URL or OS version differences send users to the wrong page.
  - Mitigation: verify locally that it deep-links to the `Accessibility` and `Screen & System Audio Recording` pages.
- Risk: incorrect drag pasteboard contents mean the user can see the tile but can't actually drag it in.
  - Mitigation: have the drag source use the app bundle's `fileURL` directly, rather than just a visual copy.

## Milestones

1. Converge on the entry point and packaging approach.
2. Implement the permission window and the drag accessory panel.
3. `.app` packaging, local verification, docs sync.

## Verification

- Commands:
  - `swift build`
  - `swift test`
  - `scripts/build-open-computer-use-app.sh debug`
  - `open dist/OpenComputerUse.app`
- Manual checks:
  - App mode displays the permission window correctly.
  - The `Allow` button jumps to `Accessibility` and `Screen & System Audio Recording` respectively.
  - The accessory panel can be shown and dragging the app tile can be started.
  - The main window converges to `Done` once permissions are granted.
- Observational checks:
  - The `doctor` permission status matches the app window's.
  - After authorization, the window state automatically converges to `Done` or clearly prompts for a relaunch.

## Progress Log

- [x] Milestone 1
- [x] Milestone 2
- [x] Milestone 3

## Decision Log

- 2026-04-17: Build permission onboarding directly into the `OpenComputerUse` main target rather than starting a fully separate helper app. This lets the `mcp` CLI and the app bundle share the same executable and bundle identity.
- 2026-04-17: Add reading of the TCC persistent authorization record to the permission-state determination, to avoid the CLI subprocess and the GUI app seeing inconsistent results for the same bundle's permission state in dev environments.
- 2026-04-17: The drag panel is still only shown while `System Settings` is in the foreground; its horizontal position stays centered on the window's right-side content area, and its vertical position preferentially follows the current permission page's `+ / -` control row, falling back to the window's bottom edge only when that control's geometry can't be obtained — avoiding it getting stuck at the very bottom of the screen on long pages like `Screen & System Audio Recording`.
- 2026-04-17: App mode switched to running `LSUIElement` + `.accessory` agent-style, keeping the permission window visible while no longer exposing an extra foreground app icon in the Dock during execution.
- 2026-04-19: The accessory panel's first appearance now flies in from the main window's `Allow` button source frame to the bottom edge of the `System Settings` content area, using a spring + curved-frame transition; an explicit back button was also added inside the panel, so the action of interrupting guidance is handled within the app itself.

## Current Conclusion

- App mode, System Settings deep links, the drag tile, `.app` packaging, and the main window's `Done` state are all working.
- The accessory panel now has a one-shot source-to-target entrance animation and an explicit back button, so permission switching no longer relies solely on a hard cut and manually switching back to the main window.
- `swift test`, `./scripts/run-tool-smoke-tests.sh`, `doctor`, and a real `System Settings` snapshot have all passed.
- The official "accessory UI that looks embedded inside `System Settings`" experience remains a follow-up UI polish item and does not block this round's functional verification.
