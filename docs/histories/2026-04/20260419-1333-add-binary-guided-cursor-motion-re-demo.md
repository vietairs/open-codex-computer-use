## [2026-04-19 13:33] | Task: Add a standalone cursor motion reverse-engineering demo

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `gpt-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Keep digging into the official cursor motion, and build a demo in a standalone directory that doesn't conflict with `CursorMotion`; ideally it can take a start/end point and output the path and velocity-related sampling.

### 🛠 Changes Overview
**Scope:** `scripts/cursor-motion-re/`, `docs/exec-plans/active/`, `docs/references/`, `docs/histories/`

**Key Actions:**
- **[Add a standalone execution plan]**: Created a separate plan under `docs/exec-plans/active/` for this reverse-engineering + scripted-demo track, explicitly stating it does not touch `CursorMotion`.
- **[Implement the scripted reverse-engineering tool]**: Added `scripts/cursor-motion-re/`, implementing minimal Mach-O section parsing, Swift field-metadata recovery, and extraction of constant / candidate coefficient tables from the official binary in pure Python.
- **[Implement the binary-guided demo]**: Added a CLI supporting two subcommands, `inspect` and `demo`; `demo` can generate candidate paths, measurements, and sample-point JSON for a given start/end point, defaulting to a condensed `candidate_summaries + chosen_candidate` output.
- **[Confirm candidate scoring and selection]**: Fed the score formula from `0x100060da0` and the "prefer in-bounds, then choose minimum score" strategy back into the script's output, replacing the previously guessed weights.
- **[Continue lifting candidate geometry]**: Landed the real field layout of `CursorMotionPath/Segment` from `0x10005fd98`, the guide vector, the two base candidates, the `3 x 3 x 2` arched candidates, and the total of `20` candidates directly into the script, moving past the earlier state of "missing the second base candidate."
- **[Fill in timing evidence]**: Continued drilling through Swift metadata, type descriptors, and the function chain to confirm the real field relationships of `ComputerUseCursor.CloseEnoughConfiguration`, `CursorNextInteractionTiming`, `Animation.SpringParameters`, `AnimationDescriptor`, `Transaction`, and `VelocityVerletSimulation.Configuration`, and wrote the cursor path animation's `response=1.4`, `dampingFraction=0.9`, `dt=1/240`, `idleVelocityThreshold=28800`, and `ComputerUseCursor.Window`'s animation state slots back into the script and docs.
- **[Fill in the VelocityVerlet math]**: Kept digging through `0x100593cfc`, `0x100593f18`, `0x100593404`, and `0x100594110`, landing `stiffness = min((2π / response)^2, 28800)`, `drag = 2 * dampingFraction * sqrt(stiffness)`, the stale-time clamp, and the single-step `VelocityVerlet` update order all into the standalone script.
- **[Recover the SpringAnimation finished predicate]**: Continued taking apart `0x1005761bc` / `0x1005934b0`, confirming that the frame update runs the finished predicate after advancing the simulation, and recorded the threshold-square gate, the `0.01` float-literal broadcast, the exact-zero bidirectional comparison, and the cautious inference that "the endpoint locks first, and finished may still only become true later."
- **[Consolidate the function-level analysis]**: Added `software-cursor-motion-reconstruction.md`, capturing the confirmed `sample(progress)`, `CursorMotionPathMeasurement`, the candidate score formula, and the shape of the total candidate count on its own.
- **[Sync directory navigation]**: Updated the reverse-engineering README to add the new reconstruction doc to the index.

### 🧠 Design Intent (Why)
Another session is already actively working on `CursorMotion`, so directly continuing to modify the experimental target carried too much risk. This round instead used a standalone script under `scripts/`, which lets the closed-source implementation continue to be dug into while also cleanly separating "confirmed" from "still under reconstruction" parts, making them easier to replace incrementally later.

### 📁 Files Modified
- `docs/exec-plans/active/20260419-official-cursor-motion-reconstruction.md`
- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-motion-reconstruction.md`
- `docs/histories/2026-04/20260419-1333-add-binary-guided-cursor-motion-re-demo.md`
- `scripts/cursor-motion-re/README.md`
- `scripts/cursor-motion-re/official_cursor_motion.py`
- `scripts/cursor-motion-re/reconstruct_cursor_motion.py`
