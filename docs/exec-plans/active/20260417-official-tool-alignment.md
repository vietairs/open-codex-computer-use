# Official Tool Alignment

## Goal

Bring the 9 tools that this repo's `open-computer-use` exposes to the MCP host into closer alignment, in one pass, with what the real official `computer-use`'s `tools/list` and `tools/call` currently return: description, schema, annotations, error semantics, the shape of the `list_apps` list, and the text-output style of `get_app_state` / action tools, as far as practical.

## Scope

- In scope:
  - Empirically test the official `tools/list` and representative `tools/call` responses using `scripts/computer-use-cli`.
  - Converge the description, input schema, and annotations of the 9 tools.
  - Make `list_apps` output closer to the official "running + used in the last 14 days" app view.
  - Adjust the text rendering of `get_app_state` / action tools to reduce internal implementation detail and move closer to the official tree-shaped output.
  - Sync the architecture docs, history, and necessary tests.
- Out of scope:
  - At this stage, no commitment to 100% replicate the official closed-source security policy, session approval, overlay UI, or private host integrations.
  - At this stage, do not turn a one-off local sample into a full automated diff platform.

## Background

- Related docs:
  - `docs/ARCHITECTURE.md`
  - `docs/references/codex-computer-use-cli.md`
  - `docs/references/codex-local-runtime-logs.md`
  - `docs/references/codex-computer-use-reverse-engineering/tool-call-samples-2026-04-17.md`
- Related code paths:
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ToolDefinitions.swift`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppDiscovery.swift`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
  - `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/MCPServer.swift`
- Known constraints:
  - The official `computer-use` can only be reliably invoked indirectly through `codex app-server`; a plain stdio client should not be assumed to connect directly.
  - The final source of the `uses` figure in the official `list_apps` was confirmed to be system Spotlight metadata (`kMDItemUseCount` / `kMDItemLastUsedDate_Ranking`), not the previously guessed `Knowledge/knowledgeC.db`.
  - The Accessibility tree and index assignment depend heavily on the host app's own AX layer structure; achieving a fully identical result requires trimming and abstraction rather than exposing the local AX detail as-is.

## Risks

- Risk: aligning only the schema and not the result text still leaves the host seeing a noticeably different tree structure and error semantics.
  - Mitigation: adjust `list_apps`, `get_app_state`, and tool error payloads together in the same pass.
- Risk: over-trimming the AX tree degrades the existing smoke path or action tool hit rate.
  - Mitigation: keep the underlying element map intact and only tighten the user-visible text; behavior matching continues to rely on the full internal snapshot.
- Risk: after `list_apps` introduces a new system data source, usage data may be unavailable on some machines.
  - Mitigation: make it a read-only, fail-safe fallback; still return running apps when usage data cannot be found.

## Milestones

1. Empirically confirm the official surface and the differences.
2. Converge schema, error semantics, `list_apps`, and state rendering.
3. Re-test both paths, sync docs, and archive.

## Verification

- Commands:
  - `swift test`
  - `go run . list-tools --transport app-server`
  - `go run . list-tools --transport direct --server-bin ../../.build/debug/OpenComputerUse`
  - `go run . call list_apps --transport direct --server-bin ../../.build/debug/OpenComputerUse`
- Manual checks:
  - The 9 tool surfaces in the official and open-source `tools/list` can be visually aligned at a glance.
  - The official bundled `computer-use`'s raw app-server helper is currently only used to probe `tools/list`; real tool calls go through the normal Codex agent/tool call chain or this repo's direct server.
  - `get_app_state` text no longer exposes `_NS:` internal identifiers, frame noise, or excessive cell recursion.
  - Error shapes such as `appNotFound` and safety denials return to `content` + `isError: true` consistently with the official behavior.
- Observational checks:
  - `list_apps` output includes `running`, `last-used`, `uses`, in an order close to the official one.
  - Representative action tool responses continue to include status text and a screenshot.

## Progress Log

- [x] Milestone 1
- [x] Milestone 2
- [x] Milestone 3

## Decision Log

- 2026-04-17: this round of alignment is based on empirically testing the official return via `computer-use-cli`, rather than continuing to maintain "approximate copy" based on earlier guesses.
- 2026-04-17: `list_apps` now prefers the Spotlight metadata query, sorting and filtering apps by the same-source `kMDItemUseCount` / `kMDItemLastUsedDate_Ranking` as the official implementation; running apps continue to be merged in and backfilled via `NSWorkspace`.
- 2026-04-17: added an official-style safety denial for high-risk apps passed directly by bundle id, and made the name-matching path not resolve to these apps by default, replicating the official `appNotFound("iTerm2")` / `not allowed to use the app 'com.googlecode.iterm2'` boundary behavior.
- 2026-04-17: the current official baseline for the direct MCP tool's `content[0].text` should start from `App=<bundle-id> (pid ...)`, no longer treating the old `Computer Use state (CUA App Version: 750)` / `<app_state>` wrapper as part of the response text.
- 2026-05-07: Issue #12 exposed a problem where Chrome was blocked by the built-in denylist. After revisiting this plan and the reverse-engineering samples, only the official safety denial for iTerm2 could be confirmed; Chrome only appeared in `list_apps` samples, with no empirical evidence of it being denied. Following that, per product judgment the built-in denylist was narrowed to password managers — terminals, Chrome / Atlas, and system components are no longer built-in blocked targets, and subsequent sensitive-app policy is deferred to session approval / policy design.
