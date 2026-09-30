# PR #16 review: translation fidelity

Branch `docs/translate-to-english` (c9814e9) vs `origin/main` (4ac1d5e). Read-only review.

## Verdict

The translation is faithful overall. No section, list item, table row, number, version, date or command was lost or altered in the sample. I found 3 small meaning defects, 1 duplicated block, and several places where literal source/test strings were translated. That last point contradicts the PR's own "kept deliberate Chinese" rule. All fixes are single edits, and none blocks merging on its own. I recommend fixing B1–B3 and N1 before merge.

## Scope and method

- **Read in full, line-paired original vs translated:** ARCHITECTURE, SECURITY, RELIABILITY, REPO_COLLAB_GUIDE, feature-release-notes (every row), software-cursor-overlay, 20260418-1430-standalone-cursor-lab, DESIGN, FRONTEND, generated/README.
- **5 files of my choosing:** AGENTS.md, CLAUDE.md, CONTRIBUTING.md, references/macos-skylight-background-click.md, exec-plans/completed/20260723-preserve-sky-click-focus.md.
- **Also inspected**, because the scripted checks below flagged them: codex-computer-use-cli.md, permission-onboarding.md, runtime-and-host-dependencies.md, 20260420-1416, 20260922-1036, 20260922-0124, 20260507-2017, 20260512-1852, 20260507-1825, 20260417-1156.
- **Scripted checks over all 252 files:**
  - numbers multiset
  - inline-code multiset
  - line count
  - residual CJK
  - per-line length ratio (truncation detector: the minimum ratio is about 3.0 English chars per CJK char, so no truncated lines)
  - duplicated paragraphs

### Concurrent-write check

DESIGN.md, FRONTEND.md and generated/README.md are clean. Line-for-line they match the original: nothing truncated, duplicated or mixed.

## Blocking (meaning changed)

### B1. Wrong technical term: "compositing" instead of "synthetic"

`docs/exec-plans/completed/20260723-preserve-sky-click-focus.md:10`

- Original: `将 SkyLight activation session 从“前台 defocus + 目标 focus + 双向恢复”收敛为只改变目标应用合成状态。`
- Translated: `... down to changing only the target application's compositing state.`

Here 合成状态 means the synthetic-active (event-routing) state, not WindowServer compositing. SECURITY.md and macos-skylight-background-click.md both translate it correctly as "synthetic state" / "synthetic event-routing state".

Fix: `changing only the target application's synthetic-active state`.

### B2. A causal link that is not in the original

`docs/histories/2026-09/20260922-1036-h2-tree-line-offsets-invariant-test.md` ([Ordering assertion])

- Original: `所以逐行前缀检查在任何发射顺序下都通过，compact 本身也会再排一次升序。`
- Translated: `so the row-by-row prefix check passes under any emission order, since compact itself re-sorts ascending anyway.`

The original gives two independent facts. The translation says the prefix check passes *because* compact re-sorts, which is technically wrong: it passes because the offsets are self-consistent. The same bullet also has a broken sentence ("Review overturned a claim ... — that X — does not hold").

Fix: replace "since" with "; separately,". Rewrite the opening as: "Review overturned a claim from the first draft: that feeding elements in shuffled order would catch a missed sort."

### B3. Literals that match source and test code were translated

These contradict the PR's own policy of keeping "literal on-screen UI strings or test input quoted from real apps, each glossed in English". 20260507-1747 applies that policy correctly. These files do not:

- `docs/histories/2026-05/20260507-2017-avoid-counter-text-merge.md:10`
  - Original: `` `["消息", "126/126"]` ``
  - Translated: `` `["Messages", "126/126"]` ``
  - The real test at OpenComputerUseKitTests.swift:1752 is `shouldMergeTextOnlySiblings(["消息", "126/126"])`.
  - The same file, lines 14 and 18, turns `` `text 消息 126/126` `` / `` `text 消息` `` into `` `text Messages …` ``, which is not the output the renderer actually produced.
- `docs/histories/2026-05/20260507-1825-polish-accessibility-formatting.md:25`
  - Original: `` `HTML 内容 messenger-chat, URL: ...` ``
  - Translated: `` `HTML content messenger-chat, URL: ...` ``
  - The source literal at AccessibilitySnapshot.swift:2005 is `"HTML 内容"`.
- `docs/releases/feature-release-notes.md:51` (row 0.1.43)
  - Original: `` `HTML 内容` 区域 ``
  - Translated: `"HTML content" area`

Impact: anyone grepping the docs for the real string gets no hit, and the docs now describe output that never occurred.

Fix: restore the original literal and add a gloss, e.g. `` `["消息", "126/126"]` (`消息` = "Messages") ``.

## Nits

### N1. Duplicated block (content added)

`docs/histories/2026-04/20260420-1416-add-computer-use-cli-call-seq.md`

The `**Follow-up Files:**` block with its 2 bullets appears twice at the end. The original has it once. This is the only duplicated paragraph across all 252 files. Delete the second copy.

### N2. Wrong term: "windowed-server"

`docs/releases/feature-release-notes.md:7`

- Original: `真实窗口服务器拖拽`
- Translated: `real windowed-server drag`
- Should be: `real window-server drag`

### N3. Temporal claim added

`feature-release-notes.md:7`

- Original: `firstAnyWindow 回退不受 recoveryPolicy 限制`
- Translated: `is no longer gated by recoveryPolicy`

The original states a property. It does not say the behavior changed. Should be: `is not gated by`.

### N4. Generic term narrowed to a specific app

`feature-release-notes.md:71` (0.1.39)

- Original: `Chrome、终端、Atlas`, where 终端 means terminal apps in general.
- Translated: `Chrome, Terminal, Atlas`, which now names Apple's Terminal.app.

The same row also turns `仍保持内置阻止` ("still built-in blocked") into "still blocked by default". Compare ARCHITECTURE.md:70, which gets it right: "Terminal, … no longer built-in blocked targets". Should be: `terminal apps` and `built-in blocked`.

### N5. "signed" added

`docs/SECURITY.md` (peer-auth bullet)

- Original: `agent 非 bundle 运行时退化为仅 team pin`
- Translated: `When the agent itself is not running as a signed bundle`

The original says "not running as a bundle". ARCHITECTURE.md:51 translates the same clause correctly. Drop "signed".

### N6. Binary name lost

`docs/references/codex-computer-use-reverse-engineering/runtime-and-host-dependencies.md:37-38`

- Original: `` `node` 的 … `` / `` `python3` 的 … ``
- Translated: `Node's …` / `Python's …`

The exact binary (`python3`) matters in a launch-constraint note. Restore `` `node`'s `` / `` `python3`'s ``.

### N7. Group names and sent test messages translated without the original

`docs/histories/2026-05/20260512-1852-avoid-synthetic-row-side-action-clicks.md:44-48`

- `` `AgentSphere 双周会群` `` / `` `研发群` `` became `` `AgentSphere Biweekly Meeting Group` `` / `` `R&D Group` ``.
- The two joke messages that were actually sent were also translated inside code spans.

In the same file, person names keep the Chinese with a gloss. Apply the same keep-and-gloss treatment to the group names and messages.

### N8. PR body undercounts residual CJK

The PR body says "Residual CJK: 10 lines in 10 files". The actual count is 23 lines in 11 files. The extras are feature-release-notes (2), 20260507-1747 (5), 20260512-1817 (3), 20260512-1852 (5), and others. All are intentional literals. Only the claim is wrong.

### N9. Minor wording in RELIABILITY.md:28

- Original: `不要改用隐式 fallback`
- Translated: `do not silently switch to an implicit fallback`

"silently" is redundant. Harmless.

## Verified clean (no finding)

- **ARCHITECTURE.md (191 lines):** all numbers, env vars, tool names and code spans are intact. These carry the same meaning:
  - the negations: sky_click never sends a defocus to the foreground app, explicit modes never fall back, lock guard fail-closed
  - the thresholds: 1200/64, 500 chars, 8pt, 30 s, 343/240
- **SECURITY.md:** the 61→60 line change comes from folding the dangling `共同提供。` into the list lead-in. No content was lost. All "cannot/never/only" constraints in the trust-boundary and peer-auth section are preserved.
- **RELIABILITY, REPO_COLLAB_GUIDE, CONTRIBUTING, CLAUDE.md, macos-skylight-background-click:** faithful.
- **feature-release-notes:** all 60+ rows have the same dates, versions and meaning apart from N2–N4 and B3.
- **software-cursor-overlay, standalone-cursor-lab:** faithful, including the per-tool trigger table, pixel sizes, spring params and slider sample values.
- **AGENTS.md:** the added "write all repository documents in English" rule is new content. It is disclosed in the PR body and the history note, so it is intentional and not a fidelity defect.
- **codex-computer-use-cli.md (135→126) and permission-onboarding.md (190→188):** hard-wrapped prose was reflowed into single lines. No content was lost.

## Unresolved questions

- Is the B3 inconsistency across files deliberate per translator (18 parallel agents), or should the "keep literal + gloss" policy be applied everywhere? This report assumes the second.
