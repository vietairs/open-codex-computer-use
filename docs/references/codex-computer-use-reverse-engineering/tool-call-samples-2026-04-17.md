# Computer Use Tool Call Samples (2026-04-17)

This document records real-world test samples taken on 2026-04-17, in the current Codex session, against the `computer-use` MCP's 9 public tools.

## Recording Method

- Sample source: real MCP call results from within the current session.
- Goal: preserve an in-repo reference for later open-source compatibility-layer implementation, showing roughly "what a request looks like, what a response looks like."
- Text strategy: preserve the original response format as much as possible; for especially long accessibility trees, keep only the prefix and key changed fragments.
- Screenshot strategy: calls like `get_app_state`, `click`, `scroll`, and `drag` all attach a screenshot in the tool UI; this document keeps only the text response, without embedding screenshots.
- Test apps: `Finder`, `Activity Monitor`, `System Settings`.
- Safety boundary: only low-risk actions were selected — directory selection, search-box input, scrolling, splitter dragging — with no system permission toggles switched and no double-clicking to open files.
- Re-checked later on 2026-04-17 and confirmed: when looking directly at the MCP tool's `content[0].text`, the official text starts with `App=...`; the earlier-preserved `Computer Use state (CUA App Version: 750)` / `<app_state>` wrapper noted here should no longer be treated as the current official baseline.

## `list_apps`

### Sample 1

Request

```json
{}
```

Response excerpt

```text
[{"type":"text","text":"Google Chrome — com.google.Chrome [running, last-used=2026-04-17, uses=20980]
PyCharm — com.jetbrains.pycharm [running, last-used=2026-04-17, uses=3444]
iTerm2 — com.googlecode.iterm2 [running, last-used=2026-04-17, uses=3178]
Sublime Text — com.sublimetext.4 [running, last-used=2026-04-17, uses=2023]
ChatGPT — com.openai.chat [running, last-used=2026-04-17, uses=661]
Finder — com.apple.finder [running, last-used=2026-04-17, uses=366]
...
Obsidian — md.obsidian [last-used=2026-04-08, uses=8]"}]
```

### Sample 2

Request

```json
{}
```

Response excerpt

```text
[{"type":"text","text":"Google Chrome — com.google.Chrome [running, last-used=2026-04-17, uses=20983]
PyCharm — com.jetbrains.pycharm [running, last-used=2026-04-17, uses=3447]
iTerm2 — com.googlecode.iterm2 [running, last-used=2026-04-17, uses=3179]
...
Obsidian — md.obsidian [last-used=2026-04-08, uses=8]"}]
```

### Sample 3

Request

```json
{}
```

Response excerpt

```text
[{"type":"text","text":"Google Chrome — com.google.Chrome [running, last-used=2026-04-17, uses=20983]
PyCharm — com.jetbrains.pycharm [running, last-used=2026-04-17, uses=3447]
iTerm2 — com.googlecode.iterm2 [running, last-used=2026-04-17, uses=3179]
...
Obsidian — md.obsidian [last-used=2026-04-08, uses=8]"}]
```

Observed response shape:

```text
- The outer layer is a content array.
- Currently only one text block is returned.
- Inside the text block is multi-line plain text, each line roughly formatted as:
  App Name — bundle.id [running, last-used=YYYY-MM-DD, uses=N]
```

## `get_app_state`

### Sample 1

Request

```json
{
  "app": "Finder"
}
```

Response excerpt

```text
App=com.apple.finder (pid 1106)
Window: "open-codex-computer-use", App: Finder.
    0 standard window open-codex-computer-use, ID: FinderWindow, Secondary Actions: Raise
        1 split group
            2 scroll area
                3 outline sidebar
                    4 row (selectable, expanded) Value: Favorites, Secondary Actions: Collapse
                    ...
            25 scroll area
                26 outline Description: list view, ID: ListView
                    68 row (selectable, collapsed) Secondary Actions: Expand
                    119 row (selectable, collapsed) Secondary Actions: Expand
                    130 row (selected)
...
```

### Sample 2

Request

```json
{
  "app": "Activity Monitor"
}
```

Response excerpt

```text
App=com.apple.ActivityMonitor (pid 988)
Window: "Activity Monitor", App: Activity Monitor.
    0 standard window Activity Monitor – All Processes, Secondary Actions: Raise
        1 scroll area Secondary Actions: Scroll Left, Scroll Right, Scroll Up, Scroll Down
            2 outline Processes
                3 row (selectable) OrbStack Helper
                4 row (selectable) iTerm2
                ...
        36 toolbar
            41 Description: Categories, Help: Display processes in the category specified
                42 radio button Description: CPU, Value: 1
                43 radio button Description: Memory, Value: 0
            47 search text field (settable, string)
                48 button search
...
The focused UI element is 2 outline.
```

### Sample 3

Request

```json
{
  "app": "System Settings"
}
```

Response excerpt

```text
App=com.apple.systempreferences (pid 73431)
Window: "Screen & System Audio Recording", App: System Settings.
    0 standard window Screen & System Audio Recording, ID: main, Secondary Actions: Raise
        1 split group main, SidebarNavigationView
            2 container
                3 search text field (settable, string)
                5 scroll area Secondary Actions: Scroll Up, Scroll Down
                    6 list Sidebar
                        34 row (selected) Privacy & Security
            53 scroll area Secondary Actions: Cancel
                54 heading Screen & System Audio Recording
                ...
                    63 row (selectable) Codex Computer Use
                        64 switch Value: on, ID: Codex Computer Use_Toggle
...
```

Additional boundary sample:

Request

```json
{
  "app": "iTerm2"
}
```

Response

```text
[{"type":"text","text":"appNotFound(\"iTerm2\")"}]
```

Request

```json
{
  "app": "com.googlecode.iterm2"
}
```

Response

```text
[{"type":"text","text":"Computer Use is not allowed to use the app 'com.googlecode.iterm2' for safety reasons."}]
```

## `click`

### Sample 1

Request

```json
{
  "app": "Finder",
  "element_index": "68"
}
```

Response excerpt

```text
68 row (selected, collapsed) Secondary Actions: Expand
    69 cell (selected)
        71 text field (selected, settable, string) ... Value: docs
...
164 list path
    165 text ... Value: Macintosh HD Users leo projects github open-codex-computer-use docs
```

### Sample 2

Request

```json
{
  "app": "Finder",
  "element_index": "119"
}
```

Response excerpt

```text
119 row (selected, collapsed) Secondary Actions: Expand
    120 cell (selected)
        122 text field (selected, settable, string) ... Value: scripts
...
164 list path
    165 text ... Value: Macintosh HD Users leo projects github open-codex-computer-use scripts
```

### Sample 3

Request

```json
{
  "app": "Activity Monitor",
  "element_index": "43"
}
```

Response excerpt

```text
34 Description: Categories, Help: Display processes in the category specified
    35 radio button Description: CPU, Value: 0
    36 radio button Description: Memory, Value: 1
    37 radio button Description: Energy, Value: 0
...
The focused UI element is 2 outline.
```

## `perform_secondary_action`

### Sample 1

Request

```json
{
  "app": "Finder",
  "element_index": "68",
  "action": "Expand"
}
```

Response excerpt

```text
68 row (selectable, expanded) Secondary Actions: Collapse
    69 cell
        71 text field ... Value: docs
        72 disclosure triangle 1
79 row (selectable)
80 row (selectable)
81 row (selectable, collapsed) Secondary Actions: Expand
...
```

### Sample 2

Request

```json
{
  "app": "Finder",
  "element_index": "68",
  "action": "Collapse"
}
```

Response excerpt

```text
68 row (selectable, collapsed) Secondary Actions: Expand
    69 cell
        71 text field ... Value: docs
        72 disclosure triangle 0
```

### Sample 3

Request

```json
{
  "app": "Activity Monitor",
  "element_index": "0",
  "action": "Raise"
}
```

Response excerpt

```text
0 standard window Activity Monitor – All Processes, Secondary Actions: Raise
...
The focused UI element is 2 outline.
```

This sample illustrates:

```text
Some secondary actions genuinely change UI state (Expand / Collapse).
There's also a class that's more like a window-level command (Raise), where the response text may barely change.
```

## `scroll`

### Sample 1

Request

```json
{
  "app": "Activity Monitor",
  "element_index": "1",
  "direction": "down",
  "pages": 1
}
```

Response excerpt

```text
1 scroll area Secondary Actions: Scroll Up, Scroll Down
    2 outline Processes
        3 row (selectable) coreservicesd
        4 row (selectable) corebrightnessd
        ...
25 scroll bar (settable, float) 0.1371493880660984
    26 value indicator (settable, float) 0.1371493880660984
```

### Sample 2

Request

```json
{
  "app": "Activity Monitor",
  "element_index": "1",
  "direction": "up",
  "pages": 1
}
```

Response excerpt

```text
1 scroll area Secondary Actions: Scroll Up, Scroll Down
    2 outline Processes
        3 row (selectable) OrbStack Helper
        4 row (selectable) iTerm2
        ...
22 scroll bar (settable, float) 0
    23 value indicator (settable, float) 0
```

### Sample 3

Request

```json
{
  "app": "System Settings",
  "element_index": "5",
  "direction": "down",
  "pages": 1
}
```

Response excerpt

```text
5 scroll area Secondary Actions: Scroll Up, Scroll Down
    6 list Sidebar
        17 row (selectable) General
        18 row (selectable) Accessibility
        ...
        45 row (selectable) Printers & Scanners
46 scroll bar (settable, float) 0.9999999999999994
    47 value indicator (settable, float) 0.9999999999999994
```

## `set_value`

### Sample 1

Request

```json
{
  "app": "Activity Monitor",
  "element_index": "40",
  "value": "codex"
}
```

Response excerpt

```text
3 row (selectable) codex
...
14 row (selectable) Codex Computer Use
...
38 search text field (settable, string) codex
    39 button search
    40 button cancel
```

### Sample 2

Request

```json
{
  "app": "System Settings",
  "element_index": "3",
  "value": "privacy"
}
```

Response excerpt

```text
Window: "Apple Account", App: System Settings.
...
3 search text field (settable, string) privacy
    4 button Search
    5 button cancel
6 scroll area Secondary Actions: Scroll Up, Scroll Down
    7 list Sidebar
        9 row (selectable) Privacy & Security
        10 row (selectable) Allow applications to access Bluetooth
        ...
```

### Sample 3

Request

```json
{
  "app": "System Settings",
  "element_index": "3",
  "value": "screen"
}
```

Response excerpt

```text
Window: "Privacy & Security", App: System Settings.
...
3 search text field (settable, string) screen
    4 button Search
    5 button cancel
...
57 row (selectable) Privacy & Security
58 row (selectable) Allow applications to access the contents of your screen and audio through Remote Desktop
59 row (selectable) Allow applications to record your screen
```

## `press_key`

### Sample 1

Request

```json
{
  "app": "Activity Monitor",
  "key": "super+a"
}
```

Response excerpt

```text
38 search text field (settable, string) codex
...
Selected text: [codex]
```

### Sample 2

Request

```json
{
  "app": "Activity Monitor",
  "key": "super+a"
}
```

Response excerpt

```text
38 search text field (settable, string) Codex
...
Selected text: [Codex]
```

### Sample 3

Request

```json
{
  "app": "Activity Monitor",
  "key": "super+a"
}
```

Response excerpt

```text
27 search text field (settable, string) Computer Use
...
Selected text: [Computer Use]
```

## `type_text`

### Sample 1

Request

```json
{
  "app": "Activity Monitor",
  "text": "Codex"
}
```

Response excerpt

```text
38 search text field (settable, string) Codex
...
The focused UI element is 38 search text field.
```

### Sample 2

Request

```json
{
  "app": "Activity Monitor",
  "text": "Computer Use"
}
```

Response excerpt

```text
3 row (selectable) Codex Computer Use
...
27 search text field (settable, string) Computer Use
    28 button search
    29 button cancel
```

### Sample 3

Request

```json
{
  "app": "Activity Monitor",
  "text": "Helper"
}
```

Response excerpt

```text
2 outline Processes (showing 0-19 of 161 items)
    3 row (selectable) OrbStack Helper
    4 row (selectable) Figma Helper (Renderer)
    5 row (selectable) Figma Helper (GPU)
    ...
38 search text field (settable, string) Helper
```

## `drag`

### Sample 1

Request

```json
{
  "app": "Finder",
  "from_x": 158,
  "from_y": 373,
  "to_x": 220,
  "to_y": 373
}
```

Response excerpt

```text
24 splitter (disabled, settable, float) 185
...
170 pop up button Description: list view, Value: as List
```

In this sample, `Finder`'s left sidebar was widened, and the splitter's float value changed from `133` to `185`.

### Sample 2

Request

```json
{
  "app": "Finder",
  "from_x": 220,
  "from_y": 373,
  "to_x": 158,
  "to_y": 373
}
```

Response excerpt

```text
24 splitter (disabled, settable, float) 133
...
171 radio button Description: icon view, Value: 0
172 radio button Description: list view, Value: 1
```

### Sample 3

Request

```json
{
  "app": "System Settings",
  "from_x": 231,
  "from_y": 466,
  "to_x": 260,
  "to_y": 466
}
```

Response excerpt

```text
83 splitter (disabled, settable, float) 215
...
57 row (selected) Privacy & Security
```

This sample returned normally, but the text shows no noticeable change in the split value, indicating pure-coordinate dragging is fairly sensitive to the starting point's positioning.

Additional sample tending toward a no-op:

Request

```json
{
  "app": "Activity Monitor",
  "from_x": 1145,
  "from_y": 111,
  "to_x": 1145,
  "to_y": 262
}
```

Response excerpt

```text
22 scroll bar (settable, float) 0
    23 value indicator (settable, float) 0
...
38 search text field (settable, string) Helper
```

## Summary

A few stable conclusions can already be drawn from this round of testing:

```text
1. `list_apps` is a pure text enumeration interface, the simplest one.
2. `get_app_state` is the core of the whole interface surface, returning element index, attributes, secondary actions, and a screenshot.
3. Most interactive tools return "the latest full or near-full UI state" again in the response, rather than just returning `ok`.
4. `set_value` is more semantic than `type_text`, suited for writing directly to a search/text field.
5. `press_key`'s response carries `Selected text`, which is valuable for judging focus and selection.
6. `drag` only has coordinate mode, no `element_index`, so its stability depends most heavily on picking screenshot coordinates.
7. App-name resolution has boundaries: a human-readable name won't necessarily match directly, and a bundle id may also be rejected by safety policy.
```
