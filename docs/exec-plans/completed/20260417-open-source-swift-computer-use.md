# Open Source Swift Computer Use

## Goal

Land a locally runnable, testable, continuously evolvable Swift open-source implementation in the current repo: expose the 9 `computer-use` tools via stdio MCP, deliver minimally viable capability built on macOS Accessibility / screenshots / input events, along with a repeatable end-to-end verification path.

## Scope

- Included:
  - Set up a repo-level buildable project using Swift Package Manager.
  - Implement the 9 tools: `list_apps`, `get_app_state`, `click`, `perform_secondary_action`, `scroll`, `drag`, `type_text`, `press_key`, `set_value`.
  - Provide a locally launchable fixture app, serving as a safe, stable, regression-friendly UI test target.
  - Add MCP smoke / integration tests, covering real calls to the 9 tools.
  - Update repo docs such as architecture, quality, README, and history.
- Not included:
  - This phase does not replicate the official closed-source app's signing boundary, private IPC, overlay UI, or plugin self-install logic.
  - This phase makes no commitment to character-for-character compatibility with the official output text.
  - This phase does not do release-channel-facing `.app` packaging or notarization.

## Background

- Related docs:
  - `docs/references/codex-computer-use-reverse-engineering/README.md`
  - `docs/references/codex-computer-use-reverse-engineering/baseline-architecture.md`
  - `docs/references/codex-computer-use-reverse-engineering/internal-ipc-surface.md`
  - `docs/references/codex-computer-use-reverse-engineering/tool-call-samples-2026-04-17.md`
- Related code paths:
  - `apps/`
  - `packages/`
  - `scripts/`
- Known constraints:
  - macOS Accessibility and Screen Recording permissions directly affect real behavior.
  - This implementation runs under the premise of being open source with no official signed host, and cannot rely on the official private caller constraint.
  - Tool verification must choose safe actions, avoiding accidentally triggering sensitive system switches.

## Risks

- Risk: the AX tree and window screenshots vary widely across different apps, making tests brittle.
  - Mitigation: add a dedicated fixture app, pinning the regression path for the 9 tools to a controlled UI.
- Risk: input events, screen coordinates, and multi-monitor coordinate systems are prone to offset issues.
  - Mitigation: uniformly model element frame, window frame, and screenshot coordinates within a session, and use a fixed window size in tests.
- Risk: unclear tool behavior when permissions are missing.
  - Mitigation: implement explicit permission checks / error messages, and document diagnostic commands in the README and plan.

## Milestones

1. Converge on the design and scaffolding.
2. Land the Swift MCP server + macOS automation capabilities.
3. Verify the 9 tools, sync docs, and close out delivery.

## TODO

- [x] Set up the Swift package structure and build entry point.
- [x] Implement the MCP stdio transport, tool registry, and JSON-RPC request handling.
- [x] Implement app discovery, session, AX tree, screenshot, and element indexing.
- [x] Implement input handling and AX action execution for the 7 action-type tools.
- [x] Build a local fixture app providing a stable, clickable, typeable, scrollable, draggable interface.
- [x] Write and pass end-to-end tests for the 9 tools.
- [x] Update `docs/ARCHITECTURE.md`, `README.md`, `docs/QUALITY_SCORE.md`, and history.

## Verification

- Commands:
  - `swift build`
  - `swift test`
  - `swift run OpenCodexComputerUseFixture`
  - `swift run OpenCodexComputerUse mcp`
  - `scripts/run-tool-smoke-tests.sh`
- Manual checks:
  - Confirm the fixture app can launch, gain focus, and show a stable visible window.
  - Confirm `get_app_state` returns the screenshot path, window info, and AX tree.
  - Confirm all 9 tools produce an observable state change on the fixture app.
- Observation checks:
  - Record smoke test output and failure context.
  - Record the explicit diagnostic message shown when permissions are missing.

## Progress Log

- [x] Milestone 1
- [x] Milestone 2
- [x] Milestone 3

## Decision Log

- 2026-04-17: Chose to first build a combination of "an open-source runnable implementation + a dedicated fixture app," rather than directly trying to replicate the official closed-source service/client/IPC layering. This makes it possible to get real capability and a testing closed-loop running first, without an official signing boundary.
- 2026-04-17: Prioritize the Swift standard library and system frameworks, avoiding third-party dependencies as much as possible, reducing the supply-chain surface and build uncertainty.
- 2026-04-17: For ordinary apps, still keep the real AX / screenshot / CGEvent path; for the in-repo fixture app, add synthesized state and a command bridge, used to guarantee the 9 tools have a stable, low-risk, regression-friendly smoke path.
