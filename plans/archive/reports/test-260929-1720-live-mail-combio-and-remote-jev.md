# Live test: Apple Mail "combio" search + remote jev `decide_next_action` (0.3.9-vietairs.1)

Date: 2026-09-29 ~17:10 AEST. Session MCP server: freshly installed `@vietairs/open-computer-use@0.3.9-vietairs.1`
(notarized), `OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND=remote`, config at
`~/Library/Application Support/OpenComputerUse/decision-model/remote-backend.json` → `https://131.172.248.161:18003`.

## Outcome

- **Mail task: done.** The search for "combio" across all mailboxes returned 108 results; the summary is below.
- **Remote jev advisor: failed live.** All 3 `decide_next_action` calls through the MCP server returned
  "Decision model request timed out". The same harness that passed at 16:57 (6.3s cold, 1.9s warm) now fails too:
  22 of 27 `/tokenize` calls took about 12s, then it hit the deadline. A retry failed with CFNetwork error 310.
- The model never acted and nothing was sent. The remote backend fails closed as designed.

## ComBio email summary (from the result list previews)

ComBio 2026 is in Sydney at the International Convention Centre, the week of 28 Sep 2026. Harvey is presenting a poster.

| Thread | Latest | Gist |
|---|---|---|
| Combio poster printing (Ricarda Jost ↔ Harvey, 10 msgs) | 28/9 5:35 pm | Ricarda arranged the poster printing. Harvey thanked her ("a pint of beer in Sydney"). Ricarda's auto-reply says she is at ComBio. |
| Combio – Node engagement (Ricarda & Sweety, 2 msgs) | 28/9 5:29 pm | Seeking engagement opportunities for the APPN LTU node at ComBio. A digital pack has been prepared and feedback given. |
| ComBio 2026: Name Badge & Attendee App (ComBio office) | 24/9 4:37 pm | Badge collection at ICC Sydney, attendee app details, attendee ref 1332. |
| ComBio 2026: Final confirmation (Posters) (ComBio office ↔ Harvey, 2) | 24/9 4:10 pm | Final poster confirmation. |
| ComBio 2026 – Accommodation Booking Reminder (Harvey, Sandra Clavijo Arango, Accor, 5) | 24/9 10:27 am | Accommodation booked. **Action: forward the hotel tax invoice to Sandra** when it arrives. Harvey agreed. |
| Meeting declines/cancellations (Ricarda, 21–22/9) | 21–22/9 | APPN phenotyping & data team meeting cancelled, and the SCMES-APPNLTU catch-up declined, because Ricarda and Oliver are at ComBio. Chang Liu leads the catch-up. |
| Join 750+ colleagues at ComBio 2026 (ComBio) | 15/9 | Registration promo. Keynote speakers include Prof. Martin Steinegger. |

Open item: forward the Accor tax invoice to Sandra. The other 90+ results were not individually reviewed. Most match
only in quoted text or signatures.

## Remote jev failure: evidence

| Check | Result |
|---|---|
| jev health over HTTPS from the Mac | 200 in ~0.15s (TLS ~0.1s) |
| Tailnet path | direct via medaghubws `131.172.248.216`, 40 ms RTT (not a relay) |
| nginx `jev-tls-proxy` limits | no `limit_req`/`limit_conn`; `client_max_body_size 2m`, `proxy_read_timeout 30s`; 0 "limiting" log lines |
| jev queue | `Running: 0, Waiting: 0` |
| vm100 GPUs | both at 100% utilisation (~67–70 GiB used), shared with production |
| Harness, 16:57 | pass: 27 tokenize + 6 completions, 6.3s cold / 1.9s warm |
| Harness, ~17:15 | fail: 22 tokenize in 12.3s → timeout; retry → CFNetwork 310 |

Likely cause (not yet proven): per-request latency rose to about 0.5s. There are about 0.15s of fresh TLS per call,
because the transport deliberately uses one ephemeral `URLSession` per request with no keep-alive. On top of that,
jev is slower while the production engine shares the GPUs. With a cold letter cache, the 27 sequential `/tokenize`
calls plus the completions exceed the call deadline. The letter cache is only filled on success, so every call stays
cold and times out.

## Problems during the Mail run (tool-side, for the maintainers)

1. `set_value` on Mail's search field filled in the text but did not run the search. The Search button only opened
   the suggestions popover.
2. `press_key Return` went to the focused message web view, not to the search field.
3. A coordinate click at (600,12) hit **New Message** instead of the search field. This opened an empty compose
   window, which was then closed with **Don't Save**. Nothing was sent or saved.
4. What worked: once the field had keyboard focus, `type_text "combio"` + `press_key Return`.
5. Clicking a result row did not select it ("No Message Selected"), so the summary relies on list previews.

## Suggested next steps

- Decide how to handle the cold-start cost of letter resolution. Options:
  - send one batched `/tokenize` request, if the jev contract allows it;
  - persist the resolved letter table on disk, keyed by (base_url, model);
  - allow HTTP keep-alive within a single `decide_next_action` call.
  Each needs a small design decision, because the one-session-per-request transport is part of the security posture.
- Re-run the harness when vm100's GPUs are idle, to separate network cost from model load.
- Mail automation: prefer focus plus `type_text`/`Return` for search fields, and avoid coordinate clicks near the toolbar.

## Unresolved questions

- Is jev slower now because of production load on the shared GPUs (MPS), or because of something in the nginx path?
  Timing `/tokenize` on vm100 itself would tell.
- What exactly triggered CFNetwork error 310 on the retry?
