## [2026-04-20 11:51] | Task: Dig into the binary mapping of the cursor slider

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Now that we have these parameter knobs, let's go back into the binary and dig up what we reverse-engineered before, check whether the binary actually has something for each of these knobs, and see what effect adjusting each one actually has on the real curve.

### 🛠 Changes Overview
**Scope:** `scripts/cursor-motion-re/`, `docs/references/`, `docs/exec-plans/`

**Key Actions:**
- **[Add a slider-study analysis entry point]**: added a `slider-study` subcommand to `scripts/cursor-motion-re/official_cursor_motion.py` / `reconstruct_cursor_motion.py`, which outputs a shipping-bundle phrase scan, binary-confirmed motion terms, and a parameter-sensitivity analysis for the 5 sliders.
- **[Fill in the shipping-bundle evidence boundary]**: clearly recorded that the current release bundle does not match the full phrases `START HANDLE`, `END HANDLE`, `ARC SIZE`, or `ARC FLOW`; `SPRING` / `DEBUG` / `MAIL` / `CLICK` only match as ambiguous tokens, and this is no longer mis-written as "the debug UI from the video is still shipping in the release app."
- **[Land the slider-mapping doc]**: added `software-cursor-slider-parameter-investigation.md`, separately landing the binary-confirmed geometry / timing quantities corresponding to `start/end handle`, `arc size/flow`, and `spring`, along with the actual curve effects under a default sample and a more-centered sample.
- **[Sync the wording of the older doc]**: `software-cursor-motion-model.md` no longer just says "the video shows a slider UI"; it now also notes that the current shipping-bundle phrase scan does not directly match this set of labels.
- **[Add a new independent execution plan]**: added a new active execution plan for this round of parameter-mapping investigation, so it no longer crowds into the earlier cursor-reconstruction or CursorMotion UI tasks.

### 🧠 Design Intent (Why)
The key point of this round isn't to keep guessing what the 5 sliders look like in the UI, but to clearly separate "what can still be directly confirmed in the release binary" from "how we infer the sliders' effect on the curve based on those quantities." That way, when we keep digging into `ARC FLOW` or a spring remap later, we won't mix up shipping evidence, video evidence, and local lab tuning.

### 📁 Files Modified
- `scripts/cursor-motion-re/official_cursor_motion.py`
- `scripts/cursor-motion-re/README.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-slider-parameter-investigation.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-motion-model.md`
- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/exec-plans/active/20260420-cursor-slider-binary-investigation.md`
