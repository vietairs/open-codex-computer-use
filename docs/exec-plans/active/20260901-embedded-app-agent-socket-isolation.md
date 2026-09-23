# Isolate the macOS App Agent socket for embedded hosts

## Goal

Add an optional, deterministic socket namespace to Open Computer Use's macOS App Agent. All existing callers that do not configure a namespace keep using the legacy socket path; embedded hosts that configure a namespace get a private socket, preventing different OCU bundles from terminating each other's App Agent.

## Scope

- In scope: socket filename resolution, default compatibility behavior, unit tests, pre-release build verification, and history records.
- Out of scope: modifying or stopping the user's global/NVM OCU, changing the App Agent permission model, retrying non-idempotent page actions.

## Background

- Related docs: `docs/ARCHITECTURE.md`, `docs/REPO_COLLAB_GUIDE.md`, `docs/HISTORY_GUIDE.md`.
- Related code paths: `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`, `packages/OpenComputerUseKit`.
- Known constraints: legacy versions hard-code `open-computer-use-agent.sock`; when two different bundles use that socket, whichever starts later terminates the earlier Agent. Boss resume screening must use the embedded OCU and must not depend on or interfere with the global OCU.

## Risks

- Risk: changing the default path breaks existing CLI/MCP callers.
- Mitigation: strictly return the legacy filename when the namespace is unset or empty; use the new short-hash filename only for an explicit namespace.
- Risk: the socket path becomes too long or leaks the host's data directory.
- Mitigation: use only the first 16 hex characters of the SHA-256 digest, and never write the raw namespace into the filename or diagnostics.

## Milestones

1. Confirm the socket-conflict path and the backward-compatibility boundary.
2. Implement the optional namespace and cover default, determinism, and isolation behavior with tests.
3. Build, record history, and wait for approval to release a new runtime version before embedded hosts can upgrade.

## Verification

- Command: `swift test --filter OpenComputerUseKitTests/testAppAgentSocketFileName`.
- Command: `swift build --product OpenComputerUse`.
- Manual check: the filename remains `open-computer-use-agent.sock` when the environment variable is unset.
- Observation check: two different namespaces map to different socket filenames; no terminate/unlink is performed against the legacy socket.

## Progress log

- [x] Confirmed the fixed global socket is the root cause of cross-bundle Agent termination.
- [x] Completed namespace resolution and unit tests.
- [x] Completed build verification and history record; committed locally and waiting for approval to release a new runtime before embedded hosts can upgrade.

## Decision log

- 2026-09-01: Adopted an opt-in namespace rather than changing the global default path or disabling the App Agent proxy, to preserve compatibility for legacy callers while isolating embedded hosts.
