#!/usr/bin/env node
//
// Probes a running llama-server sidecar and asserts the readout semantics
// phase 04's Swift client relies on: every label is a single token, the chat
// template framing is what the prompt builder will emit, and the returned
// probabilities are pre-sampling logprobs renormalized over each head's
// label set (not grammar-masked, not post-sampling). See phase-01's
// "Signature" and "Steps" sections for the six assertions this implements.
//
// Uses only node: built-ins and the global fetch; no npm dependencies.

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { invokedAsScript } from "./run-as-script.mjs";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const manifestPath = path.join(scriptDir, "model-manifest.json");
const pinPath = path.join(scriptDir, "fixtures", "readout-pin.json");

// Label alphabets. These constants must equal what phase 04 hard-codes
// (phase-01 Signature section).
const TARGET_LABELS = [
  ...Array.from({ length: 26 }, (_, i) => String.fromCharCode(65 + i)), // A-Z
  ...Array.from({ length: 26 }, (_, i) => String.fromCharCode(97 + i)), // a-z
];
const OPERATION_NAMES = ["click", "set_value", "type_text", "scroll", "press_key", "wait", "done"];
const OPERATION_LABELS = TARGET_LABELS.slice(0, OPERATION_NAMES.length); // A-G

function labelPiece(label) {
  return ` ${label}`;
}

function usage() {
  process.stdout.write(`Usage: node scripts/decision-model/check-readout.mjs --url <base> --model <key> [--write-pin]\n`);
}

function parseArgs(argv) {
  const args = { url: null, model: null, writePin: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--url") {
      args.url = argv[i + 1];
      i += 1;
    } else if (arg === "--model") {
      args.model = argv[i + 1];
      i += 1;
    } else if (arg === "--write-pin") {
      args.writePin = true;
    } else if (arg === "--help" || arg === "-h") {
      usage();
      process.exit(0);
    } else {
      process.stderr.write(`check-readout.mjs: unknown argument: ${arg}\n`);
      usage();
      process.exit(1);
    }
  }
  if (!args.url || !args.model) {
    usage();
    process.exit(1);
  }
  return args;
}

function loadManifestEntry(modelKey) {
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  const entry = manifest.models[modelKey];
  if (!entry) {
    process.stderr.write(`check-readout.mjs: unknown model key: ${modelKey}\n`);
    process.exit(1);
  }
  return entry;
}

async function fetchJSON(url, init) {
  const response = await fetch(url, init);
  let body = null;
  const text = await response.text();
  try {
    body = text.length > 0 ? JSON.parse(text) : null;
  } catch {
    body = null;
  }
  return { status: response.status, ok: response.ok, body, rawText: text };
}

// Collects one-line failure reasons instead of throwing on the first one, so
// a single run reports every broken assertion at once.
const failures = [];
function check(condition, message) {
  if (!condition) {
    failures.push(message);
  }
  return condition;
}

async function checkHealth(base) {
  const res = await fetchJSON(`${base}/health`);
  check(res.status === 200, `GET /health returned ${res.status}, expected 200`);
  return res;
}

async function checkProps(base, expectedFilename) {
  const res = await fetchJSON(`${base}/props`);
  if (!check(res.ok, `GET /props returned ${res.status}`)) {
    return { buildInfo: null };
  }
  const modelPath = res.body?.model_path;
  const actualBasename = typeof modelPath === "string" ? path.basename(modelPath) : null;
  check(
    actualBasename === expectedFilename,
    `GET /props model_path basename "${actualBasename}" does not match manifest filename "${expectedFilename}"`,
  );
  return { buildInfo: typeof res.body?.build_info === "string" ? res.body.build_info : null };
}

// Extracts the single token piece for a `/tokenize` result, or null plus a
// pushed failure reason if the label does not tokenize to exactly one token.
async function tokenizeLabel(base, label) {
  const piece = labelPiece(label);
  const res = await fetchJSON(`${base}/tokenize`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ content: piece, add_special: false, with_pieces: true }),
  });
  if (!check(res.ok, `POST /tokenize "${piece}" returned ${res.status}`)) {
    return null;
  }
  const tokens = res.body?.tokens;
  if (!check(Array.isArray(tokens) && tokens.length === 1, `label "${piece}" tokenizes to ${Array.isArray(tokens) ? tokens.length : "non-array"} tokens, expected exactly 1`)) {
    return null;
  }
  const entry = tokens[0];
  const actualPiece = typeof entry === "object" ? entry.piece : entry;
  if (!check(actualPiece === piece, `label "${piece}" token piece is ${JSON.stringify(actualPiece)}, expected ${JSON.stringify(piece)}`)) {
    return null;
  }
  return { id: entry.id, piece: actualPiece };
}

async function checkLabelsSingleToken(base) {
  const labelTokens = new Map();
  for (const label of TARGET_LABELS) {
    const token = await tokenizeLabel(base, label);
    if (token) {
      labelTokens.set(label, token);
    }
  }
  return labelTokens;
}

// Splits an apply-template result around the "<<SYS>>" / "<<USER>>"
// sentinels into the three framing spans phase 04 needs to interpolate real
// content, then appends the empty think block Qwen3.5 requires when
// enable_thinking is false and the template did not already emit one.
async function checkTemplateFraming(base, chatTemplateKwargs) {
  const sysSentinel = "<<SYS>>";
  const userSentinel = "<<USER>>";
  const res = await fetchJSON(`${base}/apply-template`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      messages: [
        { role: "system", content: sysSentinel },
        { role: "user", content: userSentinel },
      ],
      chat_template_kwargs: chatTemplateKwargs,
      add_generation_prompt: true,
    }),
  });
  if (!check(res.ok, `POST /apply-template returned ${res.status}`)) {
    return null;
  }
  const prompt = res.body?.prompt;
  if (!check(typeof prompt === "string" && prompt.length > 0, `POST /apply-template returned a non-string or empty "prompt"`)) {
    return null;
  }

  const sysIndex = prompt.indexOf(sysSentinel);
  const userIndex = prompt.indexOf(userSentinel);
  if (!check(sysIndex >= 0 && userIndex > sysIndex, `POST /apply-template prompt does not contain both sentinels in order: ${JSON.stringify(prompt)}`)) {
    return null;
  }

  const systemPrefix = prompt.slice(0, sysIndex);
  const systemToUser = prompt.slice(sysIndex + sysSentinel.length, userIndex);
  const userSuffixToAssistant = prompt.slice(userIndex + userSentinel.length);

  const thinkBlock = "<think>\n\n</think>\n\n";
  const needsThinkBlock = chatTemplateKwargs?.enable_thinking === false && !userSuffixToAssistant.includes("<think>");

  return {
    template: { systemPrefix, systemToUser, userSuffixToAssistant },
    thinkBlock: needsThinkBlock ? thinkBlock : "",
    rawPrompt: prompt,
  };
}

function buildSyntheticUserContent() {
  return [
    "Goal: Save the document",
    "",
    "Candidates:",
    "A) menu item File",
    "B) text field Untitled",
    "C) button Save",
    "D) checkbox Read-Only",
    "E) link Help",
    "",
    'Respond with the operation letter, then the literal text "\\nTarget:", then the target letter.',
  ].join("\n");
}

function buildGrammar(operationLabels, targetLabels) {
  const opAlt = operationLabels.map((label) => `"${labelPiece(label)}"`).join(" | ");
  const tgtAlt = targetLabels.map((label) => `"${labelPiece(label)}"`).join(" | ");
  return `root ::= op "\\nTarget:" tgt\nop ::= ${opAlt}\ntgt ::= ${tgtAlt}\n`;
}

export const RESPONSE_SHAPE_NOTE =
  "completion_probabilities can include a trailing forced-stop entry (empty token/bytes) after the grammar's root production is fully matched; locate the operation-head entry at index 0 and the target-head entry as the LAST entry after index 0 whose token is a member of the page's target-label pieces, not by raw array index -1. The entries between the two heads spell the grammar literal \"\\nTarget:\" and only empty-token entries follow the target head.";

// Finds the target-head entry. Index 0 is the operation head and is never a
// candidate: operation labels A-G overlap target labels A-E, so searching down
// to index 0 would validate the target assertions against the operation
// distribution whenever the target answer is split across tokens. This is
// stricter than the Swift parser (DecisionModelClient.swift searches only
// after index 0 and throws otherwise): it also requires the tokens between the
// heads to spell the grammar's "\nTarget:" literal and only empty-token
// forced-stop entries after the target head. Returns { entry, index } or
// { error }.
export function locateTargetHead(probs, targetPieces) {
  if (!Array.isArray(probs) || probs.length < 2) {
    return { error: `completion_probabilities has ${Array.isArray(probs) ? probs.length : "no"} entries, expected >= 2` };
  }
  const tokens = probs.map((entry) => entry?.token);
  let index = -1;
  for (let i = probs.length - 1; i >= 1; i -= 1) {
    if (targetPieces.includes(tokens[i])) {
      index = i;
      break;
    }
  }
  if (index < 0) {
    return { error: `no entry after the operation head has a target-label token (tokens: ${JSON.stringify(tokens)})` };
  }
  const literal = tokens.slice(1, index).map((token) => (typeof token === "string" ? token : "")).join("");
  if (literal !== "\nTarget:") {
    return { error: `the tokens between the operation head and the target head spell ${JSON.stringify(literal)}, expected "\\nTarget:" (tokens: ${JSON.stringify(tokens)})` };
  }
  if (tokens.slice(index + 1).some((token) => token !== "")) {
    return { error: `non-empty tokens follow the target head (tokens: ${JSON.stringify(tokens)})` };
  }
  return { entry: probs[index], index };
}

function renormalizeOverLabels(topLogprobs, labelPieces) {
  const relevant = topLogprobs.filter((entry) => labelPieces.includes(entry.token));
  const maxLogprob = Math.max(...relevant.map((entry) => entry.logprob));
  const expSum = relevant.reduce((sum, entry) => sum + Math.exp(entry.logprob - maxLogprob), 0);
  const distribution = new Map();
  for (const entry of relevant) {
    distribution.set(entry.token, Math.exp(entry.logprob - maxLogprob) / expSum);
  }
  return distribution;
}

async function runSyntheticCompletion(base, framing, targetPageLabels) {
  const systemContent = "You control a macOS app on the user's behalf. Choose exactly one operation and exactly one target element to make progress on the goal. Respond only in the required format.";
  const userContent = buildSyntheticUserContent();
  const prompt =
    framing.template.systemPrefix +
    systemContent +
    framing.template.systemToUser +
    userContent +
    framing.template.userSuffixToAssistant +
    framing.thinkBlock +
    "Operation:";

  const grammar = buildGrammar(OPERATION_LABELS, targetPageLabels);
  const requestBody = {
    prompt,
    grammar,
    n_predict: 16,
    temperature: 0,
    n_probs: 128,
    post_sampling_probs: false,
    cache_prompt: true,
    stream: false,
  };

  const res = await fetchJSON(`${base}/completion`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(requestBody),
  });
  if (!check(res.ok, `POST /completion returned ${res.status}: ${res.rawText.slice(0, 500)}`)) {
    return null;
  }

  const probs = res.body?.completion_probabilities;
  if (!check(Array.isArray(probs) && probs.length >= 2, `/completion completion_probabilities has length ${Array.isArray(probs) ? probs.length : "non-array"}, expected >= 2`)) {
    return null;
  }

  const opPieces = OPERATION_LABELS.map(labelPiece);
  const tgtPieces = targetPageLabels.map(labelPiece);

  const opEntry = probs[0];
  check(opPieces.includes(opEntry.token), `/completion first entry token ${JSON.stringify(opEntry.token)} is not an operation label piece`);

  // The grammar's literal "\nTarget:" span generates as several intermediate
  // steps ("\n", "Target", ":"), and once the grammar's root production is
  // fully matched, this build samples one further forced-stop step (an
  // empty-text entry) before it stops generating. Verified empirically against
  // the pinned build: opHead + 3 literal tokens + targetHead + 1 trailing stop
  // entry for this grammar shape. See locateTargetHead for the exact rule.
  const located = locateTargetHead(probs, tgtPieces);
  if (!check(located.error === undefined, `/completion target head: ${located.error}`)) {
    return null;
  }
  const tgtEntry = located.entry;

  const opTopTokens = new Set((opEntry.top_logprobs ?? []).map((e) => e.token));
  const tgtTopTokens = new Set((tgtEntry.top_logprobs ?? []).map((e) => e.token));

  for (const piece of opPieces) {
    check(opTopTokens.has(piece), `/completion op-head top_logprobs is missing operation label piece ${JSON.stringify(piece)}`);
  }
  for (const piece of tgtPieces) {
    check(tgtTopTokens.has(piece), `/completion target-head top_logprobs is missing target label piece ${JSON.stringify(piece)}`);
  }

  const nonLabelAtOpHead = (opEntry.top_logprobs ?? []).some((e) => !opPieces.includes(e.token));
  check(nonLabelAtOpHead, `/completion op-head top_logprobs contains only label tokens; expected at least one non-label token, proving the distribution is raw and not grammar-masked`);

  const opDistribution = renormalizeOverLabels(opEntry.top_logprobs ?? [], opPieces);
  const tgtDistribution = renormalizeOverLabels(tgtEntry.top_logprobs ?? [], tgtPieces);

  const opArgmax = [...opDistribution.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  const tgtArgmax = [...tgtDistribution.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];

  check(opArgmax === opEntry.token, `op-head renormalized argmax ${JSON.stringify(opArgmax)} does not equal generated token ${JSON.stringify(opEntry.token)}`);
  check(tgtArgmax === tgtEntry.token, `target-head renormalized argmax ${JSON.stringify(tgtArgmax)} does not equal generated token ${JSON.stringify(tgtEntry.token)}`);

  const opSum = [...opDistribution.values()].reduce((a, b) => a + b, 0);
  const tgtSum = [...tgtDistribution.values()].reduce((a, b) => a + b, 0);
  check(Math.abs(opSum - 1) <= 1e-6, `op-head renormalized probabilities sum to ${opSum}, expected 1 +/- 1e-6`);
  check(Math.abs(tgtSum - 1) <= 1e-6, `target-head renormalized probabilities sum to ${tgtSum}, expected 1 +/- 1e-6`);

  return { requestBody, response: { completion_probabilities: probs, content: res.body?.content ?? null } };
}

function percentile50(sortedMs) {
  const mid = Math.floor(sortedMs.length / 2);
  if (sortedMs.length % 2 === 1) {
    return sortedMs[mid];
  }
  return (sortedMs[mid - 1] + sortedMs[mid]) / 2;
}

async function measureP50(base, framing, targetPageLabels, repeats) {
  const timingsMs = [];
  for (let i = 0; i < repeats; i += 1) {
    const start = performance.now();
    // eslint-disable-next-line no-await-in-loop
    await runSyntheticCompletionQuiet(base, framing, targetPageLabels);
    timingsMs.push(performance.now() - start);
  }
  timingsMs.sort((a, b) => a - b);
  return percentile50(timingsMs);
}

// Same request as runSyntheticCompletion but without re-pushing assertion
// failures (used only for the informational timing loop in step 6).
async function runSyntheticCompletionQuiet(base, framing, targetPageLabels) {
  const systemContent = "You control a macOS app on the user's behalf. Choose exactly one operation and exactly one target element to make progress on the goal. Respond only in the required format.";
  const userContent = buildSyntheticUserContent();
  const prompt =
    framing.template.systemPrefix +
    systemContent +
    framing.template.systemToUser +
    userContent +
    framing.template.userSuffixToAssistant +
    framing.thinkBlock +
    "Operation:";
  const grammar = buildGrammar(OPERATION_LABELS, targetPageLabels);
  await fetchJSON(`${base}/completion`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      prompt,
      grammar,
      n_predict: 16,
      temperature: 0,
      n_probs: 128,
      post_sampling_probs: false,
      cache_prompt: true,
      stream: false,
    }),
  });
}

async function main() {
  const { url, model, writePin } = parseArgs(process.argv.slice(2));
  const base = url.replace(/\/$/, "");
  const entry = loadManifestEntry(model);

  await checkHealth(base);
  const { buildInfo } = await checkProps(base, entry.filename);
  const labelTokens = await checkLabelsSingleToken(base);
  const framing = await checkTemplateFraming(base, entry.chatTemplateKwargs ?? {});

  const targetPageLabels = TARGET_LABELS.slice(0, 5); // A-E, matches the 5 synthetic candidates

  let completionResult = null;
  let p50Ms = null;
  if (framing) {
    completionResult = await runSyntheticCompletion(base, framing, targetPageLabels);
    if (completionResult) {
      p50Ms = await measureP50(base, framing, targetPageLabels, 5);
    }
  }

  if (failures.length > 0) {
    for (const message of failures) {
      process.stderr.write(`check-readout.mjs: FAIL: ${message}\n`);
    }
    process.exit(1);
  }

  process.stdout.write("check-readout.mjs: all readout assertions passed.\n");

  if (writePin) {
    const pin = {
      llamaCppVersion: buildInfo ?? "unknown",
      model,
      labelsSingleToken: true,
      probabilitySemantics: "pre_sampling_logprobs_renormalized_over_labels",
      template: framing.template,
      operationLabels: OPERATION_LABELS,
      targetLabels: targetPageLabels,
      request: completionResult.requestBody,
      response: completionResult.response,
      responseShapeNote: RESPONSE_SHAPE_NOTE,
      p50Ms,
    };
    mkdirSync(path.dirname(pinPath), { recursive: true });
    writeFileSync(pinPath, `${JSON.stringify(pin, null, 2)}\n`, "utf8");
    process.stdout.write(`check-readout.mjs: wrote ${pinPath}\n`);
  }
}

// Run only as a script, so tests can import locateTargetHead without probing a server.
if (invokedAsScript(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`check-readout.mjs: unexpected error: ${error.stack ?? error}\n`);
    process.exit(1);
  });
}
