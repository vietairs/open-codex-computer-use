# Fast Channels Discovery: Apple Events, Accessibility Tree, Process Split

**Scope:** Every use of AppleScript/OSAScript/Apple Events/AccessibilityAPIs; process split; tree walking; entitlements.
**Search:** Swift source under `packages/OpenComputerUseKit/Sources/` and `apps/OpenComputerUse/Sources/`, docs, tests.

## 1. AppleScript / OSAScript / Apple Events Usage

| File:Line | Finding |
|-----------|---------|
| MCPServer.swift:16 | Explicit instruction: "Avoid falling back to AppleScript during a computer use session. Prefer Computer Use tools as much as possible to complete tasks." |
| docs/references/codex-computer-use-reverse-engineering/baseline-architecture.md:68 | Entitlement documented: `com.apple.security.automation.apple-events` (referenced as capability of official Codex service) |
| docs/references/stage-manager-background-control/01-macos-stage-manager-background-app-control.md | AppleScript mentioned as option for background app control (Stage Manager); explicitly noted as non-preferred vs UI interaction |
| plans/260720-1024-mac-session-guard-lock-detection/reports/codex-adversarial-plan-review-260720-report.md:16 | Instruction from MCP server avoiding AppleScript fallback |

**Finding:** Zero direct AppleScript/osascript/NSAppleScript/OSAScript usage in the main codebase. The instruction to avoid AppleScript is *prescriptive* (guidance to consumers), not defensive (unused legacy code).

---

## 2. Accessibility API Usage

### Entry Points: get_app_state & Snapshot Building

| File:Line | Function | Purpose |
|-----------|----------|---------|
| ComputerUseService.swift:472 | `getAppState(query:)` | Public tool: returns rendered AX tree snapshot + screenshot |
| ComputerUseService.swift:507 | `refreshSnapshot(for:textLimit:treeLimits:recoveryPolicy:)` | Fetches or rebuilds `AppSnapshot` via `SnapshotBuilder.build()` |
| AccessibilitySnapshot.swift:313 | `SnapshotBuilder.build()` | Main snapshot factory; calls `buildAccessibilitySnapshot()` |
| AccessibilitySnapshot.swift:381 | `buildAccessibilitySnapshot()` | Creates AX tree; instantiates TreeRenderer, renders root + menubar |

### Tree Walking

| File:Line | Function | Details |
|-----------|----------|---------|
| AccessibilitySnapshot.swift:881 | `TreeRenderer.render(root:depth:ancestors:)` | Recursive DFS walk of AX tree; enforces depth/node limits; detects cycles (line 886) |
| AccessibilitySnapshot.swift:882-883 | `shouldContinueRendering()` check | Halts if `nextIndex >= maxNodeCount` OR `depth >= maxDepth` |
| AccessibilitySnapshot.swift:910 | `children(of:)` call | Calls `AXUIElementCopyAttributeValue(element, kAXChildrenAttribute)` per child |

### Accessibility API Calls (AXUIElement)

| File:Line | API Call | Context |
|-----------|----------|---------|
| AccessibilitySnapshot.swift:328 | `AXUIElementCreateApplication(pid)` | Create app-level element for PID |
| AccessibilitySnapshot.swift:330 | `AXUIElementCreateSystemWide()` | Create system-wide element for focus queries |
| AccessibilitySnapshot.swift:1302 | `AXUIElementCopyElementAtPosition(appElement, Float(x), Float(y), &hitElement)` | Hit-test: locate element at screen coordinate (no full tree walk) |
| ComputerUseService.swift (multiple) | `AXUIElementCopyAttributeValue()` | Read role, children, title, position, size, value, etc. |
| ComputerUseService.swift (multiple) | `AXUIElementSetAttributeValue()` | Set value or boolean attributes; perform text input |
| ComputerUseService.swift (multiple) | `AXUIElementPerformAction()` | Trigger accessibility actions (press, confirm, menu, etc.) |
| ComputerUseService.swift (multiple) | `AXUIElementCopyActionNames()` | Query available actions on element |
| Permissions.swift | `AXIsProcessTrusted()` | Check if process has Accessibility permission |
| Permissions.swift | `AXIsProcessTrustedWithOptions()` | Check + optionally prompt for Accessibility access |

### Accessibility Tree Limits

| File:Line | Constant | Default Value |
|-----------|----------|---------------|
| AccessibilitySnapshot.swift:49 | `AccessibilityTreeLimits.defaultMaxNodeCount` | 1200 |
| AccessibilitySnapshot.swift:50 | `AccessibilityTreeLimits.defaultMaxDepth` | 64 |
| AccessibilitySnapshot.swift:92 | `accessibilityTreeMaxNodeCount` | 1200 |
| AccessibilitySnapshot.swift:93 | `accessibilityTreeMaxDepth` | 64 |

**Finding:** Full AX tree walk (all descendants) with depth/node caps. No AXObserver/notifications. No targeted role/title search without walking (except hit-test at coordinate). Depth cap is generous (64); node cap (1200) is a hard stop.

---

## 3. Process Split: MCP Stdio Server vs App Agent

### Architecture

| Layer | File | Details |
|-------|------|---------|
| **MCP Stdio Server** | packages/OpenComputerUseKit/Sources/.../MCPServer.swift | `StdioMCPServer` reads JSON-RPC on stdin, dispatches to `ComputerUseToolDispatcher` |
| **Tool Dispatcher** | packages/OpenComputerUseKit/Sources/.../ComputerUseToolDispatcher.swift | Shared service dispatch layer; reads `environment()` callback per request |
| **Accessibility/UI Service** | packages/OpenComputerUseKit/Sources/.../ComputerUseService.swift | Calls AX APIs, takes actions; runs in MCP process in stdio mode OR in app bundle via socket |
| **App Agent** | apps/OpenComputerUse/Sources/.../OpenComputerUse.swift (implied) | Hidden LSUIElement bundle; accepts socket connections, forwards requests to ComputerUseService, returns results |
| **Socket Proxy (CLI/Host)** | apps/OpenComputerUse/Sources/.../MacOSAppAgentProxy.swift | Client-side: opens Unix socket to app agent, sends JSON request, reads JSON response |
| **Socket Server (App Agent)** | apps/OpenComputerUse/Sources/.../SocketPeerAuthenticator.swift (receiver side implied) | Accepts connections, validates peer, forwards to `ComputerUseService` |

### Unix Socket Setup

| File:Line | Detail |
|-----------|--------|
| AppAgentSocketNamespace.swift:4 | Env var: `OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE` (optional namespace) |
| AppAgentSocketNamespace.swift:6-14 | `openComputerUseAppAgentSocketFileName(namespace:)` — returns socket filename; hashes namespace if provided; default `"open-computer-use-agent.sock"` under user temp dir |
| docs/ARCHITECTURE.md:42 | Socket location: user's temp directory (macOS `$TMPDIR`); namespace support avoids sharing with other OCU bundles |

### Peer Authentication (Same-uid + Code Signature)

| File:Line | Mechanism | Details |
|-----------|-----------|---------|
| SocketPeerAuthenticator.swift:29 | `getpeereid(fd, &peerUID, &peerGID)` | Extract peer process UID/GID from socket fd; reject if `peerUID != selfUID` |
| SocketPeerAuthenticator.swift:65 | `getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, ...)` | Retrieve audit token of peer process |
| SocketPeerAuthenticator.swift:74 | `SecCodeCopyGuestWithAttributes(nil, attributes, [], &peerCode)` | Convert audit token to SecCode object |
| SocketPeerAuthenticator.swift:88-90 | Code requirement string | `"anchor apple generic and certificate leaf[subject.OU] = "<team>"` + optional bundle identifier |
| SocketPeerAuthenticator.swift:95 | `SecCodeCheckValidity(code, [], requirement)` | Validate peer signature against requirement |
| AppAgentPeerAuthPolicy.swift:32-55 | `decide()` pure function | Decision logic: reject if UID mismatch; allow if signed + requirement satisfied; fallback if unsigned |

### Process Responsibility

| Process | Runs | Controls |
|---------|------|----------|
| MCP Stdio caller (e.g. Node.js server, curl) | Stdio transport | JSON-RPC messages |
| CLI / calling host (python, shell) | Creates socket connection | Sends request JSON, reads response JSON |
| **App Agent (Open Computer Use.app)** | **Unix socket server + Accessibility/ScreenCaptureKit** | **Actual AX tree reads, input synthesis, screenshot capture** |

**Finding:** All Accessibility API calls run in the app bundle (TCC-authorized). Socket proxy validates peer = same-uid + same-team code signature. Unsigned dev builds accept same-uid only (with stderr notice).

---

## 4. NSWorkspace & Process Launch

| File:Line | API | Use |
|-----------|-----|-----|
| ComputerUseService.swift:609 | `NSWorkspace.shared.frontmostApplication?.processIdentifier` | Save/restore active app during cursor target visualization |
| AppDiscovery.swift | `NSWorkspace.shared.runningApplications` | List active processes to match query string |
| AppDiscovery.swift | `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` | Locate app bundle by identifier |
| AppDiscovery.swift | `NSWorkspace.shared.openApplication(at:configuration:)` | Launch app if not running; async callback on completion |
| Permissions.swift | `NSWorkspace.shared.open(permission.settingsURL)` | Open System Settings to permission page |
| AccessibilitySnapshot.swift:456 | `Process()` + `/usr/bin/open -b <bundleID>` | Fallback window recovery: spawn `/usr/bin/open` to activate app |

**Finding:** NSWorkspace for app discovery, launch, and settings navigation. Direct Process() call to `/usr/bin/open` for window recovery (one-shot, not a fast channel).

---

## 5. Entitlements & Hardened Runtime

| File | Reference | Detail |
|------|-----------|--------|
| docs/references/codex-computer-use-reverse-engineering/baseline-architecture.md:68 | Documented entitlement | `com.apple.security.automation.apple-events` (official Codex service) |
| docs/histories/.../hardened-runtime*.md | Historical record | Hardened runtime required for Developer ID notarization; applied to `Cursor Motion` and release bundles |
| docs/ARCHITECTURE.md:51 | Security note | Socket has peer authentication; code-signing validation in `SocketPeerAuthenticator` |

**Finding:** No `.entitlements` file in repo (built into Info.plist or Xcode project). Hardened runtime enabled for releases. Apple Events entitlement documented as present in *reference* codebase (official Codex), not in this fork.

---

## 6. Targeted Search / Non-Full-Tree Paths

### Hit-Test (Coordinate → Element)

| File:Line | Function | Mechanism |
|-----------|----------|-----------|
| ComputerUseService.swift:1298-1310 | `hitTestElement(at:in:snapshot:)` | Call `AXUIElementCopyElementAtPosition(appElement, globalX, globalY, &hitElement)` — direct coordinate-to-element without tree walk |

### Snapshot Reuse

| File:Line | Mechanism | Benefit |
|-----------|-----------|---------|
| ComputerUseService.swift:460 | `snapshotsByApp: [String: AppSnapshot]` | Cache snapshot per app; reuse if unchanged |
| ComputerUseService.swift:961-967 | `currentSnapshot()` → `refreshSnapshot()` | Return cached snapshot if query matches; rebuild only on stale cache |

### Compact View (Actionable Elements Only)

| File:Line | Feature | Details |
|-----------|---------|---------|
| AccessibilitySnapshot.swift:158-203 | `compactActionableLines()` | Filter full tree to *actionable* elements only (expose actions or settable value); reorder by focus; reuse `treeLineOffsets` (no re-render) |
| AccessibilitySnapshot.swift:228-260 | `isActionableForCompactView()` | Exclude synthetic text, static-text with ubiquitous actions; keep text entry roles |

**Finding:** No full tree → filtered tree walk; instead, tree walk renders all, then compact view filters cached results. No mid-walk pruning.

---

## 7. Tests Touching Fast Channels

| File:Line | Test Name | Scope |
|-----------|-----------|-------|
| OpenComputerUseKitTests.swift:7 | `testAppAgentSocketFileNamePreservesLegacyDefault` | Socket namespace handling |
| OpenComputerUseKitTests.swift:12 | `testAppAgentSocketFileNameIsDeterministicAndNamespaced` | Socket namespace determinism |
| OpenComputerUseKitTests.swift:1430 | `testAccessibilityTreeBudgetAllowsDeepElectronWebViews` | Depth limit enforcement (Electron 64-depth trees) |
| OpenComputerUseKitTests.swift:1443 | `testAccessibilityRendererElidesEmptyGenericElectronWrappers` | Node elision strategy |
| OpenComputerUseKitTests.swift:1573-1815 | (20+ tests) | Tree rendering: action filtering, role suppression, link text, placeholder, compact view logic |
| DecisionSidecarVerifierTests.swift | (implied) | Sidecar socket binding verification (llama-server loopback port) |

---

## 8. Summary: Existing Fast Channels (Non-Full-Walk)

| Channel | Mechanism | API | Cost |
|---------|-----------|-----|------|
| **Hit-test** | AX single-point query | `AXUIElementCopyElementAtPosition()` | O(1) (direct, no walk) |
| **Snapshot cache** | In-process memory | App-keyed dictionary | O(1) lookup; miss → rebuild |
| **Compact actionable** | Post-walk filter | Tree walk once, filter cached results | O(n walk) + O(m filter) where m << n |
| **Focused element** | AX query + sync walk | `AXFocusedElement` attribute + ancestor synthesis | O(depth) |

---

## 9. Current Architectural Gaps (Observational)

| Gap | Why It Matters | Current Workaround |
|-----|----------------|--------------------|
| No targeted AX search by role/label/identifier without walk | Full tree needed even for "find button titled X" | Full walk; filter in compact view |
| No AXObserver for live tree changes | Agent must poll via full snapshot rebuild | Caller decides refresh timing |
| Tree depth/node limits are hard stops | Truncates very large trees (e.g. 5000-node webpage) | Documented limits (1200 nodes, 64 depth) |
| No scripting dictionary / JXA paths | Only AX tree is available for non-special apps | Full reliance on Accessibility APIs |

---

## Search Coverage & Limitations

**Searched:** 
- All Swift files in `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/` and `apps/OpenComputerUse/Sources/OpenComputerUse/`
- All docs under `docs/` (except `.claude/` worktrees)
- Test suite in `packages/OpenComputerUseKit/Tests/`
- Grep for `AppleScript`, `osascript`, `NSAppleScript`, `AXObserver`, `socket`, `peer`, `getpeereid`, `LOCAL_PEERTOKEN`

**Not Found (nil result = not present):**
- `.entitlements` files (likely in Xcode project, not repo)
- `NSAppleScript` / `OSAScript` / `osascript` usage (zero instances in main code)
- `AXObserver` / `AXNotification` registration (no live observers)
- Scripting Bridge / `SBApplication` calls
- JXA runtime invocation
- URL schemes handler registration
- Shortcuts.app integration

Status: DONE
Summary: Socket-based process split with peer auth (getpeereid + code signature). Full AX tree walk with hard 1200-node, 64-depth caps. No AppleScript usage; explicit guidance to avoid it. Hit-test is the only targeted non-walk AX query; no live observers or scripting dictionaries.
Concerns: Tree limits enforce truncation on large pages (5000+ node webs). No feedback mechanisms for tree changes (screenshot + snapshot pair only).
