#!/usr/bin/env node
// Schema and parity validator for the decision-model eval dataset.
//
// An eval item pairs a user goal with a captured get_app_state snapshot (full and compact
// renderings, stored verbatim) and a ground-truth operation plus element_index. The eval
// replays those exact strings through the shipped Swift pipeline, so an item is only useful
// when its snapshot is internally consistent and its target really exists in the full tree.
//
// CLI: node eval-dataset.mjs --check <items.jsonl> --snapshots <dir> [--committed]
// Prints one JSON object of counts (never snapshot or goal text) and exits 0 iff no errors.
// Node built-ins only.

import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const OPERATIONS = ['click', 'set_value', 'type_text', 'scroll', 'press_key', 'wait', 'done'];
export const TARGETED = new Set(['click', 'set_value', 'scroll']);

const SOURCES = new Set(['real', 'fixture']);
const SPLITS = new Set(['dev', 'test']);
const CONFIDENCES = new Set(['high', 'medium', 'low']);
const COMPACT_HEADER = 'Compact actionable view:';
// Emitted by the compact renderer instead of the header when nothing is actionable.
const COMPACT_EMPTY_PREFIX = '(no actionable elements found';
const COMPACT_ROW = /^\d+ /;
const LEADING_INDEX = /^(\d+)(?:\s|$)/;
const ROW_CONTINUATION_SEPARATOR = ' — ';
const FOCUSED_SUFFIX = ' (focused)';

/** Deterministic dev/test split by snapshot: first byte of sha256(snapshotId), even -> dev. */
export function splitFor(snapshotId) {
  if (typeof snapshotId !== 'string') {
    throw new TypeError('splitFor: snapshotId must be a string');
  }
  const firstByte = createHash('sha256').update(snapshotId, 'utf8').digest()[0];
  return firstByte % 2 === 0 ? 'dev' : 'test';
}

function isPlainObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isNonEmptyString(value) {
  return typeof value === 'string' && value.length > 0;
}

function stripLeadingIndent(line) {
  return line.replace(/^[\t ]+/, '');
}

/** Full-tree lines with leading tabs and spaces removed, as the compact renderer does. */
function strippedFullLines(renderedFull) {
  return renderedFull.split('\n').map(stripLeadingIndent);
}

/**
 * Indexed rows of the compact view: lines after the header up to the first blank line that
 * start with an integer and a space. Returns null when the header is absent.
 */
function compactRows(renderedCompact) {
  const lines = renderedCompact.split('\n');
  const headerAt = lines.findIndex((line) => line.startsWith(COMPACT_HEADER));
  if (headerAt === -1) {
    return null;
  }
  const rows = [];
  for (const line of lines.slice(headerAt + 1)) {
    if (line.trim() === '') {
      break;
    }
    if (COMPACT_ROW.test(line)) {
      rows.push(line);
    }
  }
  return rows;
}

/** The part of a compact row that must equal a full-tree line. */
function compactRowHead(row) {
  const separatorAt = row.indexOf(ROW_CONTINUATION_SEPARATOR);
  let head = separatorAt === -1 ? row : row.slice(0, separatorAt);
  if (head.endsWith(FOCUSED_SUFFIX)) {
    head = head.slice(0, -FOCUSED_SUFFIX.length);
  }
  return head;
}

function validateChoice(choice, path, errors, { requireConfidence = false } = {}) {
  if (!isPlainObject(choice)) {
    errors.push(`${path} must be an object`);
    return;
  }
  if (!OPERATIONS.includes(choice.operation)) {
    errors.push(`${path}.operation must be one of ${OPERATIONS.join(', ')}`);
  }
  if (choice.elementIndex !== null && !Number.isInteger(choice.elementIndex)) {
    errors.push(`${path}.elementIndex must be an integer or null`);
  }
  if (requireConfidence && !CONFIDENCES.has(choice.confidence)) {
    errors.push(`${path}.confidence must be one of ${[...CONFIDENCES].join(', ')}`);
  }
}

function validateLabeling(labeling, errors) {
  if (!isPlainObject(labeling)) {
    errors.push('labeling must be an object');
    return;
  }
  validateChoice(labeling.generator, 'labeling.generator', errors);
  validateChoice(labeling.labeler, 'labeling.labeler', errors, { requireConfidence: true });
  for (const flag of ['agreement', 'adjudicated', 'spotChecked', 'paraphrased']) {
    if (typeof labeling[flag] !== 'boolean') {
      errors.push(`labeling.${flag} must be a boolean`);
    }
  }
}

/** Rule 1: required fields, types, and the operation/elementIndex pairing. */
function validateItemShape(item, errors) {
  if (item.schemaVersion !== 1) {
    errors.push('schemaVersion must be 1');
  }
  for (const field of ['id', 'snapshotId', 'goal']) {
    if (!isNonEmptyString(item[field])) {
      errors.push(`${field} must be a non-empty string`);
    }
  }
  if (!SOURCES.has(item.source)) {
    errors.push(`source must be one of ${[...SOURCES].join(', ')}`);
  }
  if (!SPLITS.has(item.split)) {
    errors.push(`split must be one of ${[...SPLITS].join(', ')}`);
  }
  const truth = item.groundTruth;
  if (!isPlainObject(truth)) {
    errors.push('groundTruth must be an object');
  } else if (!OPERATIONS.includes(truth.operation)) {
    errors.push(`groundTruth.operation must be one of ${OPERATIONS.join(', ')}`);
  } else if (TARGETED.has(truth.operation)) {
    if (!Number.isInteger(truth.elementIndex)) {
      errors.push(`groundTruth.elementIndex must be an integer for ${truth.operation}`);
    }
  } else if (truth.elementIndex !== null) {
    errors.push(`groundTruth.elementIndex must be null for ${truth.operation}`);
  }
  validateLabeling(item.labeling, errors);
}

/** Rules 2-4: snapshot linkage, compact/full parity, and target existence. */
function validateAgainstSnapshot(item, snapshot, errors) {
  if (!isPlainObject(snapshot)) {
    errors.push(`snapshot ${JSON.stringify(item.snapshotId)} not found`);
    return;
  }
  if (snapshot.schemaVersion !== 1) {
    errors.push('snapshot.schemaVersion must be 1');
  }
  if (snapshot.snapshotId !== item.snapshotId) {
    errors.push('snapshot.snapshotId does not match item.snapshotId');
  }
  if (snapshot.source !== item.source) {
    errors.push(`snapshot.source ${JSON.stringify(snapshot.source)} does not match item.source`);
  }
  if (typeof item.snapshotId === 'string' && item.split !== splitFor(item.snapshotId)) {
    errors.push(`split must be ${splitFor(item.snapshotId)} for this snapshotId`);
  }
  if (typeof snapshot.renderedFull !== 'string' || typeof snapshot.renderedCompact !== 'string') {
    errors.push('snapshot.renderedFull and snapshot.renderedCompact must be strings');
    return;
  }

  const fullLines = strippedFullLines(snapshot.renderedFull);
  const fullLineSet = new Set(fullLines);

  const rows = compactRows(snapshot.renderedCompact);
  if (rows === null) {
    if (!snapshot.renderedCompact.includes(COMPACT_EMPTY_PREFIX)) {
      errors.push(`snapshot.renderedCompact has no "${COMPACT_HEADER}" header`);
    }
  } else {
    for (const row of rows) {
      if (!fullLineSet.has(compactRowHead(row))) {
        const index = row.match(LEADING_INDEX)?.[1];
        errors.push(`compact row ${index} has no matching full-tree line`);
      }
    }
  }

  const truth = item.groundTruth;
  if (isPlainObject(truth) && TARGETED.has(truth.operation) && Number.isInteger(truth.elementIndex)) {
    const present = fullLines.some((line) => {
      const match = line.match(LEADING_INDEX);
      return match !== null && Number(match[1]) === truth.elementIndex;
    });
    if (!present) {
      errors.push(`groundTruth.elementIndex ${truth.elementIndex} is not in the full tree`);
    }
  }
}

/**
 * Validates one item against its snapshot. Returns error strings; empty means valid.
 * With committed:true, only fixture-sourced items are allowed (real captures stay local).
 */
export function validateItem(item, snapshot, { committed = false } = {}) {
  const errors = [];
  if (!isPlainObject(item)) {
    return ['item must be an object'];
  }
  validateItemShape(item, errors);
  validateAgainstSnapshot(item, snapshot, errors);
  if (committed && item.source !== 'fixture') {
    errors.push(`source ${JSON.stringify(item.source)} must not be committed; only fixture items are`);
  }
  return errors;
}

/**
 * Reads a JSONL items file and every *.json snapshot in a directory, keyed by snapshotId.
 * Throws with the offending file/line on unreadable input, invalid JSON, or duplicate ids.
 */
export function loadDataset(itemsPath, snapshotsDir) {
  const items = [];
  const lines = readFileSync(itemsPath, 'utf8').split('\n');
  lines.forEach((line, lineIndex) => {
    if (line.trim() === '') {
      return;
    }
    try {
      items.push(JSON.parse(line));
    } catch (error) {
      throw new Error(`${itemsPath}:${lineIndex + 1}: invalid JSON (${error.message})`);
    }
  });

  const snapshots = new Map();
  const files = readdirSync(snapshotsDir).filter((name) => name.endsWith('.json')).sort();
  for (const name of files) {
    const path = join(snapshotsDir, name);
    let snapshot;
    try {
      snapshot = JSON.parse(readFileSync(path, 'utf8'));
    } catch (error) {
      throw new Error(`${path}: invalid JSON (${error.message})`);
    }
    if (!isPlainObject(snapshot) || !isNonEmptyString(snapshot.snapshotId)) {
      throw new Error(`${path}: snapshotId must be a non-empty string`);
    }
    if (snapshots.has(snapshot.snapshotId)) {
      throw new Error(`${path}: duplicate snapshotId ${JSON.stringify(snapshot.snapshotId)}`);
    }
    snapshots.set(snapshot.snapshotId, snapshot);
  }
  return { items, snapshots };
}

function countBy(values) {
  const counts = {};
  for (const value of values) {
    const key = String(value);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

function rate(items, predicate) {
  if (items.length === 0) {
    return 0;
  }
  return Number((items.filter(predicate).length / items.length).toFixed(4));
}

/** Validates a loaded dataset and returns the count-only report the CLI prints. */
function checkDataset({ items, snapshots }, { committed = false } = {}) {
  const errors = [];
  const seenIds = new Set();
  items.forEach((item, position) => {
    const label = isPlainObject(item) && isNonEmptyString(item.id) ? item.id : `line-item ${position + 1}`;
    if (isPlainObject(item) && isNonEmptyString(item.id)) {
      if (seenIds.has(item.id)) {
        errors.push(`${label}: duplicate id`);
      }
      seenIds.add(item.id);
    }
    const snapshot = isPlainObject(item) ? snapshots.get(item.snapshotId) : undefined;
    for (const error of validateItem(item, snapshot, { committed })) {
      errors.push(`${label}: ${error}`);
    }
  });
  if (committed) {
    for (const [snapshotId, snapshot] of snapshots) {
      if (snapshot.source !== 'fixture') {
        errors.push(`snapshot ${snapshotId}: source ${JSON.stringify(snapshot.source)} must not be committed`);
      }
    }
  }

  const objects = items.filter(isPlainObject);
  return {
    n: items.length,
    bySource: countBy(objects.map((item) => item.source)),
    byOperation: countBy(objects.map((item) => item.groundTruth?.operation)),
    bySplit: countBy(objects.map((item) => item.split)),
    agreementRate: rate(objects, (item) => item.labeling?.agreement === true),
    adjudicated: objects.filter((item) => item.labeling?.adjudicated === true).length,
    paraphrasedRate: rate(objects, (item) => item.labeling?.paraphrased === true),
    errors,
  };
}

function parseArgs(argv) {
  const options = { committed: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--committed') {
      options.committed = true;
    } else if ((arg === '--check' || arg === '--snapshots') && i + 1 < argv.length) {
      options[arg.slice(2)] = argv[i + 1];
      i += 1;
    } else {
      return null;
    }
  }
  return options.check && options.snapshots ? options : null;
}

function main(argv) {
  const options = parseArgs(argv);
  if (options === null) {
    process.stderr.write('usage: node eval-dataset.mjs --check <items.jsonl> --snapshots <dir> [--committed]\n');
    return 2;
  }
  let report;
  try {
    const dataset = loadDataset(resolve(options.check), resolve(options.snapshots));
    report = checkDataset(dataset, { committed: options.committed });
  } catch (error) {
    report = {
      n: 0,
      bySource: {},
      byOperation: {},
      bySplit: {},
      agreementRate: 0,
      adjudicated: 0,
      paraphrasedRate: 0,
      errors: [error.message],
    };
  }
  process.stdout.write(`${JSON.stringify(report)}\n`);
  return report.errors.length === 0 ? 0 : 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  process.exitCode = main(process.argv.slice(2));
}
