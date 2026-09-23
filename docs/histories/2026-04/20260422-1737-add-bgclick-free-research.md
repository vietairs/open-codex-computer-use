# document-bgclick-free-research-workflow

## User Request

Replace IDA Pro with free tools like Ghidra to do decompilation research into the background-click direction of the bundled computer-use app; the research directory is too large to commit, so only settle a reproducible methodology for future agents into the docs, and don't commit `research/`.

## Changes This Round

- Added `research/` to the repository-level `.gitignore`, avoiding committing one-off Ghidra projects, large disassembly files, and temporary Swift build artifacts.
- Added a new methodology document for the background-click free-tooling research, recording the reproduction steps for Ghidra/radare2/Apple CLI/Swift prototypes.
- Updated the reverse-engineering docs entry point, noting that large analysis artifacts should be regenerated locally under `research/`.
- Preserved the key conclusions already verified this round: `NSEvent -> CGEvent`, window id fields, and the private `CGEventSetWindowLocation` and `postToPid` are the core path for reproducing background clicks.

## Design Motivation

The official binary is a stripped Swift/ObjC Mach-O, so the original source can't be recovered directly; one-off decompilation artifacts are too large and have less long-term value than a reproducible methodology. Writing the methods, the shape of the key evidence, and the verification matrix into the docs lets future developers have an AI regenerate the local research directory on demand, while keeping the repository lightweight.

## Files Affected

- `.gitignore`
- `docs/references/README.md`
- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/references/codex-computer-use-reverse-engineering/background-click-free-tooling.md`
