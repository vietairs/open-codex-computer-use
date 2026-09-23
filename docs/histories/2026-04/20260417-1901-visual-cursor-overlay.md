# Visual Cursor Overlay

## User Request

The user wanted to improve the look and feel of `click`, aligning it with the official `computer-use` experience of "not hijacking the real cursor, but rendering its own cursor overlay for the user to see," and specifically noted:

- The cursor should sway slightly when idle;
- It should move along a curved arc with a bit of directional change;
- Clicking should not reactivate the target app or steal current focus because of this visualization layer.

The user also provided a local screen recording, `00:59 ~ 01:03`, as a reference sample, and asked this round to also analyze it together with the official `Codex Computer Use.app` and the existing reverse-engineering material already in the repo.

## What Changed This Round

- **[MCP runtime]**: Added a minimal AppKit runtime for `mcp` mode. When visual cursor is enabled, the main thread keeps an event loop alive to host the overlay UI, while the stdio server continues running on a background thread as before.
- **[Software cursor overlay]**: Added `SoftwareCursorOverlay`, which draws an independent software cursor using a transparent `NSPanel`, supporting curved-path movement, click pulse, idle sway after clicking, and can be explicitly disabled via `OPEN_COMPUTER_USE_VISUAL_CURSOR=0`.
- **[Click path wiring]**: `ComputerUseService.click` now moves the visual cursor before performing the real action, then proceeds with the original AX-first / HID-fallback strategy; pulse and settle happen after the action completes, without changing the underlying click decision just because visualization was added.
- **[Tests and scripts]**: Added environment variables and a few pure-logic unit tests for the visual cursor; the smoke script explicitly disables the overlay to keep the UI animation from affecting regression stability.
- **[Docs sync]**: Updated `README.md`, `docs/ARCHITECTURE.md`, and the execution plan to state clearly that the open-source version now has a click visual cursor layer, though it still doesn't replicate the official choreography in full.

## Design Rationale

The official bundle and existing reverse-engineering docs already make it clear enough that the pointer shown to the user is most likely an independent `Software Cursor` window, not the real system cursor. For the open-source version, the most sensible convergence isn't to keep stuffing everything into the HID event path, but to clearly separate "executing the real action" from "the visual layer shown to the user":

- Real actions still prefer AX, trying not to steal focus.
- The visual cursor is only responsible for conveying "where it's clicking now, what it's about to click."
- Even with an HID fallback still underneath, this visualization layer alone can already push the product's look-and-feel and observability a good step toward the official behavior.

## Key Files

- `apps/OpenComputerUse/Sources/OpenComputerUse/MCPAppRuntime.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `README.md`
- `docs/ARCHITECTURE.md`

## [2026-04-17 19:52] | Follow-up: Shrink the Cursor and Order It by Target Window

### Additional Changes

- **[Official asset fallback]**: Still uses the same `SoftwareCursorOverlay`, but the visual style now preferentially reads the `SoftwareCursor` asset at runtime from the local official `Codex Computer Use.app` bundle, then applies local processing before drawing it; this reuses the official asset without vendoring closed-source assets directly into the repo.
- **[Size and motion tuning]**: Noticeably reduced the cursor's default display size, and lengthened both the initial entry offset and the movement duration, to avoid the impression of "there's a cursor, but it barely seems to move."
- **[Ordering relative to the target window]**: Added a target `windowID` / `layer` to `AppSnapshot`; the overlay no longer stays fixed at `.floating` on top — it now tries to stay above the target window while remaining below any higher-layer foreground window, more closely matching the official behavior where "acting on A doesn't let the cursor bleed through in front of B."
- **[Auto-hide after action]**: The overlay no longer stays on screen indefinitely. After a click completes or settles abnormally, it holds briefly with a slight sway, then automatically fades out and calls `orderOut`, reappearing on the next action.

### Why

The user pointed out two very specific problems: the cursor was too big, and when the user was currently on app B, an action on app A shouldn't have its cursor cover B. The former showed that the first version of the overlay was still at the "prove the pipeline works" stage, with size and asset choices too rough; the latter showed that window ordering can't just consider "should it be visible" but also "which layer should it sit at." The focus of this follow-up is moving the visual cursor from "present" to "feeling right."
