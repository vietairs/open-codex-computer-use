// Tests for start-sidecar.sh and stop-sidecar.sh process ownership. Every run uses a scratch HOME and a scratch copy
// of the scripts with a tiny model manifest, and only ever signals dummy processes that the test itself started:
// `sleep` renamed with `exec -a`, or an idle or mock-serving copy of the node binary named `llama-server`, so the
// kernel reports that name as its executable. No real llama-server or model is touched.

import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  constants, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const SCRIPTS = ['start-sidecar.sh', 'stop-sidecar.sh', 'sidecar-pid-lib.sh', 'check-readout.mjs'];

const MOCK_SERVER = `
import { createServer } from 'node:http';
const [modelPath] = process.argv.slice(2);
const server = createServer((request, response) => {
  if (request.url === '/health' || request.url === '/props') {
    response.writeHead(200, { 'content-type': 'application/json' });
    return response.end(JSON.stringify(request.url === '/health' ? { status: 'ok' } : { model_path: modelPath }));
  }
  response.writeHead(404);
  response.end();
});
server.listen(0, '127.0.0.1', () => process.stdout.write(String(server.address().port) + '\\n'));
`;

/** A scratch HOME plus a scratch copy of the scripts whose manifest names a tiny, present, hash-correct model. */
function makeSandbox(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'ocu-sidecar-')));
  const children = [];
  t.after(() => {
    for (const child of children) {
      if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
    }
    rmSync(root, { recursive: true, force: true });
  });

  const scripts = join(root, 'scripts');
  mkdirSync(scripts);
  for (const name of SCRIPTS) copyFileSync(join(scriptDir, name), join(scripts, name));
  const model = Buffer.from('tiny model for sidecar script tests\n');
  writeFileSync(join(scripts, 'model-manifest.json'), JSON.stringify({
    active: 'tiny',
    models: { tiny: { filename: 'tiny.gguf', sizeBytes: model.length, sha256: createHash('sha256').update(model).digest('hex') } },
  }));

  const home = join(root, 'home');
  const stateDir = join(home, 'Library', 'Application Support', 'OpenComputerUse', 'decision-model');
  for (const dir of ['models', 'run', 'logs']) mkdirSync(join(stateDir, dir), { recursive: true });
  writeFileSync(join(stateDir, 'models', 'tiny.gguf'), model);

  const bin = join(root, 'bin');
  mkdirSync(bin);
  const fakeLlama = join(bin, 'llama-server');
  copyFileSync(process.execPath, fakeLlama, constants.COPYFILE_FICLONE);
  writeFileSync(join(root, 'mock-server.mjs'), MOCK_SERVER);

  const env = {
    ...process.env,
    HOME: home,
    PATH: [bin, dirname(process.execPath), '/usr/bin', '/bin', '/usr/sbin', '/sbin'].join(':'),
  };
  delete env.OCU_DECISION_MODEL_PORT;

  return {
    root,
    fakeLlama,
    pidFile: join(stateDir, 'run', 'llama-server.pid'),
    track(child) {
      children.push(child);
      return child;
    },
    /** Runs a script asynchronously, so this process keeps reaping its own dummy children while it waits. */
    run(script, args = []) {
      return new Promise((resolve, reject) => {
        const child = spawn('bash', [join(scripts, script), ...args], { env, stdio: ['ignore', 'pipe', 'pipe'] });
        let stdout = '';
        let stderr = '';
        child.stdout.on('data', (chunk) => { stdout += chunk; });
        child.stderr.on('data', (chunk) => { stderr += chunk; });
        child.on('error', reject);
        child.on('close', (status) => resolve({ status, stdout, stderr }));
      });
    },
  };
}

function startTime(pid) {
  return spawnSync('ps', ['-p', String(pid), '-o', 'lstart='], { env: { ...process.env, LC_ALL: 'C' }, encoding: 'utf8' })
    .stdout.replace(/\s+$/, '');
}

function writePidFile(sandbox, { pid, port, lstart = startTime(pid), binary = sandbox.fakeLlama }) {
  writeFileSync(sandbox.pidFile, `pid=${pid}\nport=${port}\nlstart=${lstart}\nbinary=${binary}\nmodel=tiny\n`, { mode: 0o600 });
}

function alive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

async function waitForExit(child, ms = 5_000) {
  const deadline = Date.now() + ms;
  while (alive(child.pid) && child.exitCode === null && child.signalCode === null && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
}

/** A `sleep` whose argv (and therefore `ps -o comm=` and `ps -o command=`) mentions llama-server. */
async function renamedSleep(sandbox) {
  const child = sandbox.track(spawn('bash', ['-c', 'exec -a "sleep-watch-llama-server.pid" sleep 300'], { stdio: 'ignore' }));
  // Wait for the exec so the start time and executable belong to sleep, not to bash.
  for (let i = 0; i < 100 && !/sleep-watch/.test(spawnSync('ps', ['-p', String(child.pid), '-o', 'command=']).stdout); i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  return child;
}

/** An idle process whose kernel-reported executable is the sandbox's `llama-server` (a copy of node). */
function idleFakeSidecar(sandbox) {
  return sandbox.track(spawn(sandbox.fakeLlama, ['-e', 'setTimeout(() => {}, 300000)'], { stdio: 'ignore' }));
}

/** The fake llama-server serving /health and /props on 127.0.0.1; resolves to { child, port }. */
function listeningFakeSidecar(sandbox, modelPath) {
  const child = sandbox.track(spawn(sandbox.fakeLlama, [join(sandbox.root, 'mock-server.mjs'), modelPath], { stdio: ['ignore', 'pipe', 'inherit'] }));
  return new Promise((resolve, reject) => {
    child.once('error', reject);
    child.stdout.once('data', (chunk) => resolve({ child, port: Number(String(chunk).trim()) }));
  });
}

test('stop-sidecar refuses a pid whose argv merely mentions llama-server, and keeps the pid file', async (t) => {
  const sandbox = makeSandbox(t);
  const impostor = await renamedSleep(sandbox);
  writePidFile(sandbox, { pid: impostor.pid, port: 39999 });

  const result = await sandbox.run('stop-sidecar.sh');

  assert.equal(result.status, 1, result.stdout + result.stderr);
  assert.match(result.stderr, /refusing to signal/);
  assert.ok(alive(impostor.pid), 'the renamed sleep must not be signalled');
  assert.ok(existsSync(sandbox.pidFile), 'the pid file stays for inspection');
});

test('stop-sidecar refuses an old pid-only file that names a running process', async (t) => {
  const sandbox = makeSandbox(t);
  const impostor = await renamedSleep(sandbox);
  writeFileSync(sandbox.pidFile, `${impostor.pid}\n`);

  const result = await sandbox.run('stop-sidecar.sh');

  assert.equal(result.status, 1, result.stdout + result.stderr);
  assert.ok(alive(impostor.pid));
  assert.ok(existsSync(sandbox.pidFile));
});

test('stop-sidecar treats a reused pid (different start time) as stale and signals nothing', async (t) => {
  const sandbox = makeSandbox(t);
  const reused = idleFakeSidecar(sandbox);
  writePidFile(sandbox, { pid: reused.pid, port: 39999, lstart: 'Thu Jan  1 00:00:00 1970' });

  const result = await sandbox.run('stop-sidecar.sh');

  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /no longer running/);
  assert.ok(alive(reused.pid), 'a process with a different start time is not the recorded sidecar');
  assert.ok(!existsSync(sandbox.pidFile));
});

test('stop-sidecar stops the recorded sidecar when pid, start time and executable all match', async (t) => {
  const sandbox = makeSandbox(t);
  const owned = idleFakeSidecar(sandbox);
  await new Promise((resolve) => setTimeout(resolve, 200));
  writePidFile(sandbox, { pid: owned.pid, port: 39999 });

  const result = await sandbox.run('stop-sidecar.sh');
  await waitForExit(owned);

  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /stopped/);
  assert.ok(!alive(owned.pid) || owned.signalCode !== null, 'the owned dummy must be stopped');
  assert.ok(!existsSync(sandbox.pidFile));
});

test('start-sidecar refuses to start on another port while the recorded sidecar runs, and keeps its record', async (t) => {
  const sandbox = makeSandbox(t);
  const running = idleFakeSidecar(sandbox);
  await new Promise((resolve) => setTimeout(resolve, 200));
  writePidFile(sandbox, { pid: running.pid, port: 39998 });
  const before = readFileSync(sandbox.pidFile, 'utf8');

  const result = await sandbox.run('start-sidecar.sh', ['--port', '39997']);

  assert.equal(result.status, 4, result.stdout + result.stderr);
  assert.match(result.stderr, /still running \(pid \d+, port 39998\)/);
  assert.ok(alive(running.pid), 'the running sidecar must not be touched');
  assert.equal(readFileSync(sandbox.pidFile, 'utf8'), before, 'the record of the running sidecar must survive');
});

test('start-sidecar reuse runs check-readout and refuses a sidecar serving another model, leaving it running', async (t) => {
  const sandbox = makeSandbox(t);
  const { child, port } = await listeningFakeSidecar(sandbox, '/x/Some-Other-Model.gguf');
  writePidFile(sandbox, { pid: child.pid, port });
  const before = readFileSync(sandbox.pidFile, 'utf8');

  const result = await sandbox.run('start-sidecar.sh', ['--port', String(port)]);

  assert.equal(result.status, 6, result.stdout + result.stderr);
  assert.doesNotMatch(result.stdout, /export OPEN_COMPUTER_USE_DECISION_MODEL_URL/);
  assert.match(result.stderr, /model_path basename "Some-Other-Model.gguf"/);
  assert.ok(alive(child.pid), 'reuse failure must leave the running server alone');
  assert.equal(readFileSync(sandbox.pidFile, 'utf8'), before);
});

test('start-sidecar refuses an old pid-only file that names a running process', async (t) => {
  const sandbox = makeSandbox(t);
  const running = idleFakeSidecar(sandbox);
  writeFileSync(sandbox.pidFile, `${running.pid}\n`);

  const result = await sandbox.run('start-sidecar.sh', ['--port', '39997']);

  assert.equal(result.status, 4, result.stdout + result.stderr);
  assert.match(result.stderr, /old or unreadable format/);
  assert.ok(alive(running.pid));
  assert.equal(readFileSync(sandbox.pidFile, 'utf8'), `${running.pid}\n`);
});
