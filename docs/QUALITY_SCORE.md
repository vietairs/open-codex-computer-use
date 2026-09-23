# Quality Score

## Scoring Criteria

- `A`: Full coverage, stable behavior, clear documentation, low operational risk.
- `B`: Generally acceptable, but with clear gaps.
- `C`: Usable, but needs targeted hardening.
- `D`: Fragile, lacking conventions, or many behaviors still undefined.

## Current State

| Area | Score | Reason | Next Step |
| --- | --- | --- | --- |
| Product surface | B | There is already a native Swift `computer-use` MCP server, default app-mode permission onboarding, and a set of 9 tools converged against official surface/result behavior. | Continue converging state-rendering details for complex AX scenarios, permission UI, and clearer user error messages. |
| Windows runtime | C | A separate Go `.exe` has been added, exposing the same 9 tools, MCP server, and `call --calls` via Windows UI Automation + Win32 window messages; by default it no longer auto-launches the app, performs `SetFocus`, or lets `type_text` fall back to the UIA text path that may steal foreground focus, and it is now wired into npm bundled artifact distribution, but it is still a functional first version. | Add interactive desktop smoke tests, Windows fixtures, installer/signing, and a more native Go UIA implementation or a more stable bridge. |
| Linux runtime | C | A separate Go binary has been added, exposing the same 9 tools, MCP server, and `call --calls` via Python GI / AT-SPI2; on an Ubuntu GNOME VM, `list_apps`, the MCP tools list, and the Text Editor 8-tool sequence all run successfully, and it is now wired into npm bundled artifact distribution, but screenshots under GNOME Wayland remain best-effort only, and coordinate input is not a universal background model. | Add Linux fixtures, a repeatable smoke runner, a portal/compositor screenshot path, and a more native Go D-Bus/libatspi bridge. |
| Architecture docs | B | The top-level structure, fixture bridge, app mode, and verification path are already documented. | Still need to document release artifacts, code signing/notarization, and host integration methods. |
| Testing | B | `swift test` + the smoke suite cover regressions for the 9 tools, and a manual comparison sample set for "was foreground focus stolen" has been added and preserved. | Add more recorded regressions against ordinary apps, reducing reliance on fixtures and one-off manual checks alone. |
| Observability | C | There is already `doctor`, `snapshot`, smoke output, and a set of archived comparison samples between the official `computer-use` and this repo's implementation. | Add unified log levels, failure context, and diagnostic information in release artifacts; converge one-off samples into a repeatable collection process. |
| Security | B | Local-only scope, permission boundaries, and the fixture test bridge's scope are already clearly defined, and the built-in denylist has been narrowed to password managers. | Add session approval and a clearer sensitive-app policy, avoiding policy staying hardcoded in the repo long-term. |
