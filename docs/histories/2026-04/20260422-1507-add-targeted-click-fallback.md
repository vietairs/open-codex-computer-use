## [2026-04-22 15:07] | Task: add targeted click fallback

### 🤖 Execution Context
* **Agent ID**: `019db3f1-0538-7a70-bdd4-19395299085c`
* **Base Model**: `GPT-5 Codex`
* **Runtime**: `Codex CLI`

### 📥 User Query
> okie, try to optimize it, the key thing is that I don't wanna to grab user mouse, offical computer use can do it, so as we can

### 🛠 Changes Overview
**Scope:** `OpenComputerUseKit`, `docs/ARCHITECTURE.md`, `docs/histories/`

**Key Actions:**
- **[Targeted click fallback]**: Added a `CGEvent.postToPid` targeted mouse-event fallback for `click`, to avoid defaulting straight to the global HID path — which moves the real mouse — after an AX failure.
- **[Semantic click ordering]**: Reordered the AX sequence for element-targeted/coordinate `click`: try direct semantic actions and descendant `AXOpen` candidates first, and push `AXRaise`/focus-style activation later, to avoid a false success on things like the Finder sidebar that only focus without navigating.
- **[Behavior docs]**: Updated the architecture docs to state that `click`'s order is now `AX -> pid-targeted mouse event -> optional global pointer fallback`.
- **[Live validation]**: Used the Finder sidebar's `Applications` item as a real-sample regression, confirming the default path can click through without grabbing the user's mouse.

### 🧠 Design Intent (Why)
Official Computer Use can still click successfully on targets with incomplete AX, like Finder, without defaulting to hijacking the user's hardware mouse. The local implementation also needs to try the narrower targeted-event path first, keeping the global physical pointer fallback as an explicit, opt-in last resort.

A subsequent regression uncovered a subtler behavioral issue: a Finder sidebar row itself may allow a `focus`/`main`-style activation to succeed, but that does not mean navigation actually happened. Placing that step before `AXOpen` would misreport "focused but didn't switch pages" as a successful click, so the ordering must keep converging on "semantic click first, focus/activation as fallback."

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/InputSimulation.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-04/20260422-1507-add-targeted-click-fallback.md`
