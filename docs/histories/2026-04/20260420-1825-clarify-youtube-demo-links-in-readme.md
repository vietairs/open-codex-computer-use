## [2026-04-20 18:25] | Task: clarify README YouTube demo links

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5 family (Codex)`
* **Runtime**: `Codex CLI`

### 📥 User Query
> The YouTube links in the README render like plain images, which makes it hard to tell they're actually videos; wanted this explained and the presentation made clearer.

> A follow-up request asked to condense the explicit explanation into something more concise, changing it to a centered caption below the video thumbnail.

> Then a further request said a base64 image had already been prepared, and wanted a replaceable placeholder left in the README along with instructions on how to wire it in.

> Finally, two local PNGs were provided, to be moved directly into the repo to serve as the official cover images.

### 🛠 Changes Overview
**Scope:** `repository docs`

**Key Actions:**
- **[Centered captions]**: Kept the existing thumbnail links in both demo sections of the English and Chinese READMEs, and changed the explanatory text into a centered caption below the image.
- **[Less visual noise]**: Removed the extra explanation line above the image, avoiding repeated text breaking up the top of the README and between sections.
- **[Custom cover placeholder]**: Added a comment-style placeholder at the top demo section of both READMEs, documenting the convention of decoding the base64 to a fixed path in the repo and then swapping in the image reference.
- **[Repo-local covers]**: Moved the two user-provided `1280x720` PNGs into `docs/generated/readme-assets/`, and switched both video covers in the English and Chinese READMEs to repo-relative paths.
- **[History sync]**: Added a history entry for this doc change, keeping the README presentation strategy change traceable.

### 🧠 Design Intent (Why)
GitHub README doesn't auto-render a plain external video-thumbnail link as an embedded card with a play button or a YouTube badge. Without introducing an iframe, a custom cover image plus a caption below it is a more direct way to communicate this. Landing the final cover assets in a fixed in-repo directory and referencing them via relative paths matches GitHub README's stable rendering behavior, and is more maintainable than keeping a base64 placeholder or an external thumbnail link.

### 📁 Files Modified
- `README.md`
- `README.zh-CN.md`
- `docs/generated/readme-assets/open-computer-use-demo-cover.png`
- `docs/generated/readme-assets/cursor-motion-demo-cover.png`
- `docs/histories/2026-04/20260420-1825-clarify-youtube-demo-links-in-readme.md`
