# Local validation takes priority over public releases

## User Request

The user pointed out that we shouldn't keep publishing public releases after every build, and suggested pointing at a local `open-computer-use` via the Codex TOML config for validation instead, to avoid exposing external users to too many patch releases.

## Main Changes

- Updated `docs/releases/RELEASE_GUIDE.md` to make clear that day-to-day alignment validation defaults to a local build and local MCP config.
- Added the trigger conditions for a public release: only enter the release checklist when the user explicitly asks for a release, or a fix has stabilized enough to need external delivery.

## Design Motivation

A public release should represent a stable delivery consumable by the outside world, not a byproduct of every local validation. Going forward, agents should first use a local build to verify the behavioral difference between `open-computer-use` and the official `computer-use`, reducing meaningless version noise.

## Files Affected

- `docs/releases/RELEASE_GUIDE.md`
