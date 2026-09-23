## [2026-04-17 11:56] | Task: Lay the groundwork for computer-use reverse-engineering analysis

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Analyze `SkyComputerUseClient` and `Codex Computer Use.app`, and continuously land the results into a dedicated directory under `docs/` following repo conventions, then later consider an open-source implementation based on what's gathered.

### 🛠 Changes Overview
**Scope:** `docs/`

**Key Actions:**
- **[Execution Plan]**: Created a long-running execution plan, establishing a research-first, implementation-second approach.
- **[Research Docs]**: Created a dedicated reverse-engineering analysis directory, recording baseline architecture and runtime / host dependency conclusions.
- **[Docs Index]**: Updated `docs/references/README.md` to add this analysis material to the repo index.
- **[Probe Script]**: Added a minimal `stdio` probe script to directly reproduce `SkyComputerUseClient mcp`'s startup and exit behavior in pipe/stdin mode.

### 🧠 Design Intent (Why)
This work spans multiple rounds and involves reverse-engineering a closed-source bundle, so the core conclusions can't be left in chat context. Establish the long-running plan and a dedicated analysis directory first, so each subsequent round can accumulate evidence and refine judgments in the same set of docs, before converging on an open-source implementation approach.

### 📁 Files Modified
- `scripts/probe-cua-stdio.js`
- `docs/exec-plans/active/20260417-open-source-computer-use-reverse-engineering.md`
- `docs/references/README.md`
- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/references/codex-computer-use-reverse-engineering/baseline-architecture.md`
- `docs/references/codex-computer-use-reverse-engineering/runtime-and-host-dependencies.md`
- `docs/histories/2026-04/20260417-1156-open-source-computer-use-research-foundation.md`

## [2026-04-17 12:10] | Task: Reproduce the computer-use direct-connection failure directly with the Python MCP SDK

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Skip Inspector, just init `uv`, then write a minimal client yourself with the Python MCP SDK and try it.

### 🛠 Changes Overview
**Scope:** `pyproject.toml`, `uv.lock`, `scripts/`, `docs/`

**Key Actions:**
- **[UV Bootstrap]**: Initialized a repo-level `uv` Python project scaffold and installed the `mcp` dependency.
- **[Python Probe]**: Added `scripts/probe_cua_mcp_python.py`, using the Python `mcp` SDK's `stdio_client + ClientSession.initialize()` for a minimal direct-connection experiment.
- **[Runtime Evidence]**: Reproduced a `BrokenResourceError` at the `initialize` stage via the Python SDK, and confirmed the system simultaneously generated a new `Launch Constraint Violation` crash report.
- **[Docs Sync]**: Added the Python SDK reproduction path and conclusions to the reverse-engineering docs and execution plan.

### 🧠 Design Intent (Why)
Inspector wraps a proxy layer and frontend interaction, which is too large a failure surface. Reproducing directly with the official Python MCP SDK compresses the problem to its minimum: the `stdio` process launches successfully, but the pipe breaks right at the `initialize` write stage, while the system simultaneously logs a launch-constraint kill. This evidence chain is cleaner than Inspector's and is better suited for continued reverse engineering.

### 📁 Files Modified
- `pyproject.toml`
- `uv.lock`
- `scripts/probe_cua_mcp_python.py`
- `docs/exec-plans/active/20260417-open-source-computer-use-reverse-engineering.md`
- `docs/references/codex-computer-use-reverse-engineering/runtime-and-host-dependencies.md`
- `docs/histories/2026-04/20260417-1156-open-source-computer-use-research-foundation.md`

## [2026-04-17 12:18] | Task: Converge evidence on the Codex host IPC and parent constraint

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Keep analyzing.

### 🛠 Changes Overview
**Scope:** `docs/`

**Key Actions:**
- **[Parent Constraint]**: Confirmed via the surviving process's parent chain and signing info that a long-lived `SkyComputerUseClient mcp` process is essentially always hanging off a Codex host process under OpenAI Team ID `2DC432GLL2`.
- **[Appserver IPC]**: Confirmed via `lsof` and strings that `SkyComputerUseService` connects to the `codex-ipc/ipc-501.sock` Unix socket held by `Codex.app`.
- **[Host Integration]**: Added implementation traces regarding the service's `CodexAppServerJSONRPCConnection`, auth cache/provider, plugin installation, and notify hook updates.

### 🧠 Design Intent (Why)
At this point, the problem is no longer just "an external stdio call can't start the official client" — it's that "the official computer-use depends on a private Codex host IPC layer." Writing this relationship down clearly lets the open-source version make a more explicit choice: directly drop the private host coupling, rather than mistakenly treating it as a necessary part of the computer-use core.

### 📁 Files Modified
- `docs/references/codex-computer-use-reverse-engineering/baseline-architecture.md`
- `docs/references/codex-computer-use-reverse-engineering/runtime-and-host-dependencies.md`
- `docs/histories/2026-04/20260417-1156-open-source-computer-use-research-foundation.md`

## [2026-04-17 12:04] | Task: Add the computer-use tools schema

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Based on the current analysis, continue analyzing the names and parameters of all of codex computer use's tools; organize the tool definition schemas into the docs as structured code blocks, for easy viewing.

### 🛠 Changes Overview
**Scope:** `docs/`

**Key Actions:**
- **[Tool Schemas]**: Completed documentation of the 9 tools `computer-use` currently exposes publicly in the baseline architecture doc, adding a structured code-block schema for each tool.
- **[Runtime Notes]**: Added return shapes and usage semantics based on the actual results of calling `list_apps` and `get_app_state` in the current session.
- **[Compatibility Notes]**: Added interface-layer judgments aimed at an open-source compatibility layer, clarifying the role boundaries of `get_app_state`, `element_index`, and coordinate mode.

### 🧠 Design Intent (Why)
The previous round of docs only confirmed the tool list, without organizing the parameter surface and call semantics into a format directly usable for compatibility-layer design. With the schema now structured into the repo, future open-source MCP reimplementation work can pull the interface directly from this doc, without needing to dig through scattered chat conclusions again.

### 📁 Files Modified
- `docs/references/codex-computer-use-reverse-engineering/baseline-architecture.md`
- `docs/histories/2026-04/20260417-1156-open-source-computer-use-research-foundation.md`

## [2026-04-17 12:34] | Task: Add packaging structure and turn-ended lifecycle integration notes

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Keep analyzing.

### 🛠 Changes Overview
**Scope:** `docs/`

**Key Actions:**
- **[Packaging Layout]**: Added a dedicated doc recording the official plugin's root directory, `.codex-plugin/plugin.json`, `.mcp.json`, and the main app's distribution structure.
- **[Lifecycle Hook]**: Combined `SkyComputerUseClient --help`, `~/.codex/config.toml`, and strings from the `Codex` host to confirm that `turn-ended` is a callback entry point hanging off the legacy notify / `after_agent` lifecycle.
- **[Distribution Evidence]**: Added observations on `LSUIElement`, the Sparkle update source, embedded resource bundles, the application group container, and the provisioning profile.

### 🧠 Design Intent (Why)
The earlier docs already clarified the runtime host dependency, but "how does Codex see this plugin" and "which lifecycle chain does `turn-ended` actually belong to" hadn't been documented on their own yet. With this interface surface written up separately, later open-source design work can more clearly distinguish what's part of the MCP capability itself versus what's just the official host's integration method.

### 📁 Files Modified
- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/references/codex-computer-use-reverse-engineering/packaging-and-lifecycle-integration.md`
- `docs/histories/2026-04/20260417-1156-open-source-computer-use-research-foundation.md`

## [2026-04-17 12:47] | Task: Converge the client-service internal IPC surface

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Keep analyzing.

### 🛠 Changes Overview
**Scope:** `docs/`

**Key Actions:**
- **[Internal IPC]**: Added a dedicated doc organizing the `ComputerUseIPC*` type family, confirming there's a local protocol between client and service that is separate from MCP.
- **[Request Families]**: Converged the `ListAppsRequest`, `AppGetSkyshotRequest`, `AppPerformActionRequest`, `AppModifyRequest`, `CodexTurnEndedRequest`, `AppUsageRequest`, and other request families.
- **[Security Boundary]**: Added evidence on `ComputerUseIPCSenderAuthorization`, `CodeSignature`, `Requirement`, and other sender-auth mechanisms, and recorded the service's active-client / idle-timeout self-reclamation semantics.

### 🧠 Design Intent (Why)
At this point, it's clear the official implementation is not "an MCP server directly touching system APIs," but has at least one internal IPC layer separating the MCP client from the desktop automation service. With this protocol stack documented on its own, the open-source version can more clearly decide whether to keep this separation, and if so, how to design the sender-auth and skyshot model as a transparent, implementable open-source approach.

### 📁 Files Modified
- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/references/codex-computer-use-reverse-engineering/internal-ipc-surface.md`
- `docs/histories/2026-04/20260417-1156-open-source-computer-use-research-foundation.md`

## [2026-04-17 12:56] | Task: Reinforce internal IPC transport judgment with real tool calls

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Keep analyzing.

### 🛠 Changes Overview
**Scope:** `docs/`

**Key Actions:**
- **[Live Runtime Check]**: Started the service via a real `computer-use` `get_app_state(Finder)` call, then re-checked processes and handles with `lsof`/`pgrep`.
- **[Transport Evidence]**: Confirmed that the only persistently visible Unix socket on the service side remains `codex-ipc/ipc-501.sock`, connecting to the Codex host, with no client-service resident Unix socket observed.
- **[Inference Tightening]**: Further tightened the client-service transport judgment to "more likely XPC, a short-lived local channel, or some other non-visible transport," avoiding mistakenly writing it up as an ordinary local socket.

### 🧠 Design Intent (Why)
The previous round already confirmed the `ComputerUseIPC*` protocol family from type names, but the transport form was still a guess. Adding a real runtime counter-check makes it possible to more clearly rule out the oversimplified assumption that "client and service maintain a long-lived ordinary Unix socket between them."

### 📁 Files Modified
- `docs/references/codex-computer-use-reverse-engineering/internal-ipc-surface.md`
- `docs/histories/2026-04/20260417-1156-open-source-computer-use-research-foundation.md`

## [2026-04-17 13:03] | Task: Converge the turn-ended payload wire shape and caller restrictions

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Keep analyzing.

### 🛠 Changes Overview
**Scope:** `docs/`

**Key Actions:**
- **[Wire Shape]**: Confirmed the precise JSON structure of the `notify` / `after_agent` legacy-compat payload via `codex-rs/hooks/src/legacy_notify.rs` in the official `openai/codex` open-source repo.
- **[Lifecycle Mapping]**: Mapped this JSON wire shape back to `SkyComputerUseClient turn-ended <payload>`, upgrading the earlier "likely" conclusion into one backed by source evidence.
- **[Action-Time Validation]**: Ran `turn-ended` locally from an external shell with both valid and invalid payloads, observing `status=137` and a `Launch Constraint Violation` crash report in both cases, confirming it also isn't a standalone CLI callable by any arbitrary caller.

### 🧠 Design Intent (Why)
We already knew `turn-ended` was part of lifecycle integration, but two pieces of hard evidence were still missing: what the payload actually looks like, and whether it can be used as a generic command by any external caller. With both pinned down, the open-source version can more clearly separate "the structure of the lifecycle notification" from "the official host's trust restrictions."

### 📁 Files Modified
- `docs/references/codex-computer-use-reverse-engineering/packaging-and-lifecycle-integration.md`
- `docs/references/codex-computer-use-reverse-engineering/runtime-and-host-dependencies.md`
- `docs/histories/2026-04/20260417-1156-open-source-computer-use-research-foundation.md`

## [2026-04-17 13:10] | Task: Tighten the previous-notify boundary judgment

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Keep analyzing.

### 🛠 Changes Overview
**Scope:** `docs/`

**Key Actions:**
- **[Core Comparison]**: Compared against `config/mod.rs`, `hooks/legacy_notify.rs`, and `hooks/registry.rs` in the official `openai/codex` open-source core, confirming the core `notify` mechanism itself only recognizes argv + a trailing JSON payload, with no `previous-notify` concept.
- **[Boundary Tightening]**: Tightened the judgment on `--previous-notify` from "possibly a chained argument" to "more likely a compatibility wrapper argument introduced by `SkyComputerUseClient turn-ended` itself, not part of the Codex core hook API."
- **[Open Question Update]**: Narrowed the open question to "this argument's specific encoding format" rather than "whether it belongs to the core notify mechanism."

### 🧠 Design Intent (Why)
The value of this step is separating "the official host's own compatibility wrapper" from "Codex's core public hook mechanism." Going forward, the open-source design won't mistakenly treat `previous-notify` as a Codex core protocol field that must be supported, but will instead treat it as a private migration detail of the official plugin taking over notify configuration.

### 📁 Files Modified
- `docs/references/codex-computer-use-reverse-engineering/packaging-and-lifecycle-integration.md`
- `docs/histories/2026-04/20260417-1156-open-source-computer-use-research-foundation.md`

## [2026-04-17 12:41] | Task: Converge permission onboarding and drag-guidance window clues

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> I noticed that during authorization it creates a window that lets you directly drag the codex computer use.app into it, without needing to find it yourself.

### 🛠 Changes Overview
**Scope:** `docs/`

**Key Actions:**
- **[Permission Evidence]**: Converged strings such as `Accessibility`, `Screen Recording`, `TCCDialogSystemPermission`, `permissionsWindow`, and `permissionState`, confirming that both permission gating and the permission window are built-in capabilities of the main service.
- **[Accessory UI Evidence]**: Added naming evidence for `SystemSettingsAccessoryWindow`, `SystemSettingsAccessoryTransitionOverlayWindow`, `ArrowWindow`, and `SystemSettingsAccessoryWindowDragDelegate`, confirming the official implementation built a custom accessory UI around System Settings.
- **[Drag Flow Inference]**: Recorded naming such as `DraggableApplicationView`, `dragDelegate`, `dragContinuation`, and `draggable`, and mapped them to the user's observed experience of "dragging the app in to authorize."
- **[Docs Index]**: Added a dedicated permission onboarding doc, and updated the reverse-engineering material index.

### 🧠 Design Intent (Why)
This finding advances the official experience from "just checking TCC permission" to "a productized onboarding flow built around the macOS authorization process." For an open-source implementation, this difference matters, since it determines whether the initial permission setup is smooth, and whether we should later replicate a System Settings accessory window rather than just popping a hint message.

### 📁 Files Modified
- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/references/codex-computer-use-reverse-engineering/permission-onboarding.md`
- `docs/histories/2026-04/20260417-1156-open-source-computer-use-research-foundation.md`

## [2026-04-17 12:46] | Task: Extract computer-use visual asset samples

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Sure, how would you extract the visual assets? Give it a try?

### 🛠 Changes Overview
**Scope:** `docs/`

**Key Actions:**
- **[Asset Extraction]**: Used AppKit's `Bundle.image(forResource:)` to export assets such as `SoftwareCursor`, `HintArrow`, `CUAAppIcon_Assets/cursor`, `CUAAppIcon_Assets/cursor dark`, and `menubar-cursor` directly from the official bundle as PNGs.
- **[Verification]**: Recorded the exported files' dimensions, alpha channel, and hash; confirmed that `SoftwareCursor` exported from `Package_SlimCore.bundle` and `Package_ComputerUse.bundle` is binary-identical.
- **[Asset Archive]**: Archived the exported PNGs to `docs/references/codex-computer-use-reverse-engineering/assets/extracted-2026-04-17/`, and added an asset index description.
- **[Doc Linking]**: Added direct links to the extracted assets in both the software cursor and permission onboarding docs, for easier future viewing and comparison.

### 🧠 Design Intent (Why)
Earlier analysis could already infer the existence of the software cursor and permission-arrow UI from strings and window behavior, but actually extracting the assets upgrades the conclusion from "credible by naming" to "an actual clickable, comparable visual asset in hand." This is very helpful for future open-source experience replication, since dimensions, reuse relationships, and rough visual direction can now be referenced directly.

### 📁 Files Modified
- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/references/codex-computer-use-reverse-engineering/assets/README.md`
- `docs/references/codex-computer-use-reverse-engineering/assets/extracted-2026-04-17/appicon-cursor-dark.png`
- `docs/references/codex-computer-use-reverse-engineering/assets/extracted-2026-04-17/appicon-cursor.png`
- `docs/references/codex-computer-use-reverse-engineering/assets/extracted-2026-04-17/hint-arrow.png`
- `docs/references/codex-computer-use-reverse-engineering/assets/extracted-2026-04-17/menubar-cursor.png`
- `docs/references/codex-computer-use-reverse-engineering/assets/extracted-2026-04-17/software-cursor-computeruse.png`
- `docs/references/codex-computer-use-reverse-engineering/assets/extracted-2026-04-17/software-cursor-slimcore.png`
- `docs/references/codex-computer-use-reverse-engineering/permission-onboarding.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md`
- `docs/histories/2026-04/20260417-1156-open-source-computer-use-research-foundation.md`

### Follow-up
- Change the links in `software-cursor-overlay.md` and `permission-onboarding.md` that point to exported PNGs via absolute local paths to repo-relative paths, so the docs don't depend on the author's machine directory structure.

## [2026-04-17 12:32] | Task: Analyze implementation clues for the yellow virtual mouse overlay

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> The tool calls are sufficient now. I noticed that in actual use, codex computer use shows a little yellow mouse cursor (probably a floating image — the experience is excellent, since it doesn't steal the user's mouse while still simulating a mouse animation) — can you detect and analyze this?

### 🛠 Changes Overview
**Scope:** `docs/`

**Key Actions:**
- **[Resource Evidence]**: Further checked `Codex Computer Use.app`'s `Assets.car` and strings, confirming resource names like `cursor`, `cursor dark`, and `menubar-cursor` exist in the main app, along with implementation clues like `cursorWindow`, `imageView`, and `Start Bezier cursor animation`.
- **[Runtime Probe]**: Directly enumerated runtime windows with `CGWindowListCopyWindowInfo`, confirming an independent window literally named `Software Cursor` exists under the `Codex Computer Use` process.
- **[Behavior Check]**: Compared the `Software Cursor` window's coordinates before and after a safe Finder click, confirming it moves along with tool actions rather than being a static resource or menu-bar decoration.
- **[Docs Index]**: Added a dedicated doc converging facts and inferences about the yellow virtual mouse overlay, and updated the reverse-engineering material index.

### 🧠 Design Intent (Why)
This little yellow mouse is a very important product detail in the official experience. Converging it from "feels like a floating image" to "an independent `Software Cursor` window held by `SkyComputerUseService`" lets a future open-source implementation more clearly split input injection and visual feedback into two separate mechanisms, rather than mistakenly assuming it has to directly manipulate the real system cursor.

### 📁 Files Modified
- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md`
- `docs/histories/2026-04/20260417-1156-open-source-computer-use-research-foundation.md`

## [2026-04-17 12:21] | Task: Add real-world computer-use tool call samples

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Have you tried calling all the tools yet? Ideally each one gets called a few times (e.g. against different apps or actions), say 3 times, and then save the call requests and response results to some directory under docs, for future reference.

### 🛠 Changes Overview
**Scope:** `docs/`

**Key Actions:**
- **[Live Samples]**: Ran live tests against `computer-use`'s 9 public tools, aiming to keep at least 3 samples per tool.
- **[Request/Response Archive]**: Added a dedicated samples doc, archiving request / response code blocks per tool, with notes on screenshot omission and response excerpting strategy.
- **[Boundary Notes]**: Additionally recorded `get_app_state`'s `appNotFound` and safety-denial boundary response types, and a no-op-leaning sample for `drag`.
- **[Docs Index]**: Updated the reverse-engineering material index to include this live-test doc in the current doc list.

### 🧠 Design Intent (Why)
Knowing the tool schema alone isn't enough; building an actual compatibility layer also requires knowing whether the runtime response is "a pure state snapshot" or "just returns OK," as well as stability differences across tools. With real request / response samples now in the repo, future implementation and regression verification can use this doc directly as a baseline, without repeated manual probing.

### 📁 Files Modified
- `docs/references/codex-computer-use-reverse-engineering/README.md`
- `docs/references/codex-computer-use-reverse-engineering/tool-call-samples-2026-04-17.md`
- `docs/histories/2026-04/20260417-1156-open-source-computer-use-research-foundation.md`

## [2026-04-17 12:51] | Task: Clean up one-off probe scripts and the temporary Python/uv setup

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex CLI`

### 📥 User Query
> Help me clean up this one-off script and its supporting bits — looks like `uv` got initialized for it too, don't need that either, this isn't a python repo.

### 🛠 Changes Overview
**Scope:** `scripts/`, `docs/`

**Key Actions:**
- **[Probe Cleanup]**: Deleted the one-off Node / Python `stdio` probe scripts, no longer keeping them as long-term repo assets.
- **[Python Chain Removal]**: Removed the `uv` project scaffold and Python dependency files that were temporarily introduced for this experiment.
- **[Docs Reframe]**: Reworded the relevant statements in the reverse-engineering docs and execution plan to "historical experiment conclusions," no longer implying the repo currently maintains a Python / `uv` entry point.
- **[History Sync]**: Recorded this cleanup in the same history file, preserving the research trail while removing the one-off implementation residue.

### 🧠 Design Intent (Why)
These scripts and the `uv` initialization only served a one-off minimal reproduction experiment and aren't part of the repo's long-term scope. Leaving the evidence in the docs while removing the temporary runtime chain from the repo avoids future readers mistakenly thinking this is a multi-language repo that needs a maintained Python environment.

### 📁 Files Modified
- `scripts/probe-cua-stdio.js`
- `scripts/probe_cua_mcp_python.py`
- `pyproject.toml`
- `uv.lock`
- `docs/exec-plans/active/20260417-open-source-computer-use-reverse-engineering.md`
- `docs/references/codex-computer-use-reverse-engineering/runtime-and-host-dependencies.md`
- `docs/histories/2026-04/20260417-1156-open-source-computer-use-research-foundation.md`
