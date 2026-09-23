# Background Click Free Tooling Workflow

This document records a methodology for using free tools instead of IDA Pro to research the official bundled `computer-use`'s background-click path. It's not meant to commit a one-off Ghidra project, large disassembly files, or a temporary Swift prototype into the repository — it's meant to let future developers or AI regenerate the local research directory by following the same steps.

## When to Use This

When you need to research the official closed-source `Codex Computer Use.app`'s mouse click, background window delivery, `CGEvent` fields, or AppKit / AX interaction paths, prefer creating a new local `research/<topic>-<date>/` directory following this document. The repository-level `.gitignore` already ignores `research/`, avoiding bringing large binary analysis artifacts into commits.

## Toolchain

Free tool combo:

```bash
brew install ghidra radare2
python3 -m pip install --user frida-tools lief capstone
```

Common system tools:

```bash
xcrun -f otool
xcrun -f nm
xcrun -f swift-demangle
xcrun -f llvm-objdump
codesign --help
```

If Ghidra headless can't find Java, set it explicitly:

```bash
export JAVA_HOME="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"
```

The Ghidra headless entry point is usually:

```bash
"$(brew --prefix ghidra)/libexec/support/analyzeHeadless"
```

## Locating the Target

By default, take the target binary from the bundled plugin. Don't write machine-specific absolute paths into the docs; build them from environment variables at runtime:

```bash
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
APP="$CODEX_HOME/plugins/cache/openai-bundled/computer-use/1.0.755/Codex Computer Use.app"
SERVICE="$APP/Contents/MacOS/SkyComputerUseService"
CLIENT="$APP/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"
```

First confirm the bundle, signature, and Mach-O type:

```bash
file "$SERVICE" "$CLIENT"
codesign -dv --verbose=4 "$APP" > raw/codesign-service-app.txt 2>&1
codesign -dv --verbose=4 "$APP/Contents/SharedSupport/SkyComputerUseClient.app" > raw/codesign-client-app.txt 2>&1
```

## Static Information Collection

It's recommended to first drop the raw output into `research/<topic>/raw/`, to make it easy for AI to grep and reference later:

```bash
mkdir -p raw
nm -u "$SERVICE" > raw/nm-u-service.txt
nm -u "$CLIENT" > raw/nm-u-client.txt
otool -L "$SERVICE" > raw/otool-L-service.txt
otool -Iv "$SERVICE" > raw/otool-Iv-service.txt
rabin2 -I "$SERVICE" > raw/rabin2-I-service.txt
rabin2 -i "$SERVICE" > raw/rabin2-imports-service.txt
rabin2 -zz "$SERVICE" > raw/rabin2-strings-service.txt
strings "$SERVICE" | swift-demangle > raw/strings-demangled-service.txt
```

For the background-click direction, prioritize searching these keywords:

```bash
rg "mouseEventWithType|eventWithCGEvent|CGEvent|buttonNumber|clickCount|windowNumber|AXUIElement|CGWindowList|dlopen|dlsym" raw
```

High-value hits typically include:

- `mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:`
- `eventWithCGEvent:`
- `AXUIElementCopyElementAtPosition`
- `AXUIElementPerformAction`
- `AXUIElementSetAttributeValue`
- `CGWindowListCopyWindowInfo`
- `CGWindowListCreateDescriptionFromArray`
- `dlopen` / `dlsym`

## Ghidra Headless Export Strategy

Don't manually click through functions one by one in the GUI. Write a headless script that collects candidate functions by symbol name and string hits, then batch-decompiles them into `ghidra-service/`.

Recommended script capabilities:

- Take a list of keywords as input, e.g. `AXUIElement`, `CGWindowList`, `NSEvent`, `CGEvent`, `mouseEventWithType`, `windowNumber`.
- Walk the symbol table, defined strings, and references.
- Decompile matching functions into standalone `.c` files.
- Additionally support exporting by address, to make it easy to trace wrappers / resolvers further.

Run shape:

```bash
mkdir -p ghidra-project ghidra-service tools
"$(brew --prefix ghidra)/libexec/support/analyzeHeadless" \
  "$PWD/ghidra-project" ComputerUseService \
  -import "$SERVICE" \
  -scriptPath "$PWD/tools" \
  -postScript FocusExport.java "$PWD/ghidra-service"
```

If you already know the key addresses, export them with a separate script:

```bash
"$(brew --prefix ghidra)/libexec/support/analyzeHeadless" \
  "$PWD/ghidra-project" ComputerUseService \
  -process SkyComputerUseService \
  -scriptPath "$PWD/tools" \
  -postScript ExportAddresses.java "$PWD/ghidra-service/address-decompiled" \
  10050d404 100569a5c 1000ae328 1000ae398 1000b8830
```

## Core Determination for Background Clicks

The key path verified this round is as follows. Future AI regeneration of the code should prioritize this call shape:

1. Use `CGWindowListCopyWindowInfo` to find the target process's layer-0 window, bounds, and `CGWindowID`.
2. Use `NSEvent.mouseEvent(...)` to create down/up events, passing the target `CGWindowID` as `windowNumber`.
3. Extract the underlying `CGEvent` from `NSEvent.cgEvent`.
4. Set the fields:
   - field `3`: button number, i.e. the public `kCGMouseEventButtonNumber`
   - field `7`: observed value is `3`
   - field `91`: window under pointer
   - field `92`: event target window
5. Set the screen-space `CGEvent.location`.
6. Convert the screen point into a window-local point.
7. Call the private symbol `CGEventSetWindowLocation(event, localPoint)`.
8. Use `CGEvent.postToPid(pid)` to deliver it directly to the target process.

On an AppKit test target, `CGEventSetWindowLocation` is the key control: keeping it lets the background window receive `mouseDown/mouseUp`; skipping it means no new clicks arrive. Some background branch in the official binary sets flags to `0x100000`, but on a simple AppKit fixture it isn't a necessary condition for the event to arrive.

## Minimal Swift Reproduction Direction

When having AI generate a local prototype, it's recommended to build a Swift package with two executable targets:

- `BackgroundClickProbe`
  - Supports arguments `--pid`, `--bundle-id`, `--app`, `--window-id`, `--point`, `--dry-run`.
  - Resolves the private symbol using `dlsym(RTLD_DEFAULT, "CGEventSetWindowLocation")`.
  - Outputs JSON containing pid, window id, bounds, screen point, local point, flags, and whether it was a dry run.
- `EchoApp`
  - A minimal AppKit window.
  - Overrides `mouseDown` / `mouseUp`.
  - Prints to stdout and also writes to `/tmp/bgclick-echoapp.log`, to make it easy to verify via `open` or a background process.

The verification matrix should cover at least:

```bash
swift build
ECHOAPP_LOG=/tmp/bgclick-echoapp.log .build/debug/EchoApp
.build/debug/BackgroundClickProbe --app EchoApp
.build/debug/BackgroundClickProbe --app EchoApp --no-background-flag
.build/debug/BackgroundClickProbe --app EchoApp --skip-window-location
.build/debug/BackgroundClickProbe --app EchoApp --nsevent-location local
tail -n 20 /tmp/bgclick-echoapp.log
```

The expectation is that the target still receives `mouseDown` / `mouseUp` while `active=false`, `key=false`. If the default command fails, check first:

- Whether `AXIsProcessTrusted()` is true.
- Whether `dlsym` can resolve `CGEventSetWindowLocation`.
- Whether the `CGWindowID` comes from the target process's layer-0 on-screen window.
- Whether the `window-local` coordinate is computed as `screenPoint - windowBounds.origin`.
- Whether a global HID post was used by mistake instead of `postToPid`.

## What to Commit

Do not commit the following:

- One-off Ghidra projects under `research/`.
- Large `llvm-objdump` / `rabin2 -zz` / strings raw output.
- The `.build/` directory of the temporary Swift package.
- Binaries or large assets exported directly from the official bundle, unless explicitly placed under `docs/references/.../assets/` and paired with Git LFS rules.

The following can be committed:

- Cleaned-up conclusion documents.
- Small, general, reproducible Ghidra scripts or collection scripts.
- Open-source implementation code that has been productionized and merged into the main runtime / smoke suite.

## Known Limitations

- Ghidra pseudocode is not source code; Swift async, ObjC message sends, and dynamic resolver sites need to be judged jointly from call shape, strings, and runtime verification.
- `CGEventSetWindowLocation` is a private API, suitable only for research and local comparison, and should not be relied on directly as a release-product dependency.
- Behavior depends on the macOS version, TCC permissions, the target app's toolkit, and the signing/host environment.
