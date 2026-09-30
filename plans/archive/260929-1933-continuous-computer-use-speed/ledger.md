# Ledger: continuous computer-use speed

Task: "agents still think then call the MCP once per mouse action; with JEV speed actions should be continuous — improve it", plus Track B: "use faster ways than screenshots to drive macOS apps, like AppleScript".

Shipped:
- Track A — PR #23, merge 86b00bb: perform_actions batching, text-only action results, lower per-call latency.
- Track B — PR #25, squash 67f5d42: always-on find_elements (breadth-first AX search, ratio 0.023 vs get_app_state on Mail); opt-in OPEN_COMPUTER_USE_ENABLE_SCRIPTING=1 for run_script, get_scripting_dictionary, open_url, list_shortcuts, run_shortcut via LocalChannelRouter in the MCP process.

Key deviations:
- Depth-first walk failed the 0.50 ratio target (0.985); switched to breadth-first (pre-approved lever).
- Advisor cascade guide moved into decide_next_action's description to keep server instructions under 2048 chars.
- run_script latency target accepted as Mail-bound (channel overhead ~0ms).
- Review rounds found an sdef billion-laughs bypass (parameter entities, then UTF-7/EBCDIC declarations); fixed with a DOCTYPE stripper plus an encoding allowlist.

Learnings:
- Byte scanners over XML are bypassable through libxml2's declared-encoding path; allowlist encodings first.
- CI's Swift compiler times out on mixed-width integer ternaries that the local toolchain accepts; split into typed locals.
- New MCP tools reach live agents only after an npm release (0.3.10-vietairs.1).

Not archived: reports/track-b/ship-gate-diff-fast-macos-channels.txt (reproducible via git diff 1b14cb8..5f1c25d).

Archived-at-SHA: 67f5d42cda37d275e87dacae8376d9a8af749bcf
