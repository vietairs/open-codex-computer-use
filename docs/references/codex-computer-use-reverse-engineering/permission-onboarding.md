# Permission Onboarding

This document focuses on Codex Computer Use's system permission onboarding experience, especially two types of permission:

- `Accessibility`
- `Screen & System Audio Recording`

and one more specific question: does it really build a custom window that guides the user to drag `Codex Computer Use.app` directly into the authorization area, rather than just dropping the user into System Settings to figure it out themselves.

The conclusion up front: the current evidence is already enough to confirm the official implementation is not just "detect permissions, then open System Settings." It has a built-in permission state machine and a dedicated `SystemSettingsAccessoryWindow` guidance UI; the "you can drag the app straight in" experience you're seeing is highly consistent with the `DraggableApplicationView`, `dragDelegate`, `ArrowWindow`, and `TransitionOverlayWindow` names that appear in the binary.

## Observed Facts

### 1. Permission gating is a first-class capability inside the service

`SkyComputerUseService` strings show:

```text
ComputerUseIPCPermissionResult
ComputerUseIPCRequestRequiringSystemPermissions
ensureApplicationHasPermissions
Failed to request access to permission: %@
Failed to open System Settings for permission: %@
```

This shows permissions aren't a casual outer-layer precheck, but are folded into the internal request pipeline.

### 2. The official implementation explicitly tracks two core permission types

The same set of strings also shows:

```text
accessibility
screenRecording
screen_recording
AccessibilityPermission
TCCDialogSystemPermission
Privacy_Accessibility
Privacy_ScreenCapture
```

Combined with the `Screen & System Audio Recording` page already observed in an earlier real `System Settings` sample, this confirms the official implementation explicitly does permission gating and system-settings navigation around at least:

- Accessibility
- Screen Recording / Screen & System Audio Recording

### 3. The user-facing copy is itself a permission-guidance flow, not just a system dialog

`SkyComputerUseService` shows a continuous set of guidance copy:

```text
Codex Computer Use needs these permissions to use apps on your Mac.
These permissions are only used when you ask Codex to perform tasks.
Allows Codex to access app interfaces
Codex uses screenshots to know where to click
COMPLETE IN SYSTEM SETTINGS
```

This shows the main app has its own layer of permission-explanation UI.

### 4. A separate permission-window state and its callbacks exist

The strings also show:

```text
permissionState
permissionsWindow
permissionsPending
permissionsNotGranted
onGrantAccessibility
onGrantScreenRecording
onOpenAccessibilitySettings
onOpenScreenRecordingSettings
```

This set of names is no longer just "go open some system page" — it shows there's internally:

- A permission window object
- A permission state machine
- Per-permission-type grant/open callbacks

### 5. `SlimCore` has a dedicated System Settings guidance window system

The currently available strings evidence directly shows:

```text
SystemSettingsAccessCoordinator
SystemSettingsAccessoryWindow
SystemSettingsAccessoryWindowView
SystemSettingsAccessoryWindowDragDelegate
SystemSettingsAccessoryTransitionOverlayWindow
SystemSettingsAccessoryTransitionOverlayReplicantWindow
SystemSettingsAccessoryTransitionBackground
ArrowWindow
```

This shows the official implementation isn't simply `open x-apple.systempreferences:` and done — it's built a whole set of accessory / overlay / transition UI around System Settings.

### 6. The "drag the app in" experience has direct naming evidence

The most critical set of names is:

```text
SystemSettingsAccessoryWindowView.DraggableApplicationView
dragDelegate
dragContinuation
draggable
ArrowWindow
```

The name `DraggableApplicationView` here pretty much spells out the implementation intent on its own:

- It shows a "draggable application view"
- It's paired with a drag delegate
- There's also an arrow window pointing the user toward the target area

This is highly consistent with what you observed: "inside the window you can directly drag `Codex Computer Use.app` in, without needing to go find the app yourself."

A hint-arrow asset strongly tied to this guidance flow can currently be extracted directly from `Package_SlimCore.bundle`:

- [hint-arrow.png](assets/extracted-2026-04-17/hint-arrow.png)

Its corresponding asset name is `HintArrow`, sized `57x66`, which lines up very well with the `ArrowWindow` / `SystemSettingsAccessoryWindow` naming group.

## Current Inferences

### 1. The permission flow is most likely split into two layers

The most reasonable structure right now is:

- `SkyComputerUseService`
  - Checks permission state
  - Decides which permission is currently missing
  - Opens the corresponding System Settings page
  - Manages the permission window's lifecycle
- `SlimCore`
  - Provides the concrete accessory window / overlay / drag UI
  - Uses arrows, transition overlays, and the draggable app view to guide the user through the last step in System Settings

### 2. The drag window you're seeing looks more like an official custom guidance shell, not the system's native default UI

The reasoning is direct:

- System Settings itself doesn't expose a name like `DraggableApplicationView` to third-party apps.
- `ArrowWindow`, `TransitionOverlayWindow`, and `permissionsWindow` are all internal symbols belonging to the official bundle.
- The copy `COMPLETE IN SYSTEM SETTINGS` suggests "this app explains first, then hands the last step off to System Settings."

So the more reasonable explanation is:

- Real authorization still ultimately happens inside macOS's TCC / System Settings;
- But the official app layers an auxiliary window on top, reducing the cost of the user finding the entry point, finding the app, and finding the drag target themselves.

### 3. The evidence for drag guidance is stronger for Accessibility than for Screen Recording

Semantically speaking:

- The `Accessibility` page is inherently a better fit for a "drag the app into the allow list" interaction.
- `Screen Recording` / `Screen & System Audio Recording` more commonly involves toggling an entry or confirming a relaunch of the app.

So the stronger inference right now is:

- The `DraggableApplicationView` interaction serves at least Accessibility authorization;
- Whether it's also used identically for Screen Recording still needs additional dynamic observation to confirm with full certainty.

## Why This Experience Matters

This shows that, at the product level, the official implementation isn't content with "just kick the user to System Settings and let them figure it out." It specifically added a layer of:

- Permission explanation
- Precise page navigation
- Drag guidance
- State convergence after returning to the app

For an open-source implementation, this point matters a lot, because it directly affects first-round authorization success rate and user frustration.

## Points Not Yet Fully Confirmed

- No live runtime screenshot of the permission onboarding window has been captured yet, because permissions are already granted on this machine at this time.
- Whether `DraggableApplicationView` is used only for Accessibility, or also participates in Screen Recording guidance, remains an inference for now.
- The concrete visual assets for this permission UI haven't yet been fully extracted from `Assets.car`.

## Implications For The Open-Source Implementation

- Don't just do "if the check fails, tell the user to go to System Settings manually."
- The permission flow should be modeled as its own state machine, rather than scattered across tool-call failure branches.
- It's best to provide an auxiliary window targeted at the specific system page, especially for a multi-step, deep-path authorization flow like Accessibility.
- Splitting "open System Settings" apart from "how the last step gets completed" as separate design concerns gives a much better experience than plain text prompts alone.
