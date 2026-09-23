// Scoring, aggregation, tau selection, and summary building for the decision-model eval.
//
// Pure functions over dataset items (eval-dataset.mjs schema) and DecisionModelEval output lines. The committed
// summary is built from whitelisted numeric/enum fields only, so goal, row, and rendered text can never leak into it.
// Node built-ins only.

import { TARGETED } from './eval-dataset.mjs';

export const GATES = Object.freeze([
  Object.freeze({ name: 'top1', threshold: 0.8, cmp: '>=' }),
  Object.freeze({ name: 'auroc', threshold: 0.7, cmp: '>=' }),
  Object.freeze({ name: 'prunedTargetRate', threshold: 0.05, cmp: '<=' }),
  Object.freeze({ name: 'p50Ms', threshold: 1500, cmp: '<' }),
]);

const PRUNE_CAUSES = new Set(['disabled', 'menu_bar', 'scroll_bar_part', 'window_chrome', 'duplicate_close', 'overflow', 'not_actionable']);

function round4(value) {
  return value === null ? null : Number(value.toFixed(4));
}

function ratio(numerator, denominator) {
  return denominator === 0 ? null : round4(numerator / denominator);
}

function finiteOrNull(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

/** Mann-Whitney AUROC; ties count 0.5; returns null when either class is empty. */
export function auroc(scores, positives) {
  if (!Array.isArray(scores) || !Array.isArray(positives) || scores.length !== positives.length) {
    throw new TypeError('auroc: scores and positives must be arrays of equal length');
  }
  const pos = scores.filter((_, i) => positives[i] === true);
  const neg = scores.filter((_, i) => positives[i] !== true);
  if (pos.length === 0 || neg.length === 0) {
    return null;
  }
  let wins = 0;
  for (const p of pos) {
    for (const n of neg) {
      if (p > n) wins += 1;
      else if (p === n) wins += 0.5;
    }
  }
  return wins / (pos.length * neg.length);
}

/** Nearest-rank percentile, p in (0, 100]; returns null for an empty array. */
export function percentile(values, p) {
  if (!(p > 0 && p <= 100)) {
    throw new RangeError('percentile: p must be in (0, 100]');
  }
  if (!Array.isArray(values) || values.length === 0) {
    return null;
  }
  const sorted = [...values].sort((a, b) => a - b);
  const rank = Math.ceil((p / 100) * sorted.length);
  return sorted[Math.max(rank, 1) - 1];
}

/**
 * Scores one harness output line against its dataset item. See the phase 06 Signature for field semantics.
 * Throws when the line does not belong to the item or lacks the pruning fields.
 */
export function scoreItem(item, line) {
  if (line === null || typeof line !== 'object' || line.id !== item.id) {
    throw new Error(`scoreItem: line id ${JSON.stringify(line?.id)} does not match item id ${JSON.stringify(item.id)}`);
  }
  if (!Array.isArray(line.offered_indices) || line.dropped === null || typeof line.dropped !== 'object') {
    throw new Error(`scoreItem: line ${item.id} lacks offered_indices or dropped`);
  }
  const gt = item.groundTruth;
  const targeted = TARGETED.has(gt.operation);
  const error = typeof line.error === 'string' ? line.error : null;
  const advice = error === null && line.advice !== null && typeof line.advice === 'object' ? line.advice : null;

  const opCorrect = advice !== null && advice.operation === gt.operation;
  const indexMatches = advice !== null && advice.element_index === gt.elementIndex;
  const prunedTarget = targeted ? !line.offered_indices.includes(gt.elementIndex) : null;

  return {
    id: item.id,
    split: item.split,
    source: item.source,
    targeted,
    correct: opCorrect && (!targeted || indexMatches),
    opCorrect,
    targetCorrect: targeted ? indexMatches : null,
    prunedTarget,
    pruneCause: prunedTarget ? (line.dropped[String(gt.elementIndex)] ?? 'not_actionable') : null,
    margin: advice === null ? null : finiteOrNull(advice.margin),
    latencyMs: advice === null ? null : finiteOrNull(advice.latency_ms),
    error,
  };
}

/** Aggregates scored items. Errors count as incorrect in top1 and are excluded from auroc and latency. */
export function aggregate(scored) {
  const n = scored.length;
  const targeted = scored.filter((row) => row.targeted);
  const withMargin = scored.filter((row) => row.error === null && row.margin !== null);
  const latencies = scored.filter((row) => row.error === null && row.latencyMs !== null).map((row) => row.latencyMs);

  const prunedByCause = {};
  for (const row of targeted) {
    if (row.prunedTarget) {
      prunedByCause[row.pruneCause] = (prunedByCause[row.pruneCause] ?? 0) + 1;
    }
  }
  const aurocValue = auroc(withMargin.map((row) => row.margin), withMargin.map((row) => row.correct));

  return {
    n,
    top1: ratio(scored.filter((row) => row.correct).length, n),
    opAccuracy: ratio(scored.filter((row) => row.opCorrect).length, n),
    targetAccuracy: ratio(targeted.filter((row) => row.targetCorrect).length, targeted.length),
    prunedTargetRate: ratio(targeted.filter((row) => row.prunedTarget).length, targeted.length),
    prunedByCause,
    auroc: aurocValue === null ? null : round4(aurocValue),
    p50Ms: percentile(latencies, 50),
    p95Ms: percentile(latencies, 95),
    errors: scored.filter((row) => row.error !== null).length,
  };
}

/**
 * Precision and coverage of "follow when margin >= t". Coverage is over every scored item (errors included, since a
 * host cannot follow an error); precision is over the followed items and is null when none are followed.
 */
export function precisionCoverageAt(scored, t) {
  const followed = scored.filter((row) => row.error === null && row.margin !== null && row.margin >= t);
  return {
    precision: ratio(followed.filter((row) => row.correct).length, followed.length),
    coverage: scored.length === 0 ? 0 : round4(followed.length / scored.length),
  };
}

/** Smallest margin threshold reaching both floors; {tau: 1.0, precision: null, coverage: 0} when none does. */
export function selectTau(scored, { minPrecision = 0.9, minCoverage = 0.1 } = {}) {
  const margins = scored.filter((row) => row.error === null && row.margin !== null).map((row) => row.margin);
  const candidates = [...new Set([...margins, 1.0])].sort((a, b) => a - b);
  for (const t of candidates) {
    const { precision, coverage } = precisionCoverageAt(scored, t);
    if (precision !== null && precision >= minPrecision && coverage >= minCoverage) {
      return { tau: t, precision, coverage };
    }
  }
  return { tau: 1.0, precision: null, coverage: 0 };
}

/** Rounds tau up to 2 decimals, capped at 1; the 1e-9 guard keeps 0.57 (56.999... after scaling) at 0.57. */
export function roundTauUp(value) {
  return Math.min(1, Math.ceil(value * 100 - 1e-9) / 100);
}

function numberOrNull(value) {
  return finiteOrNull(value);
}

function stringOrNull(value) {
  return typeof value === 'string' ? value : null;
}

function countMap(value) {
  const out = {};
  if (value !== null && typeof value === 'object') {
    for (const [key, count] of Object.entries(value)) {
      if (Number.isInteger(count)) out[key] = count;
    }
  }
  return out;
}

function pickMetrics(metrics) {
  const m = metrics ?? {};
  const prunedByCause = {};
  for (const [cause, count] of Object.entries(countMap(m.prunedByCause))) {
    if (PRUNE_CAUSES.has(cause)) prunedByCause[cause] = count;
  }
  return {
    n: Number.isInteger(m.n) ? m.n : 0,
    top1: numberOrNull(m.top1),
    opAccuracy: numberOrNull(m.opAccuracy),
    targetAccuracy: numberOrNull(m.targetAccuracy),
    prunedTargetRate: numberOrNull(m.prunedTargetRate),
    prunedByCause,
    auroc: numberOrNull(m.auroc),
    p50Ms: numberOrNull(m.p50Ms),
    p95Ms: numberOrNull(m.p95Ms),
    errors: Number.isInteger(m.errors) ? m.errors : 0,
  };
}

function gatePasses(value, threshold, cmp) {
  if (value === null) return false;
  if (cmp === '>=') return value >= threshold;
  if (cmp === '<=') return value <= threshold;
  if (cmp === '<') return value < threshold;
  throw new Error(`unknown gate comparator ${cmp}`);
}

/** Builds the committed summary object from whitelisted fields only; never copies goal, row, or rendered text. */
/** What the reported p50/p95 cover, so the latency gate is not read as the cost of a live call. */
export const LATENCY_SCOPE_NOTE = 'p50/p95 are the advisor latency_ms of each item: candidate pruning plus the model '
  + 'round trip. They exclude the accessibility refresh and rendering that the live decide_next_action call performs '
  + 'first (the cost of a get_app_state), and the MCP and app-agent hops, so a live call takes longer.';

/** Distinct snapshots per split. Items taken from one screen are correlated, so this is the effective sample size. */
export function snapshotsBySplit(items) {
  const sets = {};
  for (const item of Array.isArray(items) ? items : []) {
    if (typeof item?.split !== 'string' || typeof item?.snapshotId !== 'string') continue;
    (sets[item.split] ??= new Set()).add(item.snapshotId);
  }
  return Object.fromEntries(Object.entries(sets).map(([split, ids]) => [split, ids.size]));
}

/** How many screens the test metrics rest on, stated next to them so they are not read as n independent items. */
export function testClusteringNote(bySplit, snapshotCounts) {
  const items = Number.isInteger(bySplit?.test) ? bySplit.test : 0;
  const screens = Number.isInteger(snapshotCounts?.test) ? snapshotCounts.test : 0;
  return `Test metrics come from ${items} items on only ${screens} screens (the split is by snapshot); items from one `
    + 'screen are correlated, so the test AUROC and the test precision at tau are weaker evidence than the item count suggests.';
}

/**
 * States, from the tuning log itself, whether any pruning tuning run could have shown test metrics. A round counts as
 * dev-only only when the log records `split: 'dev'`, which eval-run.mjs writes now that it runs tuning rounds on the
 * dev split alone; older rows ran over every split.
 */
export function tuningIsolationNote(tuningRounds) {
  const rounds = Array.isArray(tuningRounds) ? tuningRounds : [];
  const base = 'Gates are judged on the test split; tau was selected on the dev split only.';
  if (rounds.length === 0) return `${base} No pruning tuning rounds were recorded.`;
  const exposed = rounds.filter((round) => round?.split !== 'dev').map((round) => round?.round);
  if (exposed.length === 0) {
    return `${base} Every pruning tuning round ran with --split dev, so no tuning run scored or printed test items.`;
  }
  return `${base} Pruning tuning rounds ${exposed.join(', ')} were compared on their dev metrics, but they ran over `
    + '--split all, so their reports also printed test aggregates.';
}

export function buildSummary({ meta, dataset, metricsBySplit, tau, tauOnTest, tuningRounds, notes }) {
  const metrics = {
    all: pickMetrics(metricsBySplit?.all),
    dev: pickMetrics(metricsBySplit?.dev),
    test: pickMetrics(metricsBySplit?.test),
  };
  return {
    schemaVersion: 1,
    generatedAt: stringOrNull(meta?.generatedAt),
    model: { key: stringOrNull(meta?.model?.key), sha256: stringOrNull(meta?.model?.sha256) },
    llamaCpp: { version: stringOrNull(meta?.llamaCpp?.version) },
    hardware: { chip: stringOrNull(meta?.hardware?.chip), memoryGB: numberOrNull(meta?.hardware?.memoryGB) },
    dataset: {
      n: Number.isInteger(dataset?.n) ? dataset.n : 0,
      fixture: Number.isInteger(dataset?.fixture) ? dataset.fixture : 0,
      real: Number.isInteger(dataset?.real) ? dataset.real : 0,
      bySplit: countMap(dataset?.bySplit),
      snapshotsBySplit: countMap(dataset?.snapshotsBySplit),
      byOperation: countMap(dataset?.byOperation),
    },
    metrics,
    tau: {
      value: roundTauUp(numberOrNull(tau?.tau) ?? 1.0),
      devPrecision: numberOrNull(tau?.precision),
      devCoverage: numberOrNull(tau?.coverage),
      testPrecision: numberOrNull(tauOnTest?.precision),
      testCoverage: numberOrNull(tauOnTest?.coverage),
    },
    gates: GATES.map(({ name, threshold, cmp }) => {
      const value = metrics.test[name];
      return { name, threshold, cmp, value, split: 'test', pass: gatePasses(value, threshold, cmp) };
    }),
    tuningRounds: (Array.isArray(tuningRounds) ? tuningRounds : []).map((round) => ({
      round: Number.isInteger(round?.round) ? round.round : null,
      note: stringOrNull(round?.note),
      devTop1: numberOrNull(round?.devTop1),
      devPrunedTargetRate: numberOrNull(round?.devPrunedTargetRate),
    })),
    notes: (Array.isArray(notes) ? notes : []).filter((note) => typeof note === 'string'),
  };
}
