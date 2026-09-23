## [2026-04-17 23:18] | Task: Fix the 0.1.7 / 0.1.8 release workflow build failure

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Look into why both `0.1.7` and `0.1.8` failed to publish; check the action.

### 🛠 Changes Overview
**Scope:** `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`

**Key Actions:**
- **Located the release failure root cause**: confirmed via GitHub Actions logs that both `v0.1.7` and `v0.1.8` failed at the `Build npm release artifacts` stage, never reaching artifact upload or npm publish.
- **Fixed an Xcode 26 compile error**: changed the `AXUIElement` property read in the permission onboarding window from a conditional downcast to an explicit `CFTypeID` check followed by a forced cast, avoiding Xcode 26.2's compile error for CoreFoundation types where "a conditional downcast will always succeed."
- **Preserved existing behavior boundaries**: only returns the element when the AX property read succeeds and it is actually an `AXUIElement`, avoiding changes to the existing window lookup logic just to satisfy the compiler.

### 🧠 Design Intent (Why)
This release failure wasn't about publish permissions, trusted publishing, or the tag trigger condition — it was CI's newer compiler applying stricter static checks to CoreFoundation bridging types. Explicitly comparing `CFTypeID` makes the "is the type correct" check explicit while keeping runtime semantics stable, which fits this kind of code path that talks to the system Accessibility API.

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/PermissionOnboardingApp.swift`
- `docs/histories/2026-04/20260417-2318-fix-release-build-on-xcode-26.md`
