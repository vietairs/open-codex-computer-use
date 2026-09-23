# Open Source Computer Use Reverse Engineering

## Goal

Build a traceable set of reverse-engineering material for `open-codex-computer-use`, first clearly analyzing `SkyComputerUseClient`, `Codex Computer Use.app`, and the host dependency and runtime boundaries between the two, then use that to design an open-source implementation.

## Scope

- In scope:
  - Analyzing the closed-source `Codex Computer Use.app` bundle structure, identity, permissions, and runtime behavior.
  - Analyzing `SkyComputerUseClient`'s entry point, MCP exposure method, host dependencies, and failure modes.
  - Continuously recording findings in a dedicated directory under the repo's `docs/`.
- Out of scope:
  - Not starting implementation of the open-source version's code at this stage.
  - Not committing to fully replicating the official private protocol or UI at this stage.

## Background

- Related docs:
  - `docs/references/codex-computer-use-reverse-engineering/README.md`
  - `docs/references/codex-computer-use-reverse-engineering/baseline-architecture.md`
  - `docs/references/codex-computer-use-reverse-engineering/runtime-and-host-dependencies.md`
  - `docs/references/codex-computer-use-reverse-engineering/packaging-and-lifecycle-integration.md`
- Related code paths:
  - `~/.codex/plugins/cache/openai-bundled/computer-use/1.0.750/`
  - `~/.codex/config.toml`
- Known constraints:
  - The official bundle is closed-source binary, so it can only be reverse-engineered via bundle structure, symbols, strings, configuration, and local runtime traces.
  - The current `SkyComputerUseClient mcp` cannot be stably connected to directly by an arbitrary external MCP client.

## Risks

- Risk: mistaking capabilities found in strings/symbols for functionality that is actually currently enabled.
- Mitigation: all docs distinguish between "observed fact" and "inference", and attach the local evidence source wherever possible.

- Risk: attributing Inspector connection failures to a single simple cause.
- Mitigation: record all four types of evidence — direct launch, Inspector, analytics, and crash reports — simultaneously, to avoid overreaching conclusions.

- Risk: locking subsequent implementation prematurely onto the official private architecture.
- Mitigation: continuously separate "official implementation details" from "the capability boundary the open-source version actually needs".

## Milestones

1. Research and converge on an approach.
2. Reverse-engineer the client / service / IPC / permission model.
3. Converge on the open-source architecture and implementation scope based on the analysis results.

## Verification

- Commands:
  - `plutil -p .../Info.plist`
  - `otool -L ...`
  - `strings ... | rg ...`
  - `sqlite3 ~/Library/Group\ Containers/.../Analytics.db ...`
  - `codesign -dvv ...`
- Manual checks:
  - Compare Inspector connection behavior against local crash reports.
  - Compare `~/.codex/config.toml` against `.mcp.json` transport configuration.
- Observational checks:
  - Watch for service/client launch events in `Analytics.db`.
  - Watch for crash records in `~/Library/Logs/DiagnosticReports/`.

## Progress Log

- [x] Milestone 1
- [x] Milestone 2
- [x] Milestone 3

## Decision Log

- 2026-04-17: Record long-term reverse-engineering results in `docs/references/codex-computer-use-reverse-engineering/` first, rather than scattering them across chat context. This lets the open-source implementation reference the repo's own docs directly later.
- 2026-04-17: Do not implement code yet; first clearly analyze the boundaries of client / service / host dependencies, to avoid implementing on wrong assumptions from the start.
- 2026-04-17: Temporarily initialized `uv` and the Python `mcp` dependency in the repo to reproduce experiments with a minimal Python SDK and verify `stdio` connection behavior, instead of continuing to rely on the Inspector.
- 2026-04-17: After the above Python / `uv` reproduction experiments were complete, the one-off probe and its runtime chain were not kept in the repo; what is kept long-term is the evidence and conclusions in the docs.
- 2026-04-17: Split the plugin packaging structure, the `turn-ended` notify lifecycle, and the main app's distribution form into a separate document, instead of mixing them with the runtime host dependencies, to make it easier to map them directly to the open-source version's interface boundary later.
- 2026-04-17: The reverse-engineering phase has converged within the repo; subsequent implementation moves to the Swift open-source implementation plan at `docs/exec-plans/completed/20260417-open-source-swift-computer-use.md`.
