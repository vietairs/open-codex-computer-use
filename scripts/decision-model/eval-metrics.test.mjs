// Tests-first for scripts/decision-model/eval-metrics.mjs.
// Written before the implementation exists; must fail (module-not-found) until
// eval-metrics.mjs is implemented to its Signature.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  GATES, LATENCY_SCOPE_NOTE, aggregate, auroc, buildSummary, percentile, scoreItem, selectTau, snapshotsBySplit,
  testClusteringNote, tuningIsolationNote,
} from './eval-metrics.mjs';

const CANARY = 'CANARY-PII-7f3a';

function makeItem({ id = 'item-1', operation = 'click', elementIndex = 3, split = 'dev', source = 'fixture', goal = 'Press the button' } = {}) {
  return {
    schemaVersion: 1,
    id,
    snapshotId: 'fixture-01',
    source,
    goal,
    groundTruth: { operation, elementIndex },
    split,
    labeling: {},
  };
}

function makeLine({
  id = 'item-1',
  operation = 'click',
  elementIndex = 3,
  margin = 0.5,
  latencyMs = 400,
  offered = [1, 2, 3],
  dropped = {},
  error = null,
  rowText = 'button Save',
} = {}) {
  return {
    id,
    offered_indices: offered,
    dropped,
    actionable_count: offered.length + Object.keys(dropped).length,
    advice: error === null
      ? {
          operation,
          element_index: elementIndex,
          margin,
          latency_ms: latencyMs,
          chosen_row_text: rowText,
          target_distribution: [{ element_index: elementIndex, probability: 0.9, row_text: rowText }],
        }
      : null,
    error,
    wall_ms: latencyMs + 5,
  };
}

test('GATES lists the four exec-plan gates in order', () => {
  assert.deepEqual(GATES.map((gate) => [gate.name, gate.threshold, gate.cmp]), [
    ['top1', 0.8, '>='],
    ['auroc', 0.7, '>='],
    ['prunedTargetRate', 0.05, '<='],
    ['p50Ms', 1500, '<'],
  ]);
  assert.ok(Object.isFrozen(GATES));
});

test('auroc: perfect, reversed, tied, and single-class inputs', () => {
  assert.equal(auroc([0.9, 0.8, 0.2, 0.1], [true, true, false, false]), 1);
  assert.equal(auroc([0.9, 0.8, 0.2, 0.1], [false, false, true, true]), 0);
  assert.equal(auroc([0.5, 0.5], [true, false]), 0.5);
  assert.equal(auroc([1], [true]), null);
  assert.equal(auroc([], []), null);
});

test('percentile: nearest rank and empty input', () => {
  const values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  assert.equal(percentile(values, 50), 5);
  assert.equal(percentile(values, 95), 10);
  assert.equal(percentile([10, 1, 5], 50), 5, 'unsorted input is sorted first');
  assert.equal(percentile([], 50), null);
});

test('scoreItem: correct click', () => {
  const scored = scoreItem(makeItem(), makeLine());
  assert.equal(scored.id, 'item-1');
  assert.equal(scored.split, 'dev');
  assert.equal(scored.source, 'fixture');
  assert.equal(scored.targeted, true);
  assert.equal(scored.correct, true);
  assert.equal(scored.opCorrect, true);
  assert.equal(scored.targetCorrect, true);
  assert.equal(scored.prunedTarget, false);
  assert.equal(scored.pruneCause, null);
  assert.equal(scored.margin, 0.5);
  assert.equal(scored.latencyMs, 400);
  assert.equal(scored.error, null);
});

test('scoreItem: right operation with the wrong index is incorrect', () => {
  const scored = scoreItem(makeItem(), makeLine({ elementIndex: 2 }));
  assert.equal(scored.correct, false);
  assert.equal(scored.opCorrect, true);
  assert.equal(scored.targetCorrect, false);
});

test('scoreItem: an untargeted operation ignores the advised index', () => {
  const item = makeItem({ operation: 'press_key', elementIndex: null });
  const scored = scoreItem(item, makeLine({ operation: 'press_key', elementIndex: 2 }));
  assert.equal(scored.correct, true);
  assert.equal(scored.targeted, false);
  assert.equal(scored.targetCorrect, null);
  assert.equal(scored.prunedTarget, null);
  assert.equal(scored.pruneCause, null);
});

test('scoreItem: a pruned target reports the dropping rule', () => {
  const scored = scoreItem(makeItem({ elementIndex: 7 }), makeLine({ offered: [1, 2, 3], dropped: { 7: 'menu_bar' } }));
  assert.equal(scored.prunedTarget, true);
  assert.equal(scored.pruneCause, 'menu_bar');
  assert.equal(scored.correct, false);
});

test('scoreItem: a target absent from the compact view is not_actionable', () => {
  const scored = scoreItem(makeItem({ elementIndex: 9 }), makeLine({ offered: [1, 2, 3], dropped: { 7: 'menu_bar' } }));
  assert.equal(scored.prunedTarget, true);
  assert.equal(scored.pruneCause, 'not_actionable');
});

test('scoreItem: a harness error is incorrect with no margin or latency', () => {
  const scored = scoreItem(makeItem(), makeLine({ error: 'deadline exceeded' }));
  assert.equal(scored.correct, false);
  assert.equal(scored.opCorrect, false);
  assert.equal(scored.margin, null);
  assert.equal(scored.latencyMs, null);
  assert.equal(scored.error, 'deadline exceeded');
});

test('scoreItem: rejects a line whose id does not match the item', () => {
  assert.throws(() => scoreItem(makeItem({ id: 'a' }), makeLine({ id: 'b' })), /id/);
});

test('aggregate: errors count against top1 but not auroc or latency; pruned rate uses targeted items only', () => {
  const scored = [
    scoreItem(makeItem({ id: 'a' }), makeLine({ id: 'a', margin: 0.9, latencyMs: 100 })),
    scoreItem(makeItem({ id: 'b' }), makeLine({ id: 'b', elementIndex: 2, margin: 0.1, latencyMs: 300 })),
    scoreItem(makeItem({ id: 'c', elementIndex: 8 }), makeLine({ id: 'c', error: 'timeout', offered: [1, 2, 3] })),
    scoreItem(
      makeItem({ id: 'd', operation: 'done', elementIndex: null }),
      makeLine({ id: 'd', operation: 'done', elementIndex: null, margin: 0.8, latencyMs: 200, offered: [1] }),
    ),
  ];
  const metrics = aggregate(scored);
  assert.equal(metrics.n, 4);
  assert.equal(metrics.top1, 0.5);
  assert.equal(metrics.errors, 1);
  assert.equal(metrics.auroc, 1, 'the error item has no margin and is excluded');
  assert.equal(metrics.p50Ms, 200, 'nearest-rank p50 over the three non-error latencies');
  assert.equal(metrics.p95Ms, 300);
  assert.equal(metrics.prunedTargetRate, Number((1 / 3).toFixed(4)), 'one of three targeted items lost its target');
  assert.deepEqual(metrics.prunedByCause, { not_actionable: 1 });
  assert.equal(metrics.opAccuracy, 0.75);
  assert.equal(metrics.targetAccuracy, Number((1 / 3).toFixed(4)));
});

test('aggregate: an empty set yields nulls, not NaN', () => {
  const metrics = aggregate([]);
  assert.equal(metrics.n, 0);
  assert.equal(metrics.top1, null);
  assert.equal(metrics.auroc, null);
  assert.equal(metrics.p50Ms, null);
  assert.equal(metrics.prunedTargetRate, null);
});

/** Builds scored rows directly: only margin, correct, and error matter for selectTau. */
function scoredRows(specs) {
  const rows = [];
  for (const { count, margin, correct } of specs) {
    for (let i = 0; i < count; i += 1) {
      rows.push({ margin, correct, error: null });
    }
  }
  return rows;
}

test('selectTau: picks the smallest margin that reaches the precision and coverage floors', () => {
  const scored = scoredRows([
    { count: 140, margin: 0.3, correct: false },
    { count: 3, margin: 0.6, correct: false },
    { count: 27, margin: 0.6, correct: true },
    { count: 30, margin: 0.8, correct: true },
  ]);
  const result = selectTau(scored);
  assert.equal(result.tau, 0.6);
  assert.equal(result.precision, 0.95);
  assert.equal(result.coverage, 0.3);
});

test('selectTau: returns 1.0 with zero coverage when precision is never reached', () => {
  const scored = scoredRows([
    { count: 10, margin: 0.2, correct: true },
    { count: 10, margin: 0.9, correct: false },
  ]);
  const result = selectTau(scored);
  assert.equal(result.tau, 1.0);
  assert.equal(result.precision, null);
  assert.equal(result.coverage, 0);
});

test('selectTau: respects the coverage floor', () => {
  const scored = scoredRows([
    { count: 95, margin: 0.1, correct: false },
    { count: 5, margin: 0.9, correct: true },
  ]);
  assert.deepEqual(selectTau(scored, { minCoverage: 0.1 }), { tau: 1.0, precision: null, coverage: 0 });
  assert.equal(selectTau(scored, { minCoverage: 0.05 }).tau, 0.9);
});

const SUMMARY_KEYS = [
  'schemaVersion', 'generatedAt', 'model', 'llamaCpp', 'hardware', 'dataset',
  'metrics', 'tau', 'gates', 'tuningRounds', 'notes',
];

function canarySummary() {
  const items = [
    makeItem({ id: 'real-1', goal: `Open ${CANARY} settings`, split: 'test', source: 'real' }),
    makeItem({ id: 'real-2', goal: `Rename ${CANARY}`, split: 'dev', source: 'real', elementIndex: 9 }),
  ];
  const lines = [
    makeLine({ id: 'real-1', rowText: `button ${CANARY}` }),
    makeLine({ id: 'real-2', rowText: `text field ${CANARY}`, elementIndex: 2 }),
  ];
  const scored = items.map((item, i) => scoreItem(item, lines[i]));
  const metricsBySplit = {
    all: aggregate(scored),
    dev: aggregate(scored.filter((row) => row.split === 'dev')),
    test: aggregate(scored.filter((row) => row.split === 'test')),
  };
  return buildSummary({
    meta: {
      generatedAt: '2026-09-23T12:00:00Z',
      model: { key: 'qwen3.5-4b-q4km', sha256: 'ab'.repeat(32), goal: CANARY },
      llamaCpp: { version: 'b10964-b29c606e2' },
      hardware: { chip: 'Apple M4 Max', memoryGB: 48, host: CANARY },
      rows: lines,
    },
    dataset: {
      n: 2, fixture: 0, real: 2, bySplit: { dev: 1, test: 1 }, snapshotsBySplit: { dev: 1, test: 1 },
      byOperation: { click: 2 }, items,
    },
    metricsBySplit,
    tau: { tau: 0.62, precision: 0.93, coverage: 0.4 },
    tauOnTest: { precision: 0.9, coverage: 0.35 },
    tuningRounds: [{ round: 0, note: 'baseline', devTop1: 0.5, devPrunedTargetRate: 0.1, goal: CANARY }],
    notes: ['p50 is an optimistic bound (Apple M4 Max, 48 GB).'],
  });
}

test('buildSummary: whitelisted fields only; never copies goal or row text', () => {
  const summary = canarySummary();
  assert.equal(JSON.stringify(summary).includes(CANARY), false);
  assert.deepEqual(Object.keys(summary).sort(), [...SUMMARY_KEYS].sort());
});

test('buildSummary: gates are judged on the test split and tau rounds up to 2 decimals', () => {
  const summary = canarySummary();
  assert.equal(summary.schemaVersion, 1);
  assert.equal(summary.gates.length, 4);
  for (const gate of summary.gates) {
    assert.equal(gate.split, 'test');
    assert.equal(typeof gate.pass, 'boolean');
  }
  const top1 = summary.gates.find((gate) => gate.name === 'top1');
  assert.equal(top1.value, summary.metrics.test.top1);
  assert.equal(top1.pass, summary.metrics.test.top1 >= 0.8);
  const auroc = summary.gates.find((gate) => gate.name === 'auroc');
  assert.equal(auroc.value, null, 'single-class test split has no AUROC');
  assert.equal(auroc.pass, false, 'a missing value never passes');
  assert.deepEqual(summary.tau, { value: 0.62, devPrecision: 0.93, devCoverage: 0.4, testPrecision: 0.9, testCoverage: 0.35 });
  assert.deepEqual(summary.tuningRounds, [{ round: 0, note: 'baseline', devTop1: 0.5, devPrunedTargetRate: 0.1 }]);
  assert.deepEqual(summary.hardware, { chip: 'Apple M4 Max', memoryGB: 48 });
  assert.deepEqual(Object.keys(summary.dataset).sort(), ['byOperation', 'bySplit', 'fixture', 'n', 'real', 'snapshotsBySplit']);
  assert.deepEqual(summary.dataset.snapshotsBySplit, { dev: 1, test: 1 });
});

test('buildSummary: tau rounding is upward and float-safe', () => {
  const base = canarySummary();
  const rebuild = (tau) => buildSummary({
    meta: { generatedAt: base.generatedAt, model: base.model, llamaCpp: base.llamaCpp, hardware: base.hardware },
    dataset: base.dataset,
    metricsBySplit: base.metrics,
    tau: { tau, precision: 0.9, coverage: 0.2 },
    tauOnTest: { precision: 0.9, coverage: 0.2 },
    tuningRounds: [],
    notes: [],
  }).tau.value;
  assert.equal(rebuild(0.6123), 0.62);
  assert.equal(rebuild(0.57), 0.57, '0.57 * 100 is 56.99999... in floating point and must not round to 0.58');
  assert.equal(rebuild(1.0), 1);
});

test('snapshotsBySplit: counts distinct screens per split, not items', () => {
  const items = [
    { ...makeItem({ id: 'a', split: 'dev' }), snapshotId: 's1' },
    { ...makeItem({ id: 'b', split: 'dev' }), snapshotId: 's1' },
    { ...makeItem({ id: 'c', split: 'dev' }), snapshotId: 's2' },
    { ...makeItem({ id: 'd', split: 'test' }), snapshotId: 's3' },
    { ...makeItem({ id: 'e', split: 'test' }), snapshotId: 's3' },
  ];
  assert.deepEqual(snapshotsBySplit(items), { dev: 2, test: 1 });
  assert.deepEqual(snapshotsBySplit([]), {});
});

test('testClusteringNote: names the item and screen counts behind the test metrics', () => {
  const note = testClusteringNote({ dev: 175, test: 79 }, { dev: 16, test: 7 });
  assert.match(note, /79 items on only 7 screens/);
  assert.match(note, /correlated/);
});

test('tuningIsolationNote: claims dev-only tuning only when every logged round ran with --split dev', () => {
  assert.match(tuningIsolationNote([]), /No pruning tuning rounds were recorded/);
  const devOnly = tuningIsolationNote([{ round: 0, split: 'dev' }, { round: 1, split: 'dev' }]);
  assert.match(devOnly, /no tuning run scored or printed test items/);
  const exposed = tuningIsolationNote([{ round: 0 }, { round: 1 }, { round: 2, split: 'dev' }]);
  assert.match(exposed, /rounds 0, 1 were compared on their dev metrics/);
  assert.match(exposed, /also printed test aggregates/);
  assert.doesNotMatch(exposed, /no tuning run/);
});

test('LATENCY_SCOPE_NOTE: says the latency excludes the accessibility refresh', () => {
  assert.match(LATENCY_SCOPE_NOTE, /exclude the accessibility refresh/);
});
