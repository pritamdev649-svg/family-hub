#!/usr/bin/env node
/**
 * Syntax check for the whole backend without running anything:
 *   - `node --check` on every .js file under src/, scripts/ and tests/
 *   - JSON.parse on every translation file under src/i18n/
 *
 * Usage: node scripts/check-syntax.js   (npm run check)
 * Exit code 1 when any file fails.
 */
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const JS_DIRS = ['src', 'scripts', 'tests'];
const JSON_DIRS = ['src/i18n'];

function walk(dir, ext, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name.startsWith('.')) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, ext, out);
    else if (entry.isFile() && full.endsWith(ext)) out.push(full);
  }
  return out;
}

function checkJs(file) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, ['--check', file], { stdio: ['ignore', 'ignore', 'pipe'] });
    let stderr = '';
    child.stderr.on('data', (d) => {
      stderr += d;
    });
    child.on('close', (code) => resolve({ file, ok: code === 0, error: stderr.trim() }));
    child.on('error', (err) => resolve({ file, ok: false, error: err.message }));
  });
}

async function runPool(items, worker, concurrency) {
  const results = [];
  let next = 0;
  async function lane() {
    while (next < items.length) {
      const i = next++;
      results[i] = await worker(items[i]);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, lane));
  return results;
}

const jsFiles = JS_DIRS.flatMap((d) => walk(path.join(root, d), '.js')).sort();
const jsonFiles = JSON_DIRS.flatMap((d) => walk(path.join(root, d), '.json')).sort();

const jsResults = await runPool(jsFiles, checkJs, Math.max(2, os.availableParallelism?.() ?? os.cpus().length));
const jsonResults = jsonFiles.map((file) => {
  try {
    JSON.parse(fs.readFileSync(file, 'utf8'));
    return { file, ok: true };
  } catch (err) {
    return { file, ok: false, error: err.message };
  }
});

const failures = [...jsResults, ...jsonResults].filter((r) => !r.ok);
for (const f of failures) {
  console.error(`\n✗ ${path.relative(root, f.file)}\n${f.error}`);
}
console.log(
  `\nSyntax check: ${jsResults.length} JS file(s), ${jsonResults.length} JSON file(s) — ` +
    (failures.length ? `${failures.length} failed` : 'all OK'),
);
process.exit(failures.length ? 1 : 0);
