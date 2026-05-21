# Stage Manager Background Control

Research and gap analysis for controlling macOS apps in the Stage Manager background without stealing focus from the user's foreground.

## Context

When using Stage Manager, a user may want the MCP to operate a background app (e.g., automate a terminal, editor, or data entry app) while they keep working in their own foreground app. The challenge: most macOS input APIs either require the target window to be onscreen or inadvertently call `activate()` which steals focus.

## Documents

| File | Purpose |
|---|---|
| `01-macos-stage-manager-background-app-control.md` | How Stage Manager works internally, what APIs exist, API coverage matrix, recommended architecture options |
| `02-codebase-gap-analysis.md` | Exact file/line gaps in this repo's Swift code, proposed fixes with code snippets, implementation priority order |

## TL;DR

**The technique exists and is proven** — see `docs/references/codex-computer-use-reverse-engineering/background-click-free-tooling.md` for the reverse-engineering that identified it. It is **not yet wired into the production Swift code**.

Reviewed against **v0.1.51** (2026-05-20). `dragTargeted` already exists and is background-safe — original Gap 4 was incorrect. **4 gaps remain:**

1. `AccessibilitySnapshot.swift:359` — drop `optionOnScreenOnly`, skip `activate()` at line 192 for off-screen windows
2. `InputSimulation.swift` — add `clickBackgrounded` using `CGEventSetWindowLocation` + CGEvent fields 91/92
3. `ComputerUseService.swift:1668` — wire `clickBackgrounded` when `targetWindowID` is available
4. `AccessibilitySnapshot.swift:396` — return AX-tree-only result with note when window off-screen (ScreenCaptureKit also cannot capture Stage Manager background windows)
5. `ComputerUseService.swift:572` — add activate-temporarily fallback for `type_text` (guard at `canTypeTextUsingKeyboardFallback` line 1235 blocks background apps)

## Key private API

`CGEventSetWindowLocation` — resolved via `dlsym(RTLD_DEFAULT, "CGEventSetWindowLocation")` at runtime. Graceful fallback to `clickTargeted` if symbol unavailable.
