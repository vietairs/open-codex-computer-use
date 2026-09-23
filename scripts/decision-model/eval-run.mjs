#!/usr/bin/env node
// Runs the decision-model eval: replays every dataset item through the shipped Swift pipeline (DecisionModelEval),
// scores the results, and prints per-split aggregates. Gates are reported, never enforced.
//
//   node scripts/decision-model/eval-run.mjs [--url http://127.0.0.1:<port>] [--prune-only] [--split dev|test|all]
//        [--write-summary] [--tuning-round <n> --tuning-note <text>]
//
// Tuning rounds run over --split dev only, so a tuning run never scores, prints, or stores a test item. The report
// and the results file cover exactly the selected split.
//
// Raw harness lines contain real screen text, so they go only to the gitignored artifacts/decision-eval/.
// The committed summary.json is built by eval-metrics.mjs from whitelisted numeric fields.
// Exit: 0 completed run (any gate outcome); 1 harness/build failure; 2 dataset validation failure; 64 bad usage.
// Node built-ins only.

import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync, openSync, readSync, closeSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadDataset, validateItem } from './eval-dataset.mjs';
import {
  LATENCY_SCOPE_NOTE, aggregate, buildSummary, percentile, precisionCoverageAt, roundTauUp, scoreItem, selectTau,
  snapshotsBySplit, testClusteringNote, tuningIsolationNote,
} from './eval-metrics.mjs';
import { invokedAsScript } from './run-as-script.mjs';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, '..', '..');
const evalDataDir = join(scriptDir, 'eval-data');
const artifactsDir = join(repoRoot, 'artifacts', 'decision-eval');
const tuningLogPath = join(artifactsDir, 'tuning-log.json');
const summaryPath = join(evalDataDir, 'summary.json');
const advisorPath = join(repoRoot, 'packages/OpenComputerUseKit/Sources/OpenComputerUseKit/DecisionAdvisor.swift');
const sidecarLogPath = join(homedir(), 'Library/Application Support/OpenComputerUse/decision-model/logs/llama-server.log');
const SPLITS = ['all', 'dev', 'test'];
const WARMUP_COUNT = 3;

export class UsageError extends Error {}

export function parseArgs(argv) {
  const options = { url: null, pruneOnly: false, split: 'all', writeSummary: false, tuningRound: null, tuningNote: null };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const value = () => {
      if (i + 1 >= argv.length) throw new UsageError(`${arg} requires a value`);
      i += 1;
      return argv[i];
    };
    if (arg === '--prune-only') options.pruneOnly = true;
    else if (arg === '--write-summary') options.writeSummary = true;
    else if (arg === '--url') options.url = value();
    else if (arg === '--split') options.split = value();
    else if (arg === '--tuning-round') options.tuningRound = value();
    else if (arg === '--tuning-note') options.tuningNote = value();
    else throw new UsageError(`unknown argument ${arg}`);
  }
  if (!SPLITS.includes(options.split)) throw new UsageError('--split must be dev, test, or all');
  if ((options.tuningRound === null) !== (options.tuningNote === null)) {
    throw new UsageError('--tuning-round and --tuning-note go together');
  }
  if (options.tuningRound !== null) {
    if (!/^[0-3]$/.test(options.tuningRound)) throw new UsageError('--tuning-round must be 0..3');
    options.tuningRound = Number(options.tuningRound);
    if (options.pruneOnly || options.split !== 'dev') {
      throw new UsageError('--tuning-round needs a full run over --split dev, so tuning never sees test metrics');
    }
  }
  if (options.writeSummary && (options.pruneOnly || options.split !== 'all')) {
    throw new UsageError('--write-summary needs a full run over --split all');
  }
  options.url ??= `http://127.0.0.1:${39000 + (process.getuid() % 1000)}`;
  return options;
}

/** Loads fixture items plus local real captures, validates each, and returns them in dataset order. */
function loadAllItems() {
  const sources = [{ items: join(evalDataDir, 'fixture-items.jsonl'), snapshots: join(evalDataDir, 'fixture-snapshots') }];
  const realItems = join(artifactsDir, 'items-real.jsonl');
  if (existsSync(realItems)) sources.push({ items: realItems, snapshots: join(artifactsDir, 'snapshots') });

  const entries = [];
  const errors = [];
  const seen = new Set();
  for (const source of sources) {
    const { items, snapshots } = loadDataset(source.items, source.snapshots);
    for (const item of items) {
      const snapshot = snapshots.get(item?.snapshotId);
      for (const error of validateItem(item, snapshot)) errors.push(`${item?.id ?? '?'}: ${error}`);
      if (seen.has(item?.id)) errors.push(`${item.id}: duplicate id`);
      seen.add(item?.id);
      entries.push({ item, snapshot });
    }
  }
  return { entries, errors };
}

function harnessInput(id, item, snapshot) {
  return JSON.stringify({
    id, goal: item.goal, app: snapshot.app ?? '', renderedFull: snapshot.renderedFull, renderedCompact: snapshot.renderedCompact,
  });
}

function buildHarness() {
  const result = spawnSync('swift', ['build', '--product', 'DecisionModelEval'], { cwd: repoRoot, stdio: ['ignore', 2, 2] });
  if (result.status !== 0) throw new Error(`swift build --product DecisionModelEval failed (${result.status ?? result.error})`);
}

/** Spawns the harness once and returns its parsed output lines in input order. */
function runHarness(mode, inputLines) {
  const binary = join(repoRoot, '.build', 'debug', 'DecisionModelEval');
  const args = mode.pruneOnly ? ['--prune-only'] : ['--url', mode.url];
  return new Promise((resolvePromise, reject) => {
    const child = spawn(binary, args, { cwd: repoRoot, stdio: ['pipe', 'pipe', 'inherit'] });
    const chunks = [];
    child.on('error', reject);
    child.stdout.on('data', (chunk) => chunks.push(chunk));
    child.on('close', (code) => {
      if (code !== 0) {
        reject(new Error(`DecisionModelEval exited with ${code}`));
        return;
      }
      const lines = Buffer.concat(chunks).toString('utf8').split('\n').filter((line) => line.trim() !== '');
      try {
        resolvePromise(lines.map((line) => JSON.parse(line)));
      } catch (error) {
        reject(new Error(`DecisionModelEval printed a non-JSON line: ${error.message}`));
      }
    });
    child.stdin.on('error', reject);
    child.stdin.end(`${inputLines.join('\n')}\n`);
  });
}

function timestamp(date = new Date()) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}-${pad(date.getHours())}${pad(date.getMinutes())}`;
}

function sidecarLogSize() {
  return existsSync(sidecarLogPath) ? statSync(sidecarLogPath).size : null;
}

/** llama-server per-request prompt timings appended to its log since `offset` (no prompt text is read out). */
function promptTimingsSince(offset) {
  if (offset === null || !existsSync(sidecarLogPath)) return null;
  const size = statSync(sidecarLogPath).size;
  if (size <= offset) return null;
  const buffer = Buffer.alloc(size - offset);
  const fd = openSync(sidecarLogPath, 'r');
  try {
    readSync(fd, buffer, 0, buffer.length, offset);
  } finally {
    closeSync(fd);
  }
  const timings = [];
  for (const match of buffer.toString('utf8').matchAll(/prompt eval time =\s*([\d.]+) ms \/\s*(\d+) tokens/g)) {
    timings.push({ promptMs: Number(match[1]), promptN: Number(match[2]) });
  }
  if (timings.length === 0) return null;
  // Requests with more than 8 new prompt tokens are prefills; the rest are the second head's cached extension.
  const prefills = timings.filter((t) => t.promptN > 8);
  return {
    requests: timings.length,
    prefills: prefills.length,
    promptNP50: percentile(prefills.map((t) => t.promptN), 50),
    promptNP95: percentile(prefills.map((t) => t.promptN), 95),
    promptMsP50: percentile(prefills.map((t) => t.promptMs), 50),
    promptMsP95: percentile(prefills.map((t) => t.promptMs), 95),
  };
}

function countBy(values) {
  const counts = {};
  for (const value of values) counts[value] = (counts[value] ?? 0) + 1;
  return counts;
}

function readTuningLog() {
  if (!existsSync(tuningLogPath)) return [];
  const parsed = JSON.parse(readFileSync(tuningLogPath, 'utf8'));
  if (!Array.isArray(parsed)) throw new Error(`${tuningLogPath} is not a JSON array`);
  return parsed;
}

function recordTuningRound(round, note, devMetrics, resultsFile) {
  const log = readTuningLog().filter((entry) => entry.round !== round);
  log.push({
    round, note, split: 'dev', devTop1: devMetrics.top1, devPrunedTargetRate: devMetrics.prunedTargetRate, resultsFile,
    recordedAt: new Date().toISOString(),
  });
  log.sort((a, b) => a.round - b.round);
  writeFileSync(tuningLogPath, `${JSON.stringify(log, null, 2)}\n`);
}

function sysctl(name) {
  const result = spawnSync('/usr/sbin/sysctl', ['-n', name], { encoding: 'utf8' });
  if (result.status !== 0) throw new Error(`sysctl -n ${name} failed`);
  return result.stdout.trim();
}

function advisorLiteral() {
  const match = readFileSync(advisorPath, 'utf8').match(/static let recommendedMinMargin: Double = ([\d.]+)/);
  return match ? Number(match[1]) : null;
}

function writeSummary({ entries, scored, metricsBySplit, timings }) {
  const manifest = JSON.parse(readFileSync(join(scriptDir, 'model-manifest.json'), 'utf8'));
  const pin = JSON.parse(readFileSync(join(scriptDir, 'fixtures', 'readout-pin.json'), 'utf8'));
  const dev = scored.filter((row) => row.split === 'dev');
  const test = scored.filter((row) => row.split === 'test');
  const picked = selectTau(dev);
  // The shipped literal is tau rounded up to 2 decimals; report dev and test precision/coverage at that exact value.
  const tauValue = roundTauUp(picked.tau);
  const devAt = precisionCoverageAt(dev, tauValue);
  const testAt = precisionCoverageAt(test, tauValue);
  const chip = sysctl('machdep.cpu.brand_string');
  const memoryGB = Math.round(Number(sysctl('hw.memsize')) / 2 ** 30);
  const timingNote = timings === null
    ? 'llama-server prompt timings were not available from the sidecar log.'
    : `llama-server timings over ${timings.prefills} prefill requests (of ${timings.requests}): prompt_n p50 ${timings.promptNP50} / p95 ${timings.promptNP95} tokens, prompt_ms p50 ${timings.promptMsP50} / p95 ${timings.promptMsP95}; cache_prompt reuses shared prefixes between consecutive items.`;
  const bySplit = countBy(entries.map(({ item }) => item.split));
  const snapshotCounts = snapshotsBySplit(entries.map(({ item }) => item));
  const tuningRounds = readTuningLog();
  const summary = buildSummary({
    meta: {
      generatedAt: new Date().toISOString(),
      model: { key: manifest.active, sha256: manifest.models[manifest.active]?.sha256 },
      llamaCpp: { version: pin.llamaCppVersion },
      hardware: { chip, memoryGB },
    },
    dataset: {
      n: entries.length,
      fixture: entries.filter(({ item }) => item.source === 'fixture').length,
      real: entries.filter(({ item }) => item.source === 'real').length,
      bySplit,
      snapshotsBySplit: snapshotCounts,
      byOperation: countBy(entries.map(({ item }) => item.groundTruth.operation)),
    },
    metricsBySplit,
    tau: { tau: tauValue, precision: devAt.precision, coverage: devAt.coverage },
    tauOnTest: testAt,
    tuningRounds,
    notes: [
      `p50/p95 latency is an optimistic bound (${chip}, ${memoryGB} GB); the p50 gate is specified for a 16 GB M-series machine.`,
      LATENCY_SCOPE_NOTE,
      timingNote,
      'P3 step-count gate not measured: it needs agent-in-the-loop A/B runs.',
      tuningIsolationNote(tuningRounds),
      testClusteringNote(bySplit, snapshotCounts),
      `tau selection: smallest dev margin with precision >= 0.90 and coverage >= 0.10 (selected ${picked.tau}), rounded up to 2 decimals; 1.0 means never auto-follow.`,
    ],
  });
  writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`);
  const literal = advisorLiteral();
  return { summary, literal, literalMatches: literal === summary.tau.value };
}

function pruneView(metrics) {
  return { n: metrics.n, prunedTargetRate: metrics.prunedTargetRate, prunedByCause: metrics.prunedByCause };
}

async function main(argv) {
  let options;
  try {
    options = parseArgs(argv);
  } catch (error) {
    if (!(error instanceof UsageError)) throw error;
    process.stderr.write(`eval-run: ${error.message}\n`);
    return 64;
  }

  const { entries, errors } = loadAllItems();
  if (errors.length > 0) {
    process.stderr.write(`eval-run: dataset validation failed (${errors.length} errors):\n${errors.join('\n')}\n`);
    return 2;
  }
  const selected = entries.filter(({ item }) => options.split === 'all' || item.split === options.split);
  const warmups = entries.filter(({ item }) => item.source === 'fixture').slice(0, WARMUP_COUNT);

  buildHarness();
  mkdirSync(artifactsDir, { recursive: true });
  const logOffset = options.pruneOnly ? null : sidecarLogSize();
  const inputs = [
    ...warmups.map(({ item, snapshot }) => harnessInput(`warmup-${item.id}`, item, snapshot)),
    ...selected.map(({ item, snapshot }) => harnessInput(item.id, item, snapshot)),
  ];
  const outputs = await runHarness(options, inputs);
  if (outputs.length !== inputs.length) {
    throw new Error(`DecisionModelEval returned ${outputs.length} lines for ${inputs.length} inputs`);
  }
  const lines = outputs.slice(warmups.length);
  const resultsFile = join(artifactsDir, `results-${timestamp()}${options.pruneOnly ? '-prune' : ''}.jsonl`);
  writeFileSync(resultsFile, lines.map((line) => JSON.stringify(line)).join('\n') + '\n');

  const scored = selected.map(({ item }, i) => scoreItem(item, lines[i]));
  // Only the selected split is aggregated, so a dev-only run never labels dev numbers as "all".
  const metricsBySplit = options.split === 'all'
    ? {
      all: aggregate(scored),
      dev: aggregate(scored.filter((row) => row.split === 'dev')),
      test: aggregate(scored.filter((row) => row.split === 'test')),
    }
    : { [options.split]: aggregate(scored) };

  const report = { mode: options.pruneOnly ? 'prune-only' : 'advise', resultsFile, splits: {} };
  for (const [split, metrics] of Object.entries(metricsBySplit)) {
    report.splits[split] = options.pruneOnly ? pruneView(metrics) : metrics;
  }
  if (!options.pruneOnly) {
    const timings = promptTimingsSince(logOffset);
    report.promptTimings = timings;
    if (options.tuningRound !== null) {
      recordTuningRound(options.tuningRound, options.tuningNote, metricsBySplit.dev, resultsFile);
    }
    if (options.writeSummary) {
      const { summary, literal, literalMatches } = writeSummary({ entries: selected, scored, metricsBySplit, timings });
      report.summary = { path: summaryPath, tau: summary.tau, gates: summary.gates, advisorLiteral: literal, literalMatches };
      if (!literalMatches) {
        process.stderr.write(`eval-run: DecisionAdvisor.recommendedMinMargin (${literal}) != summary tau (${summary.tau.value}); update the literal.\n`);
      }
    }
  }
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  return 0;
}

// Run only as a script, so tests can import parseArgs without starting an eval.
if (invokedAsScript(import.meta.url)) {
  main(process.argv.slice(2)).then(
    (code) => { process.exitCode = code; },
    (error) => {
      process.stderr.write(`eval-run: ${error.message}\n`);
      process.exitCode = 1;
    },
  );
}
