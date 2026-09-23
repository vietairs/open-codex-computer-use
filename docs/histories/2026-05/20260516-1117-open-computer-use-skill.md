# Open Computer Use skill

## User Request

The user wants to confirm whether the repo currently has no skills, and, following the `skills/` structure of `open-codex-browser-use`, add an `open-computer-use` skill to this repo; `SKILL.md` serves as the table of contents, with installation, usage, troubleshooting, and other content split out into files loaded on demand; also add `npx skills` install and upgrade instructions to both the English and Chinese READMEs.

## Changes

- Add `skills/open-computer-use/SKILL.md` as the entry point and table of contents for the Open Computer Use agent skill.
- Add `skills/open-computer-use/references/installation.md`, `usage.md`, and `troubleshooting.md`, splitting out installation, MCP/CLI usage, and troubleshooting notes.
- Add `skills/open-computer-use/agents/openai.yaml`, providing agent display metadata and a default prompt.
- Add `scripts/package-skill.sh` and the `package:skill` npm script, for validating and packaging `.zip` / `.skill` artifacts.
- Update `README.md` and `README.zh-CN.md`, adding the `npx skills add` and `update` install/upgrade commands.
- Update `docs/ARCHITECTURE.md`, adding the `skills/` directory and the skill-packaging verification path.

## Design Intent

Follows the skill organization approach used by `open-codex-browser-use`, letting the agent read a lightweight entry point first, then open the installation, usage, or troubleshooting reference as the task needs, instead of cramming all the detail into a single `SKILL.md`. The packaging script is also kept, so future releases can ship a downloadable skill artifact.

## Files Affected

- `skills/open-computer-use/SKILL.md`
- `skills/open-computer-use/references/installation.md`
- `skills/open-computer-use/references/usage.md`
- `skills/open-computer-use/references/troubleshooting.md`
- `skills/open-computer-use/agents/openai.yaml`
- `scripts/package-skill.sh`
- `package.json`
- `README.md`
- `README.zh-CN.md`
- `docs/ARCHITECTURE.md`
