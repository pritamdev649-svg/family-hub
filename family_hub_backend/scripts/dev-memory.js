#!/usr/bin/env node
/**
 * Runs the API on an in-memory MongoDB — no local MongoDB installation needed.
 *
 *   npm run dev:memory            (PORT from .env, default 4000)
 *   DEV_MEMORY_DB_PORT=27018 npm run dev:memory   (fixed DB port, e.g. for MongoDB Compass)
 *
 * Steps: start MongoMemoryServer → set MONGODB_URI → run scripts/seed.js if present →
 * start the server. Data lives only as long as the process.
 *
 * Seeding: seed.js is loaded with a dynamic import. If it exports a function (`seed` or
 * `default`) it is called and awaited. A seed script that calls `process.exit()` while
 * seeding is contained (exit code 0 is ignored, non-zero aborts the start).
 */
import fs from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { MongoMemoryServer } from 'mongodb-memory-server';

if (!process.env.NODE_ENV || process.env.NODE_ENV === 'test') process.env.NODE_ENV = 'development';

const dbPort = process.env.DEV_MEMORY_DB_PORT ? Number(process.env.DEV_MEMORY_DB_PORT) : undefined;
const mongod = await MongoMemoryServer.create({
  instance: { dbName: 'familyhub', ...(dbPort ? { port: dbPort } : {}) },
});
const mongoUri = mongod.getUri('familyhub');
process.env.MONGODB_URI = mongoUri;
console.log(`[dev-memory] In-memory MongoDB running at ${mongoUri}`);

async function stopMongo() {
  try {
    await mongod.stop({ doCleanup: true });
  } catch {
    /* already stopped */
  }
}

class SeedExit extends Error {}

async function runSeed() {
  const seedFile = fileURLToPath(new URL('./seed.js', import.meta.url));
  if (!fs.existsSync(seedFile)) {
    console.log('[dev-memory] scripts/seed.js not found — starting with an empty database');
    return;
  }
  const realExit = process.exit;
  process.exit = (code = 0) => {
    if (Number(code) !== 0) throw new SeedExit(`seed.js exited with code ${code}`);
    console.log('[dev-memory] seed.js called process.exit(0) — ignored');
    return undefined;
  };
  try {
    const mod = await import(pathToFileURL(seedFile).href);
    const fn = typeof mod.seed === 'function' ? mod.seed : typeof mod.default === 'function' ? mod.default : null;
    if (fn) await fn({ mongoUri });
    console.log('[dev-memory] Seed completed');
  } finally {
    process.exit = realExit;
  }
}

try {
  await runSeed();
} catch (err) {
  console.error(`[dev-memory] Seeding failed: ${err?.stack ?? err}`);
  await stopMongo();
  process.exit(1);
}

try {
  const { startServer } = await import('../src/server.js');
  await startServer({ mongoUri, onShutdown: stopMongo });
} catch (err) {
  console.error(`[dev-memory] Failed to start the API: ${err?.stack ?? err}`);
  await stopMongo();
  process.exit(1);
}
