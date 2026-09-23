# Tech Debt Tracker

This records tech debt that doesn't currently block work, but is worth keeping on record.

| Date | Area | Debt Description | Why It Exists | Planned Follow-up |
| --- | --- | --- | --- | --- |
| 2026-04-17 | Generic app AX snapshot | The Finder path can already get the foreground window's subtree and output a window-relative frame, but more real-app regression samples are still needed to prove this rooting/traversal is stable across complex apps. | This round focused on converging coordinate conversion and window subtree handling for real apps like Finder first, leaving deterministic regression coverage to fixtures for later. | Add real-app samples such as Safari / System Settings / Activity Monitor for verification, and keep converging `kAXMainWindowAttribute`, the focused-element parent chain, and multi-window fallback strategy. |
