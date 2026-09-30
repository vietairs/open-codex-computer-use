#!/usr/bin/python3
"""Server-side latency bench for Open Computer Use over direct MCP stdio (Track A, PR A speed).

Run ONLY from the main loop (never inside a workflow): it drives the real Mail app through a bench build's
app agent. Stdlib only; run with /usr/bin/python3 (the framework python3 build is SIGKILLed on this Mac).

Privacy: tool result text (Mail subjects, previews) is never printed or stored. Records keep timings, sizes,
part types, and at most 160 characters of an *error* text. `render` stores only sha256 hashes unless
--save-dir is given, in which case files are written 0600 and must be deleted after the diff.

Modes (see phase-00-baseline-measurement.md for the exact protocol):
  preflight | cycle | gas | render | decide | batch   -> talk to a server, append JSONL records
  summarize                                            -> offline, reads JSONL records
  turns                                                -> offline, reads Claude Code transcript JSONLs;
                                                          with --control it applies the turns gate
"""
import argparse, hashlib, json, os, queue, re, statistics, subprocess, sys, threading, time

# Combio call mix: OCU action calls in the baseline Mail "combio" run (session 0a4f5ed5, 2026-09-29 07:10-07:14Z):
# click 6, press_key 5, set_value 1, type_text 1. decide_next_action (3) and get_app_state (3) are reported apart.
COMBIO_WEIGHTS = {"click": 6, "press_key": 5, "set_value": 1, "type_text": 1}
ACTION_TOOLS = set(COMBIO_WEIGHTS)
DEFAULT_SEARCH_RE = r"^\s*(\d+) search text field"
FOCUS_LINE_RE = re.compile(r"^The focused UI element is (.*)$", re.M)
LSAPPINFO = "/usr/bin/lsappinfo"
FRONT_CHANGED_EXIT = 3
FOCUS_POLL_TRIES, FOCUS_POLL_INTERVAL = 8, 0.2


def front_asn():
    """ASN of the frontmost app. Fails closed: the guard cannot run blind."""
    try:
        out = subprocess.run([LSAPPINFO, "front"], capture_output=True, text=True, timeout=5, check=True).stdout.strip()
    except (OSError, subprocess.SubprocessError) as exc:
        raise SystemExit(f"front-app guard: `lsappinfo front` failed ({exc}); --no-front-guard is for debugging only")
    if not out:
        raise SystemExit("front-app guard: `lsappinfo front` printed nothing; --no-front-guard is for debugging only")
    return out


def app_name_of(asn):
    try:
        out = subprocess.run([LSAPPINFO, "info", "-only", "name", asn], capture_output=True, text=True,
                             timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return asn
    m = re.search(r'"LSDisplayName"="([^"]*)"', out)
    return f"{m.group(1)} ({asn})" if m else asn


class Server:
    def __init__(self, server_bin, env_extra, call_timeout):
        env = dict(os.environ)
        env.update(env_extra)
        self.p = subprocess.Popen([server_bin, "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, text=True, bufsize=1, env=env)
        self.q = queue.Queue()
        self.i = 0
        self.timeout = call_timeout
        threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self):
        for line in self.p.stdout:
            self.q.put(line)
        self.q.put(None)

    def request(self, method, params=None):
        self.i += 1
        msg = {"jsonrpc": "2.0", "id": self.i, "method": method}
        if params is not None:
            msg["params"] = params
        t0 = time.perf_counter()
        self.p.stdin.write(json.dumps(msg) + "\n")
        self.p.stdin.flush()
        deadline = t0 + self.timeout
        while True:
            left = deadline - time.perf_counter()
            if left <= 0:
                raise SystemExit(f"timeout after {self.timeout}s waiting for {method}")
            line = self.q.get(timeout=left)
            if line is None:
                raise SystemExit("server closed stdout (exit 141/137 here usually means no GUI context or TCC)")
            resp = json.loads(line)
            if resp.get("id") == self.i:
                return resp, time.perf_counter() - t0

    def notify(self, method):
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": method}) + "\n")
        self.p.stdin.flush()

    def close(self):
        try:
            self.p.stdin.close()
            self.p.wait(timeout=10)
        except Exception:
            self.p.kill()


def text_of(resp):
    content = resp.get("result", {}).get("content", [])
    return "\n".join(c.get("text", "") for c in content if c.get("type") == "text")


def parts_of(resp):
    return [c.get("type") for c in resp.get("result", {}).get("content", [])]


class Bench:
    def __init__(self, args):
        self.args = args
        # G2 tripwire: the user's frontmost app, recorded before the server starts; every tool call is bracketed by a
        # check against it, so a focus theft aborts the run at the call that caused it.
        self.front = None if args.no_front_guard else front_asn()
        if self.front:
            print(f"[{args.label}] front-app guard on: {app_name_of(self.front)}")
        else:
            print(f"[{args.label}] WARN: front-app guard OFF (--no-front-guard); not valid for any recorded run")
        env = {"OPEN_COMPUTER_USE_VISUAL_CURSOR": "1" if args.cursor == "on" else "0"}
        if args.namespace:
            env["OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE"] = args.namespace
        if args.remote_decision:
            env["OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND"] = "remote"
        self.server = Server(args.server, env, args.call_timeout)
        os.makedirs(args.out, exist_ok=True)
        self.out = open(os.path.join(args.out, f"{args.label}.jsonl"), "a")
        _, dt = self.server.request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                                    "clientInfo": {"name": "ocu-speed-bench", "version": "1"}})
        self.server.notify("notifications/initialized")
        tools, _ = self.server.request("tools/list", {})
        self.tool_names = [t["name"] for t in tools.get("result", {}).get("tools", [])]
        print(f"[{args.label}] initialize {dt:.2f}s tools={len(self.tool_names)}")
        self.check_front("after server start")

    def check_front(self, where):
        if not self.front:
            return
        now = front_asn()
        if now != self.front:
            print(f"ABORT: frontmost app changed {where}: now {app_name_of(now)}, was {app_name_of(self.front)}."
                  " The run took focus from the user's app; nothing after this call was sent.", file=sys.stderr)
            raise SystemExit(FRONT_CHANGED_EXIT)

    def call(self, mode, rnd, tool, arguments, record=True):
        self.check_front(f"before {tool} (mode={mode} round={rnd})")
        resp, dt = self.server.request("tools/call", {"name": tool, "arguments": arguments})
        self.check_front(f"after {tool} (mode={mode} round={rnd})")
        res = resp.get("result", {})
        text = text_of(resp)
        is_error = bool(res.get("isError")) or "error" in resp
        rec = {"label": self.args.label, "cursor": self.args.cursor,
               "include_screenshot": self.args.include_screenshot, "mode": mode, "round": rnd, "tool": tool,
               "shape": sorted(k for k in arguments if k not in ("app", "include_screenshot")), "seconds": round(dt, 4), "is_error": is_error,
               "text_chars": len(text), "parts": parts_of(resp), "bytes": len(json.dumps(resp)),
               "warmup": rnd < self.args.warmup, "ts": time.strftime("%Y-%m-%dT%H:%M:%S")}
        if is_error:
            rec["error_head"] = (text or json.dumps(resp.get("error", "")))[:160]
        if record:
            self.out.write(json.dumps(rec) + "\n")
            self.out.flush()
        return resp, text, rec

    def search_index(self, text):
        m = re.search(self.args.search_field_re, text, re.M)
        if not m:
            raise SystemExit("search field not found: open a Mail viewer window with the toolbar search field visible,"
                             " or pass --search-field-re")
        return m.group(1)

    def focus_text(self, text):
        focus = FOCUS_LINE_RE.search(text)
        return focus.group(1) if focus else None

    def require_focus(self, text, what):
        focus = self.focus_text(text)
        if focus is None or not re.search(self.args.focus_re, focus):
            raise SystemExit(f"abort before typing: {what} did not leave the search field focused"
                             f" (observed focus: {focus[:120] if focus else 'none'});"
                             " no keystrokes sent to Mail's message view")

    def wait_for_search_focus(self, rnd, text, what):
        """G1: the search field must hold focus before any text or Return is sent. Polls unrecorded compact states,
        because Mail moves focus asynchronously after the shortcut."""
        focus = self.focus_text(text)
        for _ in range(FOCUS_POLL_TRIES):
            if focus is not None and re.search(self.args.focus_re, focus):
                return
            time.sleep(FOCUS_POLL_INTERVAL)
            _, text, _ = self.call("focus-poll", rnd, "get_app_state", {"app": self.args.app, "compact": True},
                                   record=False)
            focus = self.focus_text(text)
        self.require_focus(text, what)

    def recheck_before_return(self, rnd):
        """G1: a fresh, unrecorded read right before Return; the value and the focus must both still be on the field."""
        _, text, _ = self.call("focus-poll", rnd, "get_app_state", {"app": self.args.app, "compact": True},
                               record=False)
        self.require_search_value(text)
        self.require_focus(text, "the typed search")

    def require_search_value(self, text):
        if not any(re.search(self.args.search_field_re, ln) and self.args.query in ln for ln in text.splitlines()):
            raise SystemExit("abort: typed text did not land in the search field")

    # ---- modes -------------------------------------------------------------------------------------------------
    def preflight(self):
        resp, text, rec = self.call("preflight", 0, "get_app_state", {"app": self.args.app})
        s = self.search_index(text)
        print(f"get_app_state {self.args.app}: {rec['seconds']:.2f}s parts={rec['parts']} text_chars={rec['text_chars']}"
              f" search_field_index={s} error={rec['is_error']}")
        if "image" not in rec["parts"]:
            print("WARN: no image part -> Screen Recording grant missing for this build; baseline capture cost would be"
                  " understated. Fix the grant before measuring.")
        if rec["text_chars"] < 1000:
            print("WARN: tiny AX tree -> Accessibility grant missing or wrong window.")

    def act(self, mode, rnd, tool, arguments):
        """Action-tool call for cycle mode: adds include_screenshot=true only under --include-screenshot, so the
        default arguments stay exactly what they were."""
        if self.args.include_screenshot:
            arguments = {**arguments, "include_screenshot": True}
        return self.call(mode, rnd, tool, arguments)

    def cycle(self):
        a, q = self.args.app, self.args.query
        for r in range(self.args.warmup + self.args.rounds):
            _, text, _ = self.call("cycle", r, "get_app_state", {"app": a, "compact": True})
            s = self.search_index(text)
            self.act("cycle", r, "click", {"app": a, "element_index": s})
            _, text, _ = self.act("cycle", r, "press_key", {"app": a, "key": "cmd+option+f"})
            self.wait_for_search_focus(r, text, "cmd+option+f")
            _, text, rec = self.act("cycle", r, "type_text", {"app": a, "text": q})
            if rec["is_error"]:
                raise SystemExit(f"abort: type_text failed: {rec.get('error_head', '')}")
            self.require_search_value(text)
            self.recheck_before_return(r)
            _, text, _ = self.act("cycle", r, "press_key", {"app": a, "key": "Return"})
            s2 = self.search_index(text)
            _, text, _ = self.act("cycle", r, "click", {"app": a, "element_index": s2})
            # the click returns a fresher tree than the Return result; index set_value against it
            s3 = self.search_index(text)
            self.act("cycle", r, "set_value", {"app": a, "element_index": s3, "value": ""})
            self.act("cycle", r, "press_key", {"app": a, "key": "Escape"})
            print(f"round {r} done")

    def gas(self):
        for r in range(self.args.warmup + self.args.rounds):
            self.call("gas", r, "get_app_state", {"app": self.args.app})
            self.call("gas", r, "get_app_state", {"app": self.args.app, "compact": True})

    def render(self):
        for app in self.args.apps.split(","):
            resp, text, rec = self.call("render", 0, "get_app_state", {"app": app})
            digest = hashlib.sha256(text.encode()).hexdigest()
            print(f"RENDER label={self.args.label} app={app} sha256={digest} chars={len(text)} parts={rec['parts']}")
            if self.args.save_dir:
                os.makedirs(self.args.save_dir, mode=0o700, exist_ok=True)
                path = os.path.join(self.args.save_dir, f"{self.args.label}-{app}.txt")
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, "w") as fh:
                    fh.write(text)

    def decide(self):
        if "decide_next_action" not in self.tool_names:
            raise SystemExit("decide_next_action not listed: pass --remote-decision")
        for r in range(self.args.calls):
            _, _, rec = self.call("decide", r, "decide_next_action", {"app": self.args.app, "goal": self.args.goal})
            print(f"decide call {r}: {rec['seconds']:.2f}s error={rec['is_error']} {rec.get('error_head', '')[:80]}")

    def batch_clear(self, mode, rnd, text):
        s2 = self.search_index(text)
        self.call(mode, rnd, "perform_actions", {"app": self.args.app, "actions": [
            {"tool": "set_value", "args": {"element_index": s2, "value": ""}},
            {"tool": "press_key", "args": {"key": "Escape"}}]})

    def batch(self):
        if "perform_actions" not in self.tool_names:
            raise SystemExit("perform_actions not listed by this build")
        a, q = self.args.app, self.args.query
        # Probe round (recorded as warm-up): focus + type with NO Return. If typing outran Mail's focus change, the
        # text went to the message list, and without Return no message is opened or marked read.
        _, text, _ = self.call("batch", -1, "get_app_state", {"app": a, "compact": True})
        self.search_index(text)
        _, text, rec = self.call("batch", -1, "perform_actions", {"app": a, "actions": [
            {"tool": "press_key", "args": {"key": "cmd+option+f"}},
            {"tool": "type_text", "args": {"text": q}}]})
        if rec["is_error"] or not re.search(r"^Step 2 type_text: ok$", text, re.M):
            raise SystemExit(f"batch probe failed: {rec.get('error_head', 'step 2 not ok')}")
        self.require_search_value(text)
        self.batch_clear("batch", -1, text)
        print("batch probe (no Return) done")
        for r in range(self.args.warmup + self.args.rounds):
            _, text, _ = self.call("batch", r, "get_app_state", {"app": a, "compact": True})
            self.search_index(text)
            _, text, rec = self.call("batch", r, "perform_actions", {"app": a, "actions": [
                {"tool": "press_key", "args": {"key": "cmd+option+f"}},
                {"tool": "type_text", "args": {"text": q}},
                {"tool": "press_key", "args": {"key": "Return"}}]})
            if rec["is_error"] or not re.search(r"^Step 3 press_key key=Return: ok$", text, re.M):
                raise SystemExit(f"batch round {r} failed: {rec.get('error_head', 'step 3 not ok')}")
            self.require_search_value(text)
            self.batch_clear("batch", r, text)
            print(f"batch round {r} done")

def weighted_points(samples_by_tool):
    pts = []
    for tool, xs in samples_by_tool.items():
        if tool in COMBIO_WEIGHTS and xs:
            w = COMBIO_WEIGHTS[tool] / len(xs)
            pts += [(x, w) for x in xs]
    return sorted(pts)


def weighted_median(samples_by_tool):
    pts = weighted_points(samples_by_tool)
    if not pts:
        return None
    total, acc = sum(w for _, w in pts), 0.0
    for x, w in pts:
        acc += w
        if acc >= total / 2:
            return x


def weighted_mean(samples_by_tool):
    """Reported beside the median (not a gate): shows keyboard-path gains the click-dominated median hides."""
    pts = weighted_points(samples_by_tool)
    if not pts:
        return None
    return sum(x * w for x, w in pts) / sum(w for _, w in pts)


def summarize(args):
    rows = []
    for path in args.files:
        with open(path) as fh:
            rows += [json.loads(l) for l in fh if l.strip()]
    groups, errors = {}, {}
    for r in rows:
        if r.get("warmup"):
            continue
        if r.get("is_error"):
            ekey = (r["label"], r["cursor"], r["mode"])
            errors[ekey] = errors.get(ekey, 0) + 1
            continue
        key = (r["label"], r["cursor"], r["mode"])
        tool = r["tool"] + ("(compact)" if "compact" in r.get("shape", []) else "")
        groups.setdefault(key, {}).setdefault(tool, []).append(r["seconds"])
    medians, means = {}, {}
    for (label, cursor, mode), by_tool in sorted(groups.items()):
        print(f"\n== label={label} cursor={cursor} mode={mode}")
        for tool, xs in sorted(by_tool.items()):
            q = statistics.quantiles(xs, n=4) if len(xs) >= 4 else [min(xs), statistics.median(xs), max(xs)]
            flag = "" if len(xs) >= 10 else "  (n<10: not acceptance-grade)"
            print(f"  {tool:28s} n={len(xs):3d} median={statistics.median(xs):.3f}s p25={q[0]:.3f} p75={q[-1]:.3f}{flag}")
        wm, wmean = weighted_median(by_tool), weighted_mean(by_tool)
        if wm is not None:
            print(f"  COMBIO_WEIGHTED_MEDIAN={wm:.3f}s COMBIO_WEIGHTED_MEAN={wmean:.3f}s")
            if mode == "cycle":  # M_server is defined on single action calls from the cycle mode only
                medians[(label, cursor)], means[(label, cursor)] = wm, wmean
    print("\nerror calls (non-warm-up, excluded from timings): "
          + (", ".join(f"{l}/cursor={c}/{m}: {n}" for (l, c, m), n in sorted(errors.items())) or "0"))
    if args.baseline and args.candidate:
        for cursor in ("on", "off"):
            b, c = medians.get((args.baseline, cursor)), medians.get((args.candidate, cursor))
            if b and c:
                ratio = c / b
                # The gate's own samples come from cycle mode, so any cycle error makes the comparison invalid
                # (summarize drops error calls from the timings, which would otherwise hide slow failures).
                n_err = errors.get((args.baseline, cursor, "cycle"), 0) + errors.get((args.candidate, cursor, "cycle"), 0)
                if n_err:
                    verdict = f"INVALID ({n_err} cycle error calls; acceptance-grade runs need zero)"
                else:
                    verdict = "PASS" if ratio <= args.target_ratio else "FAIL"
                mean_ratio = means[(args.candidate, cursor)] / means[(args.baseline, cursor)]
                print(f"cursor={cursor}: {args.candidate} / {args.baseline} = {ratio:.3f} (target <= {args.target_ratio})"
                      f" -> {verdict}; weighted mean ratio = {mean_ratio:.3f} (reported, not a gate)")

def count_turns(path, since, until):
    calls, messages = 0, set()
    with open(path) as fh:
        for line in fh:
            try:
                o = json.loads(line)
            except ValueError:
                continue
            ts = o.get("timestamp", "")
            if o.get("type") != "assistant" or not (since <= ts <= until):
                continue
            msg = o.get("message") or {}
            for part in msg.get("content") or []:
                if isinstance(part, dict) and part.get("type") == "tool_use" and "open-computer-use" in part.get("name", ""):
                    calls += 1
                    messages.add(msg.get("id"))
    return calls, len(messages)


def turns(args):
    def median_of(paths, tag):
        ts = []
        for path in paths:
            calls, n_msgs = count_turns(path, args.since, args.until)
            ts.append(max(calls - 1, 0))
            print(f"{tag} {os.path.basename(path)}: OCU tool calls={calls} agent_turns(T=calls-1)={ts[-1]}"
                  f" assistant_messages_with_OCU={n_msgs}")
        return statistics.median(ts)
    t_head = median_of(args.transcript, "run")
    if len(args.transcript) > 1:
        print(f"median agent_turns={t_head}")
    if args.control:
        t_ctrl = median_of(args.control, "control")
        limit = min(args.max_turns, args.max_ratio * t_ctrl)
        verdict = "PASS" if t_head <= limit else "FAIL"
        print(f"TURNS GATE: median T={t_head} vs control median T={t_ctrl}: need <= {args.max_turns} and"
              f" <= {args.max_ratio} x control ({args.max_ratio * t_ctrl:g}) -> {verdict}")

def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="mode", required=True)
    for name in ("preflight", "cycle", "gas", "render", "decide", "batch"):
        sp = sub.add_parser(name)
        sp.add_argument("--server", required=True, help="path to .../Contents/MacOS/OpenComputerUse")
        sp.add_argument("--label", required=True)
        sp.add_argument("--out", required=True)
        sp.add_argument("--cursor", choices=("on", "off"), default="on")
        sp.add_argument("--namespace", default="", help="OPEN_COMPUTER_USE_AGENT_SOCKET_NAMESPACE for bench builds")
        sp.add_argument("--app", default="Mail")
        sp.add_argument("--rounds", type=int, default=10)
        sp.add_argument("--warmup", type=int, default=1)
        sp.add_argument("--call-timeout", type=float, default=90)
        sp.add_argument("--query", default="combio")
        sp.add_argument("--search-field-re", default=DEFAULT_SEARCH_RE)
        sp.add_argument("--focus-re", default=r"search text field")
        sp.add_argument("--apps", default="Finder,Mail,TextEdit")
        sp.add_argument("--save-dir", default="")
        sp.add_argument("--remote-decision", action="store_true")
        sp.add_argument("--goal", default="focus the mailbox search field")
        sp.add_argument("--calls", type=int, default=5)
        sp.add_argument("--include-screenshot", action="store_true",
                        help="cycle mode: pass include_screenshot=true on every action tool call (click, press_key,"
                             " type_text, set_value); default sends the arguments unchanged")
        sp.add_argument("--no-front-guard", action="store_true",
                        help="debugging only: skip the frontmost-app tripwire around every tool call")
    s = sub.add_parser("summarize")
    s.add_argument("files", nargs="+")
    s.add_argument("--baseline", default="")
    s.add_argument("--candidate", default="")
    s.add_argument("--target-ratio", type=float, default=0.70)
    t = sub.add_parser("turns")
    t.add_argument("--transcript", required=True, nargs="+", help="one or more transcripts (the build under test)")
    t.add_argument("--control", nargs="*", default=[], help="headless control transcripts on the baseline build")
    t.add_argument("--since", default="0000", help="ISO timestamp, e.g. 2026-09-29T07:09:00 (default: whole file)")
    t.add_argument("--until", default="9999")
    t.add_argument("--max-turns", type=float, default=9)
    t.add_argument("--max-ratio", type=float, default=0.5)
    args = ap.parse_args()
    if args.mode == "summarize":
        return summarize(args)
    if args.mode == "turns":
        return turns(args)
    bench = Bench(args)
    try:
        getattr(bench, args.mode)()
    finally:
        bench.server.close()


if __name__ == "__main__":
    main()
