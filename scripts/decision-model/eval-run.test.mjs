// Tests for eval-run.mjs argument rules. Importing the module does not start an eval.

import assert from 'node:assert/strict';
import test from 'node:test';
import { parseArgs, UsageError } from './eval-run.mjs';

test('parseArgs: a tuning round runs over the dev split only', () => {
  const options = parseArgs(['--split', 'dev', '--tuning-round', '1', '--tuning-note', 'rule change']);
  assert.equal(options.split, 'dev');
  assert.equal(options.tuningRound, 1);
});

test('parseArgs: a tuning round over all or test splits is refused, so tuning never sees test metrics', () => {
  for (const split of [[], ['--split', 'all'], ['--split', 'test']]) {
    assert.throws(() => parseArgs([...split, '--tuning-round', '1', '--tuning-note', 'x']), UsageError, split.join(' '));
  }
  assert.throws(() => parseArgs(['--split', 'dev', '--prune-only', '--tuning-round', '1', '--tuning-note', 'x']), UsageError);
});

test('parseArgs: the summary still needs a full run over every split', () => {
  assert.equal(parseArgs(['--write-summary']).writeSummary, true);
  assert.throws(() => parseArgs(['--split', 'dev', '--write-summary']), UsageError);
});
