# Render AXLink as a Markdown link

## User Ask

Continue optimizing complex app-state output using clues from reverse-engineering the official `computer-use`, especially the AX-tree output shape for Lark / Electron and browser scenarios.

## Main Changes

- Generate Markdown-style `[label](url)` text for `AXLink` elements that have an `AXURL`.
- Fix the `AXLink` role text to the English word `link`, so it isn't affected by system language into a localized role string.
- Suppress duplicate description / child text for links that have already been converted to Markdown.
- Links without a URL still keep their description as an ordinary link node.

## Design Intent

The `SkyComputerUseService` 1.0.770 binary contains a `flattenLinksIntoMarkdownText` transform. Live testing in Lark / Chrome also shows the official app prefers folding link semantics into readable text, rather than emitting a localized `链接 Description: ...` (`链接` = "link") structure. This change puts the link target URL more directly into the state, while still keeping the element record for later clicks.

## Verification

- Local Lark regression confirms links change from `链接 Description: ...` (`链接` = "link") to Markdown link text.
- Local Chrome regression confirms links with a URL render as Markdown, while links without a URL still keep the plain `link Description`.
- `swift test --filter AccessibilityRenderer`
- `./scripts/build-open-computer-use-app.sh debug`

## Files Affected

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AccessibilitySnapshot.swift`
