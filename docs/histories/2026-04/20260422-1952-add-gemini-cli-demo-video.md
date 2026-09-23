## [2026-04-22 19:52] | Task: Add a Gemini CLI MCP demo video to the README

### 🤖 Execution Context
* **Agent ID**: `Codex`
* **Base Model**: `GPT-5 family (Codex)`
* **Runtime**: `Codex CLI on macOS`

### 📥 User Query
> Copy the provided `output.mp4` into the repo for demo use, rename it if needed, and add it to the README with a description showing Gemini CLI using our MCP.

### 🛠 Changes Overview
**Scope:** README docs, history

**Key Actions:**
- **[Attachment Link]**: updated `README.md` and `README.zh-CN.md` to use the user-provided GitHub `user-attachments` video link directly, so the README references the externally hosted video resource instead of committing the video file into the repo.
- **[Storage Cleanup]**: cleaned up the local video/GIF asset commits introduced during this task, avoiding leaving large binary files sitting in the branch history taking up repo storage.
- **[History]**: kept maintaining this same history entry to clearly record the final README presentation approach and the storage trade-off.

### 🧠 Design Intent (Why)
The focus of this task was to have the README reference the video already hosted on GitHub directly, while not continuing to stuff `.mp4` / GIF binaries into the repo history. This keeps the demo entry point at the top of the README while avoiding an unnecessary, ongoing storage burden on the repo just to show a video.

### 📁 Files Modified
- `README.md`
- `README.zh-CN.md`
- `docs/histories/2026-04/20260422-1952-add-gemini-cli-demo-video.md`
