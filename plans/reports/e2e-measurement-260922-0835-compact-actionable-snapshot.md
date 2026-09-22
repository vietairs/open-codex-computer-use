# P0 measurement — compact actionable view

Run 2026-09-22 08:35 against the branch build (commit 9dbd744) deployed into
`Open Computer Use (Dev).app`, signed with a Developer ID so the Accessibility grant survives
rebuilds. `doctor` reported `accessibility=granted, screenRecording=granted`.

## Numbers (text payload only — see caveat)

| App | full bytes | compact bytes | saving | elements kept |
|---|---|---|---|---|
| Google Chrome | 20793 | 12147 | 42% | 271 of 317 (85%) |
| Mail | 14175 | 12585 | 12% | 77 of 112 (69%) |
| Finder | 23597 | 16702 | 30% | 252 of 380 (66%) |

Latency was indistinguishable (0.15–0.20 s both ways). Compact drops the screenshot at result
assembly but capture still runs, so no latency saving was expected and none was observed.

## Caveat that bounds every number above

No run produced a screenshot: every response carried exactly one `text` content block and no
`image` block, in full mode too. So these figures compare text against text, and the screenshot
suppression path — implemented and unit-tested — was never exercised end to end. Treat the
savings as a FLOOR. In normal MCP use a full snapshot also carries a PNG capped at 900 KB before
base64, which dominates the payload; compact drops it entirely.

## Verified end to end

- Focused-element hoisting: Finder compact led with `272 list (focused)`.
- Child-text carry (the round-2 H1 fix): Chrome produced
  `61 row Model — Download | Authored | Perturbed | TypeSafe`, a list row whose columns the
  previous build discarded, leaving sibling rows indistinguishable.
- Index stability: compact indices match the full tree in all three apps.

## Gate reading

The P0 gate asked whether pruning alone captures most of the benefit, in which case the classifier
is unnecessary. On tree text alone it does not: 12–42% is real but not the order of magnitude that
motivated the proposal. The dominant win is dropping the screenshot, which is a property of the
mode rather than of the pruning — and that is the part still unmeasured here.

A second observation from the real output: the filter keeps a lot of scaffolding. Finder compact
included several `scroll area ... Secondary Actions: Scroll Up, Scroll Down` rows, which are not
plausible targets for an agent. Retention of 66–85% suggests the allow-list could be tightened,
which would raise the saving without touching the classifier question.

## Unresolved

- Screenshot suppression is unverified end to end; a run where capture actually succeeds is needed.
- Whether tightening the filter toward a positive allow-list (drop scroll areas and pure
  containers) is safe has not been tested against a real click flow.
