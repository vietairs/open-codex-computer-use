# Record official state renderer reverse-engineering clues

## User Request

Continue optimizing `open-computer-use` in light of reverse-engineering results, so that tool returns for Lark / Electron apps progressively converge toward the official `computer-use`.

## Main Changes

- Added `docs/references/codex-computer-use-reverse-engineering/state-rendering-1.0.770.md`.
- Recorded strings, AX fields, tree transforms, window errors, and action clues related to state rendering found in the official `computer-use` 1.0.770 client/service binary.
- Updated the reverse-engineering README to include the new document in the navigation.

## Design Motivation

Future renderer alignment should not rely solely on a one-off visual comparison of tool output. Preserving the stable, observable fields and transform names from the official binary in the repository can help future agents choose an iteration direction backed by more evidence.

## Affected Files

- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/references/codex-computer-use-reverse-engineering/state-rendering-1.0.770.md`
