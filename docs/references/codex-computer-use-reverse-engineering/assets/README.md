# Extracted Visual Assets

This directory holds visual assets extracted directly from the official `Codex Computer Use.app` bundle, used to support the visual-layer conclusions in the reverse-engineering docs.

## Current archive

- `official-bundles/computer-use/`
  - Official `computer-use` zip packages archived from the local bundled-plugin cache; currently includes `1.0.750.zip` and `1.0.755.zip`. Zips in this directory are tracked via Git LFS.
- `extracted-2026-04-17/hint-arrow.png`
  - The `HintArrow` asset exported from `Package_SlimCore.bundle`, size `57x66`.
- `extracted-2026-04-17/software-cursor-slimcore.png`
  - The `SoftwareCursor` asset exported from `Package_SlimCore.bundle`, size `200x230`.
- `extracted-2026-04-17/software-cursor-computeruse.png`
  - The `SoftwareCursor` asset exported from `Package_ComputerUse.bundle`, size `200x230`; binary-identical to the `SlimCore` version.
- `extracted-2026-04-17/appicon-cursor.png`
  - `CUAAppIcon_Assets/cursor` exported from the main app's `Assets.car`, size `1024x1024`.
- `extracted-2026-04-17/appicon-cursor-dark.png`
  - `CUAAppIcon_Assets/cursor dark` exported from the main app's `Assets.car`, size `1024x1024`.
- `extracted-2026-04-17/menubar-cursor.png`
  - `menubar-cursor` exported from the main app bundle, size `19x17`.

## Notes

- `official-bundles/` keeps the raw zip artifacts, useful for version diffing, asset extraction, and later reproduction; do not wire it into the default build pipeline.
- These files are not screenshots — they are loaded directly from bundle resources and re-saved as PNGs.
- The current export approach is based on AppKit's `Bundle.image(forResource:)`, which suits already-named assets.
- Most of the permission-onboarding UI still looks more like SwiftUI / window-composition logic than a large set of static images, so the "permission visual assets" that can currently be exported are mainly `HintArrow`.
