// Tests-first for scripts/decision-model/eval-dataset.mjs (phase 03).
// Written before the implementation exists; must fail (module-not-found) until
// eval-dataset.mjs is implemented to this Signature.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { splitFor, validateItem } from './eval-dataset.mjs';

// A minimal, internally-consistent full/compact tree pair. Index 1 (Button) and
// index 2 (TextField) appear in both renderings so parity holds by default.
const FULL_TREE = [
  '0 Window "Fixture"',
  '  1 Button "Increment"',
  '  2 TextField',
  '  3 ScrollArea',
].join('\n');

const COMPACT_TREE = [
  'Compact actionable view:',
  '1 Button "Increment"',
  '2 TextField (focused)',
  '',
].join('\n');

function makeSnapshot(overrides = {}) {
  return {
    schemaVersion: 1,
    snapshotId: 'fixture-01',
    source: 'fixture',
    app: 'OpenComputerUseFixture',
    capturedAt: '2026-09-23T11:00:00+10:00',
    screenNote: 'initial state',
    renderedFull: FULL_TREE,
    renderedCompact: COMPACT_TREE,
    ...overrides,
  };
}

function makeItem(overrides = {}) {
  const snapshotId = overrides.snapshotId ?? 'fixture-01';
  const source = overrides.source ?? 'fixture';
  return {
    schemaVersion: 1,
    id: 'fixture-01-g01',
    snapshotId,
    source,
    goal: 'increase the counter',
    groundTruth: { operation: 'click', elementIndex: 1 },
    split: splitFor(snapshotId),
    labeling: {
      generator: { operation: 'click', elementIndex: 1 },
      labeler: { operation: 'click', elementIndex: 1, confidence: 'high' },
      agreement: true,
      adjudicated: false,
      spotChecked: false,
      paraphrased: true,
    },
    ...overrides,
  };
}

test('a valid fixture item passes validation with no errors', () => {
  const errors = validateItem(makeItem(), makeSnapshot());
  assert.deepEqual(errors, []);
});

test('missing snapshot produces an error', () => {
  const errors = validateItem(makeItem(), undefined);
  assert.ok(errors.length > 0);
});

test('elementIndex absent from the full tree produces an error', () => {
  const item = makeItem({ groundTruth: { operation: 'click', elementIndex: 99 } });
  const errors = validateItem(item, makeSnapshot());
  assert.ok(errors.length > 0);
});

test('type_text with an integer elementIndex produces an error', () => {
  const item = makeItem({ groundTruth: { operation: 'type_text', elementIndex: 1 } });
  const errors = validateItem(item, makeSnapshot());
  assert.ok(errors.length > 0);
});

test('click with a null elementIndex produces an error', () => {
  const item = makeItem({ groundTruth: { operation: 'click', elementIndex: null } });
  const errors = validateItem(item, makeSnapshot());
  assert.ok(errors.length > 0);
});

test('a parity mismatch between compact and full tree produces an error', () => {
  const badSnapshot = makeSnapshot({
    renderedCompact: [
      'Compact actionable view:',
      '1 Button "Increment"',
      '5 Button "Ghost"',
      '',
    ].join('\n'),
  });
  const errors = validateItem(makeItem(), badSnapshot);
  assert.ok(errors.length > 0);
});

test('a split value that disagrees with splitFor produces an error', () => {
  const correct = splitFor('fixture-01');
  const wrong = correct === 'dev' ? 'test' : 'dev';
  const item = makeItem({ split: wrong });
  const errors = validateItem(item, makeSnapshot());
  assert.ok(errors.length > 0);
});

test('committed:true with source "real" produces an error', () => {
  const item = makeItem({ source: 'real' });
  const snapshot = makeSnapshot({ source: 'real' });
  const errors = validateItem(item, snapshot, { committed: true });
  assert.ok(errors.length > 0);
});

test('splitFor is deterministic and returns both values over 20 ids', () => {
  const ids = Array.from({ length: 20 }, (_, i) => `snapshot-${i}`);
  const results = ids.map((id) => splitFor(id));
  // Deterministic: calling again with the same id yields the same result.
  ids.forEach((id, i) => {
    assert.equal(splitFor(id), results[i]);
  });
  const unique = new Set(results);
  assert.ok(unique.has('dev'), 'expected at least one id to map to dev');
  assert.ok(unique.has('test'), 'expected at least one id to map to test');
});
