# Auto-decisions — compact actionable snapshot (P0)

Run mode: `--auto --counsel`. Gates were not put to the user; each decision below was
auto-adjudicated with conservative bias and is recorded here so it can be audited or reversed.

Risk classification: **medium** (additive, read-only, but it changes a published MCP tool schema).
Medium never auto-merges, so this run ends at a merge-ready PR regardless of gate outcomes.

---

## 1. Ship macOS-only rather than across all three runtimes

**What:** `compact` is implemented in the Swift runtime only. The Linux and Windows Go runtimes
maintain their own tool schemas (`apps/OpenComputerUse{Linux,Windows}/main.go`) and do not accept
the parameter.

**Why:** P0 exists to measure whether pruning pays before anything is built on top of it.
Implementing the same filter three times, in three accessibility models, before the first number
exists is exactly the scope the plan warns against.

**Risk:** cross-platform tool parity is a stated repo goal, so this is a real, visible gap.
Mitigated by documenting it in `docs/ARCHITECTURE.md` and in the history record rather than
leaving callers to discover it.

**Alternatives rejected:** implement in Go now (premature, triples the cost of a change that may
be reverted); hide the flag behind a macOS-only build (worse — the gap becomes invisible).

**Reversibility:** high. The Go side is an independent addition; nothing here blocks it.

---

## 2. No de-duplication of identical-looking rows

**What:** the plan's description of the compact view mentioned de-duplication. It was not
implemented.

**Why:** two rows can render identically and still be distinct targets — two "Delete" buttons in a
list. Dropping the correct target is kill-criterion #3 of this very plan, whereas printing a
near-duplicate costs a few tokens.

**Risk:** the compact view is slightly larger than it could be.

**Alternatives rejected:** de-duplicate on the rendered line (silently drops real targets);
de-duplicate on role+label+frame (same failure, more code).

**Reversibility:** high, and it should only be revisited with measurements from P0.

---

## 3. Element indices are preserved, not renumbered

**What:** compact rows keep the index the full tree assigned.

**Why:** `click`, `set_value`, `scroll` and `perform_secondary_action` all resolve by
`element_index`. Renumbering would make every compact call a trap: the agent reads index 3 and
actuates a different element. This was treated as non-negotiable rather than a trade-off.

**Reversibility:** n/a — this is a correctness constraint, not a preference.

---

## 4. `optionalBool` does not throw on unparseable input

**What:** every other optional parser in the dispatcher throws on a malformed value; this one
returns `nil` (falls back to the default).

**Why:** the flag only widens or narrows a read-only view. A client that encodes booleans oddly
gets the full tree — the safe, more informative result — rather than a hard tool error.

**Risk:** a typo'd value is silently ignored. Flagged to code review; if review disagrees, throwing
is a one-line change.

**Reversibility:** high.

---

## 5. Measurement deferred to a follow-up

**What:** the P0 gate asks for token and latency numbers against a baseline. The implementation
landed; the numbers were not collected in this run.

**Why:** measuring needs real apps driven interactively, which is not something this unattended run
should fabricate. The plan's progress list now separates "implemented" from "measured" so the gate
cannot be recorded as passed on the strength of the code alone.

**Risk:** the P0 gate — the one that can end the whole project cheaply — is still open. This is
stated in the PR rather than implied.

**Reversibility:** n/a — this is work not yet done, not a decision to undo.
