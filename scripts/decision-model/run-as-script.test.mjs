// Tests for the "run main only as a script" guard. Node realpaths import.meta.url but not process.argv[1], so a
// guard that compares the two as written silently skips main() when a CLI is reached through a symlinked path and
// exits 0 with no output. Each CLI below is run through a directory symlink with a bad-usage argument, so a CLI
// whose main() ran exits non-zero and says why, without touching a server or the dataset.

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { invokedAsScript } from './run-as-script.mjs';

const scriptDir = dirname(fileURLToPath(import.meta.url));

/** A directory symlink to this scripts directory, under a tmpdir path that is itself not realpathed. */
function symlinkedScriptDir(t) {
  const root = mkdtempSync(join(tmpdir(), 'ocu-run-as-script-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const link = join(root, 'dm-link');
  symlinkSync(scriptDir, link, 'dir');
  return link;
}

const CLIS = [
  { name: 'check-readout.mjs', args: ['--no-such-flag'], status: 1, output: /unknown argument/ },
  { name: 'eval-run.mjs', args: ['--no-such-flag'], status: 64, output: /eval-run:/ },
  { name: 'eval-dataset.mjs', args: [], status: 2, output: /usage: node eval-dataset\.mjs/ },
];

for (const { name, args, status, output } of CLIS) {
  test(`${name} runs its main when reached through a symlinked path`, (t) => {
    const link = symlinkedScriptDir(t);
    const result = spawnSync(process.execPath, [join(link, name), ...args], { encoding: 'utf8' });
    assert.equal(result.status, status, `stdout: ${result.stdout}\nstderr: ${result.stderr}`);
    assert.match(result.stdout + result.stderr, output);
  });
}

test('invokedAsScript matches the entry module by real path, not by spelling', (t) => {
  const link = symlinkedScriptDir(t);
  const moduleUrl = new URL('./check-readout.mjs', import.meta.url).href;
  assert.equal(invokedAsScript(moduleUrl, join(scriptDir, 'check-readout.mjs')), true);
  assert.equal(invokedAsScript(moduleUrl, join(link, 'check-readout.mjs')), true);
  assert.equal(invokedAsScript(moduleUrl, join(link, 'eval-run.mjs')), false, 'another script is not this module');
  assert.equal(invokedAsScript(moduleUrl, join(link, 'missing.mjs')), false, 'an unresolvable path is not this module');
  assert.equal(invokedAsScript(moduleUrl, undefined), false, 'no argv[1] (for example node -e) is not this module');
});
