// Tests for check-readout.mjs: the target-head locator directly, and the whole script against a mock llama-server
// whose /completion response shape is controlled per test. Node built-ins only; no real sidecar is needed.

import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { locateTargetHead, RESPONSE_SHAPE_NOTE } from './check-readout.mjs';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const manifest = JSON.parse(readFileSync(join(scriptDir, 'model-manifest.json'), 'utf8'));
const pin = JSON.parse(readFileSync(join(scriptDir, 'fixtures', 'readout-pin.json'), 'utf8'));
const TARGET_PIECES = [' A', ' B', ' C', ' D', ' E'];
const OPERATION_PIECES = [' A', ' B', ' C', ' D', ' E', ' F', ' G'];

const entry = (token, pieces = []) => ({
  token,
  logprob: -0.1,
  top_logprobs: [
    { token, logprob: -0.1 },
    ...pieces.filter((piece) => piece !== token).map((piece, i) => ({ token: piece, logprob: -2 - i })),
    { token: ' the', logprob: -9 },
  ],
});

test('locateTargetHead: finds the target head in the pinned response', () => {
  const located = locateTargetHead(pin.response.completion_probabilities, TARGET_PIECES);
  assert.equal(located.error, undefined);
  assert.equal(located.index, 4);
  assert.equal(located.entry.token, ' C');
});

test('locateTargetHead: never takes the operation head at index 0 when the target answer is split', () => {
  const probs = [' A', '\n', 'Target', ':', ' ', 'C', ''].map((token) => entry(token));
  const located = locateTargetHead(probs, TARGET_PIECES);
  assert.equal(located.entry, undefined);
  assert.match(located.error, /no entry after the operation head/);
});

test('locateTargetHead: requires the "\\nTarget:" literal between the heads', () => {
  const probs = [' A', '\n', 'Tar', ' B', ''].map((token) => entry(token));
  assert.match(locateTargetHead(probs, TARGET_PIECES).error, /spell/);
});

test('locateTargetHead: rejects non-empty tokens after the target head', () => {
  const probs = [' A', '\n', 'Target', ':', ' B', 'x', ''].map((token) => entry(token));
  assert.match(locateTargetHead(probs, TARGET_PIECES).error, /non-empty tokens follow/);
});

test('the committed pin carries the current response shape note', () => {
  assert.equal(pin.responseShapeNote, RESPONSE_SHAPE_NOTE);
  assert.match(RESPONSE_SHAPE_NOTE, /after index 0/);
});

/** Starts a mock llama-server whose /completion returns `completionTokens` and resolves to its base URL. */
async function startMockServer(completionTokens) {
  const filename = manifest.models[manifest.active].filename;
  const server = createServer((request, response) => {
    let body = '';
    request.on('data', (chunk) => { body += chunk; });
    request.on('end', () => {
      const json = (value) => {
        response.writeHead(200, { 'content-type': 'application/json' });
        response.end(JSON.stringify(value));
      };
      const parsed = body.length > 0 ? JSON.parse(body) : {};
      switch (request.url) {
        case '/health': return json({ status: 'ok' });
        case '/props': return json({ model_path: `/models/${filename}`, build_info: 'mock' });
        case '/tokenize': return json({ tokens: [{ id: 1, piece: parsed.content }] });
        case '/apply-template':
          return json({ prompt: '<|im_start|>system\n<<SYS>><|im_end|>\n<|im_start|>user\n<<USER>><|im_end|>\n<|im_start|>assistant\n' });
        case '/completion':
          return json({
            content: completionTokens.join(''),
            completion_probabilities: completionTokens.map((token, i) => entry(token, i === 0 ? OPERATION_PIECES : TARGET_PIECES)),
          });
        default:
          response.writeHead(404);
          return response.end();
      }
    });
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  return { server, url: `http://127.0.0.1:${server.address().port}` };
}

function runCheckReadout(url) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [join(scriptDir, 'check-readout.mjs'), '--url', url, '--model', manifest.active], {
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', (code) => resolve({ code, stdout, stderr }));
  });
}

test('check-readout.mjs fails against a server whose target answer is split across tokens', async () => {
  const { server, url } = await startMockServer([' A', '\n', 'Target', ':', ' ', 'C', '']);
  try {
    const { code, stdout, stderr } = await runCheckReadout(url);
    assert.equal(code, 1, stdout + stderr);
    assert.doesNotMatch(stdout, /all readout assertions passed/);
    assert.match(stderr, /target head/);
  } finally {
    server.close();
  }
});

test('check-readout.mjs passes against a server with the pinned response shape', async () => {
  const { server, url } = await startMockServer([' C', '\n', 'Target', ':', ' C', '']);
  try {
    const { code, stdout, stderr } = await runCheckReadout(url);
    assert.equal(code, 0, stdout + stderr);
    assert.match(stdout, /all readout assertions passed/);
  } finally {
    server.close();
  }
});
