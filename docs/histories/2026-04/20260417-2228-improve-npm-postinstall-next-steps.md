## [2026-04-17 22:28] | Task: Strengthen the next-steps prompt after npm install

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> After a global npm install of `open-computer-use`, remind the user of the installed version and next actions; first have the user run `open-computer-use doctor`, then authorize Accessibility and Screen Recording, then print a block of JSON that can be pasted directly into an MCP-capable client.

### 🛠 Changes Overview
**Scope:** `scripts/npm/build-packages.mjs`, `README.md`

**Key Actions:**
- **Added a postinstall version prompt**: The npm install now prints `${packageName}@${version}` instead of just the package name.
- **Added first-use guidance**: Moved `open-computer-use doctor` up to the first step after install, with an explicit prompt to authorize `Accessibility` and `Screen Recording`.
- **Added MCP config output text**: The install prompt now prints copy-pasteable `mcpServers` JSON directly, along with a link to the npm package page.
- **Synced the README**: The repo's front-page npm install instructions were updated to match the path now shown in the actual post-install prompt.
- **Added npm page install instructions**: Both the `Install` section and the short description in the npm package README template now explicitly state "run `open-computer-use doctor` first after installing."

### 🧠 Design Intent (Why)
The core of this package's first-run experience is not "install succeeded" itself, but getting the user through authorization and connected to an MCP client in the shortest path possible. Putting the version number, `doctor`, permission instructions, and JSON config directly into postinstall, and repeating them in both the npm page body and the short description, reduces how often users have to go back to the docs after installing.

### 📁 Files Modified
- `scripts/npm/build-packages.mjs`
- `README.md`
- `docs/histories/2026-04/20260417-2228-improve-npm-postinstall-next-steps.md`
