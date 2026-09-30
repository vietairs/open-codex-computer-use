# PR #25 review, round 3 (final): delta 2711167..9a836db

Verdict: **Approve**. No Critical or Important findings.

## Scope
- f18af3d: `XMLDeclaredEncodingCheck.swift` (new, 109 LOC), `XMLDocumentTypeStripper.swift` (+ validate call, misplaced-decl refusal, doc rewrite), `XMLDocumentTypeStripperEncodingTests.swift` (new, 151 LOC), history note.
- 9a836db: doc comment on `StdioMCPServer.run()`.

## 1. Bypass closed? Yes (empirically)
Only parse site is `ScriptingDictionaryLookup.parse` (ScriptingDictionaryLookup.swift:197-209); XInclude targets also go through it (ScriptingDictionaryLookup.swift:360, `parse` attr other than `xml` skipped), so every included file gets the same BOM/encoding/first-unit check. Text declarations in included files are parsed as full documents via the same path.

Harness built from the branch sources; each row compares stripper+parse vs raw libxml2 parse (raw proves the vector is live):

| Vector | Stripper | Raw libxml2 |
|---|---|---|
| UTF-7 decl (billion-laughs in UTF-7) | REFUSED unsupportedEncoding | expands |
| UTF-8 BOM + decl UTF-7 | REFUSED | UTF-7 honoured |
| EBCDIC autodetect 4C 6F A7 94, no decl | REFUSED (first unit) | expands |
| EBCDIC decl IBM037; EBCDIC ws-first (0x40) | REFUSED | expands / err |
| UTF-32 BE/LE with and without BOM | REFUSED (NUL in head) | BE no-BOM expands |
| UTF-16 LE/BE no BOM | REFUSED (NUL in head) | expands |
| UTF-16 BOM + decl UTF-8 / UTF-16BE / ISO-8859-1 | REFUSED (utf16 branch allowlist) | - |
| UTF-8 BOM + decl UTF-16; bytes + decl UTF-16/UCS-2/UCS-4 | REFUSED | - |
| case: `uTf-7`, `ENCODING=`, `<?XML` | REFUSED | - |
| no-ws attrs, dup encoding (UTF-8 then UTF-7), attr order, unquoted, junk attr, `encoding=" UTF-7"` | REFUSED | - |
| decl after leading ws / after comment | REFUSED unreadableXMLDeclaration | - |
| `<?xml\f...` (not a decl for libxml2 either) | PARSE-ERR, no expansion | err |
| allowlisted latin1/ISO-8859-1/windows-1252/cp1258/UTF-16 BOM with DTD | stripped, entity undeclared -> PARSE-ERR | expands |

Allowlist reviewed: every entry (utf-8, us-ascii, latin1, ISO-8859-1..16 minus 12, windows/cp1250-1258) keeps ASCII at ASCII values; no EBCDIC/7-bit/multi-byte-stateful alias (ISO-2022, UTF-7, HZ, Shift_JIS-like trail-byte encodings) is on it. `lowercased()` Unicode folding cannot map a non-ASCII value onto an allowed name (only U+212A->k collides with ASCII; no allowed name contains `k`). libxml2's own autodetect table (00 00 00 3C, 3C 00 00 00, 00 00 3C 00, 00 3C 00 00, 4C 6F A7 94, 3C 00 3F 00, 00 3C 00 3F, BOMs) is fully covered by the NUL-in-head and first-unit rules.

## 2. False refusals
Sweep of every `.sdef` under /Applications, /System/Applications, /System/Library/CoreServices, /System/Library/ScriptingDefinitions (maxdepth 6): **49/49 strip and parse**, 0 refused. Declarations seen: `UTF-8` x45, `utf-8` x3, none x1. Logic spot-check: real sdefs start with `<?xml version="1.0" encoding="UTF-8"?>` at offset 0 -> allowed; `standalone=` also accepted by the attribute reader.

## 3. Findings

### Critical: none
### Important: none

### Minor (non-blocking)
- M1 `XMLDocumentTypeStripperEncodingTests.swift:129-132` `testEntityInAcceptedDocumentStillFailsAsUndeclared` asserts only that *something* throws; a stripper refusal (e.g. strayDeclaration) would pass it just as well as the intended libxml2 undeclared-entity error. Assert the stripper succeeds first, then that `XMLDocument(data:)` throws.
- M2 Test gaps (logic verified by harness, not pinned by tests): attribute name without `=` (`junk encoding=...`), whitespace inside the value (`" UTF-7"`), UTF-16 BOM + decl `UTF-16BE/LE` refusal (strict; accepted-refusal behaviour not documented as a test).
- M3 `XMLDeclaredEncodingCheck.swift:6-7` "follows the encoding ... even after a byte-order mark": verified for a UTF-8 BOM (UTF-7 honoured); with a UTF-16 BOM + decl UTF-8 libxml2 kept UTF-16 (raw parse succeeded). Claim is true for the case that matters; could say "after a UTF-8 byte-order mark". Wording only.
- M4 `XMLDeclaredEncodingCheck.swift:43-44` "the parser also honours an encoding in those malformed shapes" (no whitespace between attributes, any order) is not demonstrated; harmless since the check is stricter either way.

Doc comments otherwise accurate: stripper header (XMLDocumentTypeStripper.swift:9-15) matches behaviour; `codeUnits` doc matches (NUL check is first 4 bytes, "up front" is fair). `StdioMCPServer.run()` comment (MCPServer.swift:44-47) verified: `LocalChannelRouter()` defaults `environment` to `ProcessInfo.processInfo.environment` (LocalChannelRouter.swift:19-22), not the injected closure.

## Repro commands
```
S=/private/tmp/claude-501/-Users-hvnguyen-Projects-open-codex-computer-use/0a4f5ed5-68d3-4d03-ab61-127aeb69dc4a/scratchpad/round3
cd $S && swiftc -O -o r3 XMLDocumentTypeStripper.swift XMLDeclaredEncodingCheck.swift main.swift && ./r3
swiftc -O -o sw/sweep swsrc/*.swift
find /Applications /System/Applications /System/Library/CoreServices /System/Library/ScriptingDefinitions -maxdepth 6 -name '*.sdef' -print0 | xargs -0 ./sw/sweep
```
(sources copied from the worktree at 9a836db; `swift test` not run per instructions)

## Unresolved questions
- None blocking. Sweep found 49 sdefs vs the PR's 46 (different search roots); all pass.
