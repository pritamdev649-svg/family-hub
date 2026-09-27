/**
 * Uploads: docs/03-API_CONTRACT.md §12 (`POST /uploads/signature`).
 *
 * Covers the signed-upload payload (exact keys, family folder, fresh timestamp, SHA-1 signature
 * that binds folder + timestamp to the API secret), the permission matrix (admin / member / other
 * family / no family / no, malformed or expired token), 422 `details` for every kind of bad
 * `folder` (including path-injection attempts into another family's folder), malformed JSON,
 * unknown routes, `Cache-Control: no-store`, the 30 / minute / user rate limit, and the contract
 * addition `503 UPLOADS_NOT_CONFIGURED`.
 *
 * Two things cannot be observed in a normal test process, because `config/env.js` is frozen at
 * import time:
 *   1. Rate limiters are skipped in tests unless RATE_LIMIT_IN_TEST=true. This file sets it
 *      before `helpers.js` loads the app, so every limiter is live here. Request budget per
 *      minute: auth limiter 20 / IP (this file registers 8 users), global limiter 300 / IP (the
 *      file sends ~170 requests), uploads limiter 30 / user. Every user except `limited` and
 *      `racer` (which exceed it on purpose) stays below 30 signature requests; `fuzzer` is the
 *      tightest (~25). Exhaustive hostile-value lists therefore run against the zod schema, and
 *      only representatives go over HTTP.
 *   2. `services/cloudinary.js` uses fixed fake credentials in test mode, so "not configured"
 *      never happens in-process. Those cases run the real app in a child process with
 *      NODE_ENV=development against this file's in-memory MongoDB (see `runInChild`).
 *
 * The module is stateless (nothing is stored), so users are registered once and the database is
 * not reset between tests.
 */
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { after, before, describe, it } from 'node:test';
import { promisify } from 'node:util';
import zlib from 'node:zlib';
import jwt from 'jsonwebtoken';

process.env.RATE_LIMIT_IN_TEST = 'true';

const { API, authHeader, joinFamilyAs, registerFamilyAdmin, setupTestApp, teardownTestApp } = await import('./helpers.js');
const { default: mongoose } = await import('mongoose');
const { env } = await import('../src/config/env.js');
const { ApiError } = await import('../src/lib/ApiError.js');
const { JWT_AUDIENCE, JWT_ISSUER, UPLOAD_FOLDERS } = await import('../src/lib/constants.js');
const { localizeError } = await import('../src/middleware/error.js');
const { Member, User } = await import('../src/models/index.js');
const { signAccessToken } = await import('../src/services/tokens.js');
const { SIGNATURE_RATE_LIMIT_PER_MINUTE } = await import('../src/modules/uploads/uploads.routes.js');
const { signatureBody } = await import('../src/modules/uploads/uploads.schemas.js');
const { UPLOADS_NOT_CONFIGURED, createSignature, uploadsNotConfigured } = await import(
  '../src/modules/uploads/uploads.service.js'
);

const execFileAsync = promisify(execFile);

const URL_SIGNATURE = `${API}/uploads/signature`;
const SIGNATURE_KEYS = ['apiKey', 'cloudName', 'folder', 'signature', 'timestamp'];
const SHA1_HEX = /^[a-f0-9]{40}$/;
const OTHER_FAMILY_ID = 'aaaaaaaaaaaaaaaaaaaaaaaa';

let request;
/** The in-process HTTP server (see `serverUrl`). */
let ctxServer;
/** Admin of family A. */
let admin;
/** Member (role `member`) of family A. */
let member;
/** Admin of family B. */
let other;
/** Signed-in user who left family A after the token was issued (no family now). */
let loner;
/** Member of family A used only by the rate-limit test (its own 30 / minute budget). */
let limited;
/** Member of family A used only by the hostile-input test (its own 30 / minute budget). */
let fuzzer;
/** Member of family A who is removed and then joins family B while keeping the same access token. */
let mover;
/** Member of family A used only by the concurrent rate-limit test. */
let racer;

before(async () => {
  ({ request, server: ctxServer } = await setupTestApp());
  admin = await registerFamilyAdmin();
  member = await joinFamilyAs(admin.family.inviteCode, { name: 'Priya Sharma' });
  other = await registerFamilyAdmin({ name: 'Maria Lopez', family: { name: 'Lopez Family', country: 'ES', currency: 'EUR', timezone: 'Europe/Madrid' } });
  loner = await joinFamilyAs(admin.family.inviteCode, { name: 'Ravi Sharma' });
  limited = await joinFamilyAs(admin.family.inviteCode, { name: 'Kabir Sharma' });
  fuzzer = await joinFamilyAs(admin.family.inviteCode, { name: 'Meera Sharma' });
  mover = await joinFamilyAs(admin.family.inviteCode, { name: 'Arjun Sharma' });
  racer = await joinFamilyAs(admin.family.inviteCode, { name: 'Diya Sharma' });

  // "Left the family": member row gone, user unlinked — the access token is still valid.
  await Member.deleteOne({ _id: loner.member.id });
  await User.updateOne({ _id: loner.user.id }, { $set: { familyId: null, memberId: null } });
});
after(teardownTestApp);

// ---------------------------------------------------------------- helpers

const familyFolder = (familyId, folder) => `familyhub/${familyId}/${folder}`;
const nowSeconds = () => Math.floor(Date.now() / 1000);
/** The fixed fake API secret `services/cloudinary.js` signs with in test mode. */
const TEST_API_SECRET = 'test-secret';

/** Base URL of the in-process test server (for raw `fetch` bodies supertest would re-encode). */
function serverUrl(pathname) {
  const { port } = ctxServer.address();
  return `http://127.0.0.1:${port}${pathname}`;
}

/** Pass as `body` to send no body at all. */
const NO_BODY = Symbol('no body');

function sign(user, body = { folder: 'avatars' }) {
  const req = request.post(URL_SIGNATURE);
  if (user) req.set(user.auth);
  return body === NO_BODY ? req : req.send(body);
}

function assertOk(res, status = 200) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.deepEqual(Object.keys(res.body).sort(), ['data', 'success']);
  assert.equal(res.body.success, true);
  return res.body.data;
}

function assertError(res, status, code) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.equal(res.body.success, false);
  assert.ok(!('data' in res.body));
  assert.ok(!('meta' in res.body));
  assert.equal(res.body.error.code, code);
  assert.equal(typeof res.body.error.message, 'string');
  assert.ok(res.body.error.message.length > 0);
  assert.ok(!('stack' in res.body.error));
  return res.body.error;
}

/** 422 VALIDATION_ERROR with `details[path]`. */
function assertValidation(res, pathKey = 'folder') {
  const error = assertError(res, 422, 'VALIDATION_ERROR');
  assert.equal(typeof error.details?.[pathKey], 'string', JSON.stringify(res.body));
  return error;
}

/** Contract §12 payload for `familyId` / `folder`, signed within [t0, t1]. */
function assertSignature(data, { familyId, folder, t0, t1 }) {
  assert.deepEqual(Object.keys(data).sort(), SIGNATURE_KEYS);
  assert.equal(typeof data.cloudName, 'string');
  assert.ok(data.cloudName.length > 0);
  assert.equal(typeof data.apiKey, 'string');
  assert.ok(data.apiKey.length > 0);
  assert.ok(Number.isInteger(data.timestamp), 'timestamp is integer seconds');
  if (t0 !== undefined) assert.ok(data.timestamp >= t0 && data.timestamp <= t1, `timestamp ${data.timestamp} ∉ [${t0}, ${t1}]`);
  assert.match(data.signature, SHA1_HEX);
  assert.equal(data.folder, familyFolder(familyId, folder));
}

/** Cloudinary's documented scheme: SHA-1 of the sorted `key=value` pairs joined by `&` + API secret. */
function cloudinarySignature(params, apiSecret) {
  const toSign = Object.keys(params)
    .sort()
    .map((key) => `${key}=${params[key]}`)
    .join('&');
  return crypto.createHash('sha1').update(toSign + apiSecret).digest('hex');
}

// ---------------------------------------------------------------- child process (real configuration)

const MARKER = '__FH_UPLOADS_CHILD_RESULT__';

/**
 * Runs in a separate Node process with NODE_ENV=development: boots the real app against this
 * file's in-memory MongoDB, performs the given requests and prints the results after MARKER.
 */
const CHILD_SCRIPT = `
import http from 'node:http';
const { connectDb, disconnectDb } = await import(process.env.FH_DB_MODULE);
const { createApp } = await import(process.env.FH_APP_MODULE);
await connectDb(process.env.MONGODB_URI);
const server = http.createServer(createApp());
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const base = 'http://127.0.0.1:' + server.address().port;
const results = [];
for (const r of JSON.parse(process.env.FH_REQUESTS)) {
  const res = await fetch(base + r.path, { method: r.method, headers: r.headers, body: r.body });
  results.push({ status: res.status, headers: Object.fromEntries(res.headers), text: await res.text() });
}
process.stdout.write('\\n' + process.env.FH_MARKER + JSON.stringify(results) + '\\n');
server.closeAllConnections();
server.close();
await disconnectDb();
process.exit(0);
`;

function mongoUri() {
  const { host, port, name } = mongoose.connection;
  assert.ok(host && port && name, 'mongoose must be connected');
  return `mongodb://${host}:${port}/${name}`;
}

/** Request description for `runInChild`. */
function childSign(user, body = { folder: 'avatars' }, locale = 'en') {
  const headers = { 'Content-Type': 'application/json', 'Accept-Language': locale };
  if (user) headers.Authorization = authHeader(user.tokens).Authorization;
  return { method: 'POST', path: URL_SIGNATURE, headers, body: JSON.stringify(body) };
}

/**
 * @param {{ cloudName?: string, apiKey?: string, apiSecret?: string }} cloudinary credentials for the child
 * @param {object[]} requests built with `childSign`
 * @returns {Promise<{ status: number, headers: Record<string, string>, text: string, body: any }[]>}
 */
async function runInChild(cloudinary, requests) {
  // Empty working directory: no developer `.env` can leak real credentials into the child.
  const cwd = await fs.mkdtemp(path.join(os.tmpdir(), 'fh-uploads-'));
  const childEnv = {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    TMPDIR: process.env.TMPDIR,
    SystemRoot: process.env.SystemRoot,
    NODE_ENV: 'development',
    LOG_LEVEL: 'silent',
    MONGODB_URI: mongoUri(),
    JWT_ACCESS_SECRET: env.JWT_ACCESS_SECRET,
    CLOUDINARY_CLOUD_NAME: cloudinary.cloudName ?? '',
    CLOUDINARY_API_KEY: cloudinary.apiKey ?? '',
    CLOUDINARY_API_SECRET: cloudinary.apiSecret ?? '',
    FH_DB_MODULE: new URL('../src/config/db.js', import.meta.url).href,
    FH_APP_MODULE: new URL('../src/app.js', import.meta.url).href,
    FH_REQUESTS: JSON.stringify(requests),
    FH_MARKER: MARKER,
  };
  try {
    const { stdout } = await execFileAsync(process.execPath, ['--input-type=module', '-e', CHILD_SCRIPT], {
      cwd,
      env: Object.fromEntries(Object.entries(childEnv).filter(([, v]) => v !== undefined)),
      timeout: 60_000,
      maxBuffer: 10 * 1024 * 1024,
    });
    const line = stdout.split('\n').find((l) => l.startsWith(MARKER));
    assert.ok(line, `child printed no result:\n${stdout}`);
    return JSON.parse(line.slice(MARKER.length)).map((r) => ({ ...r, body: JSON.parse(r.text) }));
  } finally {
    await fs.rm(cwd, { recursive: true, force: true });
  }
}

// ---------------------------------------------------------------- happy paths

describe('POST /uploads/signature — happy paths', () => {
  it('admin: 200 with the contract payload for the family avatars folder, never cached', async () => {
    const t0 = nowSeconds();
    const res = await sign(admin, { folder: 'avatars' });
    const t1 = nowSeconds();
    const data = assertOk(res);
    assertSignature(data, { familyId: admin.family.id, folder: 'avatars', t0, t1 });
    assert.match(res.headers['cache-control'] ?? '', /no-store/);
    assert.match(res.headers['content-type'], /application\/json/);
    assert.ok(!res.text.includes(TEST_API_SECRET), 'API secret must never be returned');
    assert.ok(!/secret/i.test(res.text), 'no secret-like field in the payload');
  });

  it('admin and member can sign both folders (avatars, notices) of their own family', async () => {
    assert.deepEqual([...UPLOAD_FOLDERS], ['avatars', 'notices']);
    for (const user of [admin, member]) {
      for (const folder of UPLOAD_FOLDERS) {
        const t0 = nowSeconds();
        const data = assertOk(await sign(user, { folder }));
        assertSignature(data, { familyId: admin.family.id, folder, t0, t1: nowSeconds() });
      }
    }
  });

  it('another family signs into its own folder only', async () => {
    assert.notEqual(other.family.id, admin.family.id);
    for (const folder of UPLOAD_FOLDERS) {
      const data = assertOk(await sign(other, { folder }));
      assertSignature(data, { familyId: other.family.id, folder });
      assert.ok(!data.folder.includes(admin.family.id));
    }
  });

  it('unknown body keys (familyId, public_id, timestamp, signature, …) are ignored', async () => {
    const t0 = nowSeconds();
    const data = assertOk(
      await sign(other, {
        folder: 'notices',
        familyId: admin.family.id,
        public_id: `familyhub/${admin.family.id}/avatars/x`,
        timestamp: 1,
        signature: 'f'.repeat(40),
        cloudName: 'evil',
        apiKey: 'evil',
      }),
    );
    assertSignature(data, { familyId: other.family.id, folder: 'notices', t0, t1: nowSeconds() });
    assert.notEqual(data.cloudName, 'evil');
    assert.notEqual(data.apiKey, 'evil');
    assert.notEqual(data.signature, 'f'.repeat(40));
  });

  it('parallel requests all succeed (stateless, no shared counters besides the rate limit)', async () => {
    const results = await Promise.all(Array.from({ length: 5 }, (_, i) => sign(admin, { folder: UPLOAD_FOLDERS[i % 2] })));
    for (const [i, res] of results.entries()) {
      assertSignature(assertOk(res), { familyId: admin.family.id, folder: UPLOAD_FOLDERS[i % 2] });
    }
  });
});

// ---------------------------------------------------------------- permissions

describe('POST /uploads/signature — authentication & family scoping', () => {
  it('no token → 401 UNAUTHORIZED', async () => {
    assertError(await sign(null), 401, 'UNAUTHORIZED');
  });

  it('malformed token / wrong scheme → 401 UNAUTHORIZED', async () => {
    for (const header of ['Bearer not-a-jwt', `Basic ${Buffer.from('a:b').toString('base64')}`, 'Bearer']) {
      const res = await request.post(URL_SIGNATURE).set('Authorization', header).send({ folder: 'avatars' });
      assertError(res, 401, 'UNAUTHORIZED');
    }
  });

  it('expired token → 401 TOKEN_EXPIRED', async () => {
    const expired = jwt.sign({ exp: nowSeconds() - 10 }, env.JWT_ACCESS_SECRET, {
      subject: admin.user.id,
      issuer: JWT_ISSUER,
      audience: JWT_AUDIENCE,
    });
    const res = await request.post(URL_SIGNATURE).set(authHeader(expired)).send({ folder: 'avatars' });
    assertError(res, 401, 'TOKEN_EXPIRED');
  });

  it('signed in without a family (left / removed) → 403 NO_FAMILY, checked before the body', async () => {
    assertError(await sign(loner, { folder: 'avatars' }), 403, 'NO_FAMILY');
    assertError(await sign(loner, { folder: 'secrets' }), 403, 'NO_FAMILY');
  });

  it("other family: no body shape can target family A's folder (422, never a signature)", async () => {
    // There is no resource id on this endpoint, so "other family → 404" has no equivalent:
    // the folder is always derived from the caller's token and path-like folders are rejected.
    for (const folder of [familyFolder(admin.family.id, 'avatars'), `../${admin.family.id}/avatars`, `${admin.family.id}/notices`]) {
      assertValidation(await sign(other, { folder }));
    }
  });

  it('forged / foreign tokens → 401 UNAUTHORIZED (alg none, wrong secret / issuer / audience, unknown user, refresh token)', async () => {
    // Every token names `racer` (or a user that does not exist). None of them may count
    // against racer's signature budget: the concurrent rate-limit test below proves racer still
    // gets exactly 30 signatures, so an attacker cannot lock a victim out without their token.
    const claims = { issuer: JWT_ISSUER, audience: JWT_AUDIENCE };
    const forged = [
      jwt.sign({}, null, { ...claims, algorithm: 'none', subject: racer.user.id }),
      jwt.sign({}, 'not-the-server-secret-not-the-server-secret', { ...claims, subject: racer.user.id }),
      jwt.sign({}, env.JWT_ACCESS_SECRET, { ...claims, algorithm: 'HS512', subject: racer.user.id }),
      jwt.sign({}, env.JWT_ACCESS_SECRET, { issuer: 'someone-else', audience: JWT_AUDIENCE, subject: racer.user.id }),
      jwt.sign({}, env.JWT_ACCESS_SECRET, { issuer: JWT_ISSUER, audience: 'someone-else', subject: racer.user.id }),
      jwt.sign({}, env.JWT_ACCESS_SECRET, { ...claims, subject: 'bbbbbbbbbbbbbbbbbbbbbbbb' }), // no such user
      jwt.sign({}, env.JWT_ACCESS_SECRET, { ...claims, subject: 'aaaaaaaaaaaa' }), // 12-char "ObjectId"
      jwt.sign({ sub: { $ne: null } }, env.JWT_ACCESS_SECRET, claims), // operator object as subject
      racer.tokens.refreshToken, // opaque refresh token is not an access token
    ];
    for (const token of forged) {
      assertError(await request.post(URL_SIGNATURE).set(authHeader(token)).send({ folder: 'avatars' }), 401, 'UNAUTHORIZED');
    }
    // Two credentials in one header are ambiguous → refused.
    const doubled = await request
      .post(URL_SIGNATURE)
      .set('Authorization', `Bearer ${racer.tokens.accessToken} ${other.tokens.accessToken}`)
      .send({ folder: 'avatars' });
    assertError(doubled, 401, 'UNAUTHORIZED');
  });

  it('the family is re-read on every request: removed mid-session → 403, joined family B → only B\'s folder', async () => {
    // Same access token throughout (it only carries the user id, never the family).
    assertSignature(assertOk(await sign(mover, { folder: 'avatars' })), { familyId: admin.family.id, folder: 'avatars' });

    // Removed from family A (what DELETE /family/members/:id does: member row gone, user unlinked).
    await Member.deleteOne({ _id: mover.member.id });
    await User.updateOne({ _id: mover.user.id }, { $set: { familyId: null, memberId: null } });
    assertError(await sign(mover, { folder: 'avatars' }), 403, 'NO_FAMILY');

    // Joins family B (what POST /family/join does).
    const joined = await Member.create({ familyId: other.family.id, userId: mover.user.id, name: 'Arjun Sharma', role: 'member' });
    await User.updateOne({ _id: mover.user.id }, { $set: { familyId: other.family.id, memberId: joined._id } });
    for (const folder of UPLOAD_FOLDERS) {
      const data = assertOk(await sign(mover, { folder, familyId: admin.family.id }));
      assertSignature(data, { familyId: other.family.id, folder });
      assert.ok(!data.folder.includes(admin.family.id), 'never the old family');
    }
  });

  it('stale link (user points at family A but the member row belongs elsewhere) → 403 NO_FAMILY', async () => {
    // mover's member row is in family B now; pointing the user back at family A must not
    // resurrect access to A's folder.
    const { memberId } = await User.findById(mover.user.id).select('memberId').lean();
    await User.updateOne({ _id: mover.user.id }, { $set: { familyId: admin.family.id } });
    try {
      assertError(await sign(mover, { folder: 'avatars' }), 403, 'NO_FAMILY');
    } finally {
      await User.updateOne({ _id: mover.user.id }, { $set: { familyId: other.family.id, memberId } });
    }
  });
});

// ---------------------------------------------------------------- validation

describe('POST /uploads/signature — validation', () => {
  it('missing folder ({} / no body / non-JSON body) → 422 details.folder "required"', async () => {
    const empty = assertValidation(await sign(member, {}));
    assert.match(empty.details.folder, /required/i);
    assertValidation(await sign(member, NO_BODY));
    const text = await request.post(URL_SIGNATURE).set(member.auth).set('Content-Type', 'text/plain').send('folder=avatars');
    assertValidation(text);
  });

  it('every value outside the contract enum → 422 details.folder listing the choices', async () => {
    const invalid = [
      'secrets',
      'AVATARS',
      'Notices',
      ' avatars',
      'avatars ',
      'avatars/',
      'avatars/sub',
      '../avatars',
      'familyhub/avatars',
      '',
      null,
      42,
      true,
      ['avatars'],
      { value: 'avatars' },
    ];
    for (const folder of invalid) {
      const error = assertValidation(await sign(member, { folder }));
      assert.match(error.details.folder, /avatars, notices/, `folder=${JSON.stringify(folder)}`);
    }
  });

  it('non-object JSON body → 422 (array) or 400 BAD_REQUEST (primitive / malformed JSON)', async () => {
    assertValidation(await sign(admin, []), 'body');
    const primitive = await request.post(URL_SIGNATURE).set(admin.auth).set('Content-Type', 'application/json').send('"avatars"');
    assertError(primitive, 400, 'BAD_REQUEST');
    const malformed = await request.post(URL_SIGNATURE).set(admin.auth).set('Content-Type', 'application/json').send('{"folder":');
    assertError(malformed, 400, 'BAD_REQUEST');
  });
});

// ---------------------------------------------------------------- hostile input

/** Every value here must be refused by `signatureBody` with `details.folder`. */
const HOSTILE_FOLDERS = [
  // look-alikes / invisible characters / bidi controls (NFC, zero-width, BOM, soft hyphen)
  'аvatars', // Cyrillic а
  'avatarѕ', // Cyrillic ѕ
  'nоtices', // Cyrillic о
  'notıces', // dotless ı
  'ａｖａｔａｒｓ', // full-width
  'ᴀᴠᴀᴛᴀʀꜱ', // small capitals
  'avatars\u0000',
  '\u0000avatars',
  'avatars​',
  '​avatars',
  'ava‍tars',
  'avatars­',
  '﻿avatars',
  '‮avatars',
  '⁦avatars⁩',
  'avatars ',
  'avatars\n',
  '\tavatars',
  'avatars\r\n',
  // case / near misses
  'NOTICES',
  'Avatars',
  'avatarS',
  'avatar',
  'avatarss',
  'notice',
  'avatarsavatars',
  // paths, encodings, separators, wildcards
  '.',
  '..',
  '/',
  'avatars.',
  'avatars/..',
  'avatars\\..\\..',
  '..\\avatars',
  '%2e%2e%2favatars',
  'avatars%2F..',
  'avatar%73',
  'avatars?folder=notices',
  'avatars#',
  'avatars;notices',
  'avatars&folder=notices',
  'avatars,notices',
  'avatars notices',
  '*',
  '${folder}',
  'familyhub/aaaaaaaaaaaaaaaaaaaaaaaa/avatars',
  // other scripts / emoji
  '📷',
  '🧑‍🧑‍🧒',
  'صور',
  'אווטאר',
  'अवतार',
  '头像',
  'a'.repeat(10_000),
  // numbers and other JSON types
  0,
  -1,
  1e13,
  0.1 + 0.2,
  Number.NaN,
  Number.POSITIVE_INFINITY,
  -0,
  true,
  false,
  null,
  undefined,
  [],
  ['avatars'],
  ['avatars', 'notices'],
  {},
  { 0: 'avatars' },
  // NoSQL operators
  { $ne: null },
  { $in: ['avatars'] },
  { $regex: '^a' },
  { $gt: '' },
  { $exists: true },
];

describe('POST /uploads/signature — hostile input', () => {
  it('schema: every hostile folder value is refused with details.folder; only the exact values pass', () => {
    for (const folder of HOSTILE_FOLDERS) {
      const result = signatureBody.safeParse({ folder });
      assert.equal(result.success, false, `accepted folder=${JSON.stringify(folder)}`);
      assert.deepEqual(result.error.issues[0].path, ['folder'], `folder=${JSON.stringify(folder)}`);
    }
    for (const folder of UPLOAD_FOLDERS) {
      assert.deepEqual(signatureBody.parse({ folder }), { folder });
    }
  });

  it('schema: mass assignment and prototype keys are stripped, never inherited', () => {
    const polluted = JSON.parse(
      `{"folder":"notices","familyId":"${admin.family.id}","role":"admin","__proto__":{"folder":"avatars","familyId":"${admin.family.id}"},"constructor":{"prototype":{"familyId":"x"}}}`,
    );
    const data = signatureBody.parse(polluted);
    assert.deepEqual(Object.keys(data), ['folder']);
    assert.equal(data.folder, 'notices');
    assert.equal(Object.getPrototypeOf(data), Object.prototype);
    assert.equal(data.familyId, undefined);
    assert.equal({}.familyId, undefined, 'Object.prototype must stay clean');

    // `folder` only inside __proto__ → it is *missing*, not inherited.
    const inherited = signatureBody.safeParse(JSON.parse('{"__proto__":{"folder":"avatars"}}'));
    assert.equal(inherited.success, false);
  });

  it('HTTP: operator objects, look-alikes, control characters and numbers → 422 details.folder', async () => {
    const representatives = [{ $ne: null }, { $in: ['avatars'] }, 'аvatars', 'avatars​', 'avatars\u0000', '‮avatars', '📷', 'ａｖａｔａｒｓ', 0, 1e13];
    for (const folder of representatives) {
      const error = assertValidation(await sign(fuzzer, { folder }));
      assert.equal(error.details.folder, 'Must be one of: avatars, notices', `folder=${JSON.stringify(folder)}`);
    }
    // JSON-only literals that JSON.stringify cannot produce.
    for (const raw of ['{"folder":1e999}', '{"folder":-1e999}', '{"folder":"NaN"}']) {
      const res = await request.post(URL_SIGNATURE).set(fuzzer.auth).set('Content-Type', 'application/json').send(raw);
      assertValidation(res);
    }
  });

  it('HTTP: prototype pollution / duplicate keys cannot change the folder or the family', async () => {
    const raw = (body) => request.post(URL_SIGNATURE).set(fuzzer.auth).set('Content-Type', 'application/json').send(body);

    assertValidation(await raw('{"__proto__":{"folder":"avatars"}}'));
    assertValidation(await raw('{"constructor":{"prototype":{"folder":"avatars"}}}'));
    const polluted = assertOk(await raw(`{"folder":"notices","__proto__":{"familyId":"${other.family.id}","folder":"avatars"}}`));
    assertSignature(polluted, { familyId: admin.family.id, folder: 'notices' });
    assert.equal({}.familyId, undefined, 'Object.prototype must stay clean');
    assert.equal({}.folder, undefined, 'Object.prototype must stay clean');

    // JSON.parse keeps the *last* duplicate: whatever wins is validated like any other value.
    assertSignature(assertOk(await raw('{"folder":"../x","folder":"avatars"}')), { familyId: admin.family.id, folder: 'avatars' });
    assertValidation(await raw('{"folder":"avatars","folder":"../x"}'));
  });

  it('HTTP: the folder is read from the JSON body only (query string / form bodies are ignored)', async () => {
    assertValidation(await request.post(`${URL_SIGNATURE}?folder=avatars`).set(fuzzer.auth).send({}));
    const data = assertOk(
      await request
        .post(`${URL_SIGNATURE}?folder=..%2F..%2F${other.family.id}%2Favatars&familyId=${other.family.id}`)
        .set(fuzzer.auth)
        .send({ folder: 'avatars' }),
    );
    assertSignature(data, { familyId: admin.family.id, folder: 'avatars' });
    const form = await request.post(URL_SIGNATURE).set(fuzzer.auth).type('form').send('folder=avatars');
    assertValidation(form);
  });

  it('HTTP: huge / deeply nested / compressed bodies are bounded (422 without echo, 413 over 100 kb, never 500)', async () => {
    // Just under the 100 kb JSON limit: refused quickly, and the value is not echoed back.
    const big = await sign(fuzzer, { folder: 'a'.repeat(99_000) });
    assertValidation(big);
    assert.ok(big.text.length < 1024, `error echoes the input (${big.text.length} bytes)`);

    // 40 000 levels of nesting (~80 kb): parsed and refused, no stack overflow / 500.
    const deep = `{"folder":${'['.repeat(40_000)}${']'.repeat(40_000)}}`;
    assertValidation(await request.post(URL_SIGNATURE).set(fuzzer.auth).set('Content-Type', 'application/json').send(deep));

    // Over the limit → 413 before authentication (so it never costs a signature).
    const tooLarge = await sign(fuzzer, { folder: 'a'.repeat(200_000) });
    assertError(tooLarge, 413, 'PAYLOAD_TOO_LARGE');

    // A 5 MB body gzip-compressed to ~5 kb: the limit applies to the *inflated* size.
    const bomb = zlib.gzipSync(Buffer.from(JSON.stringify({ folder: 'avatars', pad: 'x'.repeat(5_000_000) })));
    assert.ok(bomb.length < 100_000);
    const res = await fetch(serverUrl(URL_SIGNATURE), {
      method: 'POST',
      headers: { ...fuzzer.auth, 'Content-Type': 'application/json', 'Content-Encoding': 'gzip' },
      body: bomb,
    });
    const body = await res.json();
    assert.equal(res.status, 413, JSON.stringify(body));
    assert.equal(body.error.code, 'PAYLOAD_TOO_LARGE');
  });
});

// ---------------------------------------------------------------- localization

describe('POST /uploads/signature — errors in the caller\'s language', () => {
  it('Accept-Language wins: 422 message is the localized VALIDATION_ERROR text, Content-Language set', async () => {
    const res = await request.post(URL_SIGNATURE).set(other.auth).set('Accept-Language', 'hi-IN,hi;q=0.9,en;q=0.5').send({ folder: 'x' });
    const error = assertValidation(res);
    assert.equal(res.headers['content-language'], 'hi');
    assert.equal(error.message, localizeError(ApiError.validation({}), 'hi'));
  });

  it("no Accept-Language: the user's saved locale is used (403 NO_FAMILY in Arabic)", async () => {
    await User.updateOne({ _id: loner.user.id }, { $set: { locale: 'ar' } });
    try {
      const res = await sign(loner, { folder: 'avatars' });
      const error = assertError(res, 403, 'NO_FAMILY');
      assert.equal(res.headers['content-language'], 'ar');
      assert.equal(error.message, localizeError(ApiError.noFamily(), 'ar'));
    } finally {
      await User.updateOne({ _id: loner.user.id }, { $set: { locale: 'en' } });
    }
  });
});

// ---------------------------------------------------------------- routes & service

describe('uploads routes & service', () => {
  it('only POST /uploads/signature exists → other methods / paths are 404 NOT_FOUND', async () => {
    assertError(await request.get(URL_SIGNATURE).set(admin.auth), 404, 'NOT_FOUND');
    assertError(await request.put(URL_SIGNATURE).set(admin.auth).send({ folder: 'avatars' }), 404, 'NOT_FOUND');
    assertError(await request.post(`${API}/uploads`).set(admin.auth).send({ folder: 'avatars' }), 404, 'NOT_FOUND');
    assertError(await request.post(`${API}/uploads/avatars`).set(admin.auth).send({}), 404, 'NOT_FOUND');
  });

  it('createSignature returns only the contract fields and keeps the family guard', () => {
    const data = createSignature({ familyId: OTHER_FAMILY_ID }, { folder: 'notices' });
    assertSignature(data, { familyId: OTHER_FAMILY_ID, folder: 'notices' });
    assert.throws(() => createSignature({ familyId: null }, { folder: 'avatars' }), { code: 'NO_FAMILY', status: 403 });
    assert.throws(() => createSignature({ familyId: OTHER_FAMILY_ID }, { folder: 'secrets' }), { code: 'VALIDATION_ERROR', status: 422 });
  });

  it('createSignature re-checks family and folder before the signer runs', () => {
    let calls = 0;
    const sign = () => {
      calls += 1;
      throw new Error('must not be called');
    };
    for (const user of [null, undefined, {}, { familyId: null }, { familyId: '' }]) {
      assert.throws(() => createSignature(user, { folder: 'avatars' }, { sign }), { code: 'NO_FAMILY', status: 403 });
    }
    for (const folder of ['secrets', '../avatars', `familyhub/${OTHER_FAMILY_ID}/avatars`, undefined, { $ne: null }]) {
      assert.throws(() => createSignature({ familyId: OTHER_FAMILY_ID }, { folder }, { sign }), { code: 'VALIDATION_ERROR', status: 422 });
    }
    assert.throws(() => createSignature({ familyId: OTHER_FAMILY_ID }, undefined, { sign }), { code: 'VALIDATION_ERROR' });
    assert.equal(calls, 0);
  });

  it('createSignature maps "not configured" to 503 UPLOADS_NOT_CONFIGURED and passes other errors through', () => {
    const notConfigured = ApiError.serviceUnavailable('Image uploads are not configured');
    assert.throws(
      () => createSignature({ familyId: OTHER_FAMILY_ID }, { folder: 'avatars' }, { sign: () => { throw notConfigured; } }),
      (err) => err.status === 503 && err.code === UPLOADS_NOT_CONFIGURED && err.cause === notConfigured,
    );
    const boom = new Error('boom');
    assert.throws(() => createSignature({ familyId: OTHER_FAMILY_ID }, { folder: 'avatars' }, { sign: () => { throw boom; } }), (err) => err === boom);
    const forbidden = ApiError.forbidden();
    assert.throws(() => createSignature({ familyId: OTHER_FAMILY_ID }, { folder: 'avatars' }, { sign: () => { throw forbidden; } }), (err) => err === forbidden);
  });

  it('createSignature never hands out a signature for another folder / family or a malformed payload (500, signature withheld)', () => {
    const familyId = OTHER_FAMILY_ID;
    const good = { cloudName: 'demo', apiKey: '1234', timestamp: nowSeconds(), signature: 'a'.repeat(40), folder: familyFolder(familyId, 'avatars') };
    const bad = [
      { ...good, folder: familyFolder('bbbbbbbbbbbbbbbbbbbbbbbb', 'avatars') }, // another family
      { ...good, folder: familyFolder(familyId, 'notices') }, // another folder
      { ...good, folder: `${familyFolder(familyId, 'avatars')}/../../bbbbbbbbbbbbbbbbbbbbbbbb/avatars` },
      { ...good, folder: 'familyhub' },
      { ...good, folder: undefined },
      { ...good, timestamp: String(good.timestamp) },
      { ...good, timestamp: 0 },
      { ...good, timestamp: 1.5 },
      { ...good, signature: '' },
      { ...good, signature: 'not-hex-not-hex-not-hex-not-hex-not-hex!' },
      { ...good, signature: 'A'.repeat(40) },
      { ...good, signature: 'a'.repeat(41) },
      null,
      'signature',
    ];
    for (const signed of bad) {
      assert.throws(
        () => createSignature({ familyId }, { folder: 'avatars' }, { sign: () => signed }),
        (err) => err.status === 500 && err.code === 'INTERNAL_ERROR' && !JSON.stringify({ ...err, message: err.message }).includes('a'.repeat(40)),
        `accepted ${JSON.stringify(signed)}`,
      );
    }
  });

  it('createSignature: blank / malformed cloud name or API key → 503 UPLOADS_NOT_CONFIGURED (never a URL the app cannot use)', () => {
    const familyId = OTHER_FAMILY_ID;
    const good = { cloudName: 'demo', apiKey: '1234', timestamp: nowSeconds(), signature: 'c'.repeat(40), folder: familyFolder(familyId, 'avatars') };
    const broken = [
      { cloudName: '' },
      { cloudName: '   ' },
      { cloudName: 'demo\n' },
      { cloudName: 'my cloud' },
      { cloudName: '../evil' },
      { cloudName: 'evil/image/upload?x=' },
      { cloudName: 'a'.repeat(129) },
      { cloudName: null },
      { cloudName: 42 },
      { apiKey: '' },
      { apiKey: ' 1234' },
      { apiKey: null },
      { apiKey: 1234 },
    ];
    for (const patch of broken) {
      const signed = { ...good, ...patch };
      assert.throws(
        () => createSignature({ familyId }, { folder: 'avatars' }, { sign: () => signed }),
        (err) => err.status === 503 && err.code === UPLOADS_NOT_CONFIGURED,
        `accepted ${JSON.stringify(patch)}`,
      );
    }
    // Real-world shapes still pass.
    for (const creds of [{ cloudName: 'fh-test-cloud', apiKey: '987654321012345' }, { cloudName: 'My_Cloud-2', apiKey: 'abcDEF_123-x' }]) {
      assertSignature(createSignature({ familyId }, { folder: 'avatars' }, { sign: () => ({ ...good, ...creds }) }), { familyId, folder: 'avatars' });
    }
  });

  it('createSignature copies only the five contract fields (an extra secret from the signer cannot leak)', () => {
    const familyId = OTHER_FAMILY_ID;
    let received;
    const data = createSignature(
      { familyId, role: 'admin', email: 'x@example.com' },
      { folder: 'notices', familyId: 'bbbbbbbbbbbbbbbbbbbbbbbb' },
      {
        sign: (opts) => {
          received = opts;
          return {
            cloudName: 'demo',
            apiKey: '1234',
            timestamp: 1_790_000_000,
            signature: 'b'.repeat(64),
            folder: familyFolder(familyId, 'notices'),
            apiSecret: 'leak-me',
            api_secret: 'leak-me',
          };
        },
      },
    );
    assert.deepEqual(received, { familyId, folder: 'notices' });
    assert.deepEqual(Object.keys(data).sort(), SIGNATURE_KEYS);
    assert.ok(!JSON.stringify(data).includes('leak-me'));
  });

  it('uploadsNotConfigured() is a 503 UPLOADS_NOT_CONFIGURED ApiError with a localizable key', () => {
    const err = uploadsNotConfigured();
    assert.equal(UPLOADS_NOT_CONFIGURED, 'UPLOADS_NOT_CONFIGURED');
    assert.equal(err.status, 503);
    assert.equal(err.code, UPLOADS_NOT_CONFIGURED);
    assert.equal(err.messageKey, 'common.errors.UPLOADS_NOT_CONFIGURED');
    assert.ok(err.message.length > 0);
  });
});

// ---------------------------------------------------------------- rate limit

describe('POST /uploads/signature — rate limit (30 / minute / user)', () => {
  it(
    `${SIGNATURE_RATE_LIMIT_PER_MINUTE} signatures per minute per user, then 429 with retryAfterSeconds; other users unaffected`,
    { skip: !env.RATE_LIMIT_IN_TEST && 'rate limiters are disabled in this process' },
    async () => {
      assert.equal(SIGNATURE_RATE_LIMIT_PER_MINUTE, 30);
      for (let i = 1; i <= SIGNATURE_RATE_LIMIT_PER_MINUTE; i += 1) {
        const res = await sign(limited, { folder: 'avatars' });
        assertOk(res);
        const policies = String(res.headers['ratelimit-policy'] ?? '');
        assert.match(policies, /"uploads"; q=30; w=60/);
        assert.match(String(res.headers.ratelimit ?? ''), new RegExp(`"uploads"; r=${SIGNATURE_RATE_LIMIT_PER_MINUTE - i};`));
      }

      const limitedRes = await sign(limited, { folder: 'avatars' });
      const error = assertError(limitedRes, 429, 'TOO_MANY_REQUESTS');
      const seconds = error.details?.retryAfterSeconds;
      assert.ok(Number.isInteger(seconds) && seconds >= 1 && seconds <= 60, `retryAfterSeconds=${seconds}`);
      assert.equal(limitedRes.headers['retry-after'], String(seconds));

      // The limiter runs before validation: invalid bodies are refused as well.
      assertError(await sign(limited, { folder: 'secrets' }), 429, 'TOO_MANY_REQUESTS');

      // Keyed by user, not IP: every test request comes from 127.0.0.1.
      assertSignature(assertOk(await sign(member, { folder: 'notices' })), { familyId: admin.family.id, folder: 'notices' });

      // Once limited, the 429 is localized like every other error.
      const spanish = await sign(limited, { folder: 'avatars' }).set('Accept-Language', 'es');
      const esError = assertError(spanish, 429, 'TOO_MANY_REQUESTS');
      assert.equal(esError.message, localizeError(ApiError.tooManyRequests(esError.details.retryAfterSeconds), 'es'));
    },
  );

  it(
    'concurrent burst: exactly 30 of 35 simultaneous requests are signed; new tokens / spoofed IPs share the same budget',
    { skip: !env.RATE_LIMIT_IN_TEST && 'rate limiters are disabled in this process' },
    async () => {
      const burst = SIGNATURE_RATE_LIMIT_PER_MINUTE + 5;
      const results = await Promise.all(Array.from({ length: burst }, (_, i) => sign(racer, { folder: UPLOAD_FOLDERS[i % 2] })));
      const signed = results.filter((res) => res.status === 200);
      const refused = results.filter((res) => res.status === 429);
      // Also proves the forged-token 401s above never consumed racer's budget.
      assert.equal(signed.length, SIGNATURE_RATE_LIMIT_PER_MINUTE, results.map((r) => r.status).join(','));
      assert.equal(refused.length, burst - SIGNATURE_RATE_LIMIT_PER_MINUTE);
      for (const res of signed) {
        assert.equal(res.body.data.folder.startsWith(`familyhub/${admin.family.id}/`), true);
      }
      for (const res of refused) {
        const error = assertError(res, 429, 'TOO_MANY_REQUESTS');
        assert.equal(res.headers['retry-after'], String(error.details.retryAfterSeconds));
      }

      // The budget belongs to the user, not to one token or one client address.
      const freshToken = signAccessToken(racer.user.id);
      assertError(await request.post(URL_SIGNATURE).set(authHeader(freshToken)).send({ folder: 'avatars' }), 429, 'TOO_MANY_REQUESTS');
      const spoofed = await sign(racer, { folder: 'avatars' }).set('X-Forwarded-For', '203.0.113.7').set('X-Real-IP', '203.0.113.7');
      assertError(spoofed, 429, 'TOO_MANY_REQUESTS');
    },
  );
});

// ---------------------------------------------------------------- Cloudinary configuration

describe('POST /uploads/signature — Cloudinary configuration (child process, NODE_ENV=development)', () => {
  const CONFIGURED = Object.freeze({ cloudName: 'fh-test-cloud', apiKey: '987654321012345', apiSecret: 'child-process-secret-9f8e7d' });
  let notConfigured;
  let partial;
  let configured;
  let blank;
  let padded;
  let window;

  before(async () => {
    const t0 = nowSeconds();
    [notConfigured, partial, configured, blank, padded] = await Promise.all([
      runInChild({}, [
        childSign(admin, { folder: 'avatars' }),
        childSign(member, { folder: 'notices' }),
        childSign(member, { folder: 'secrets' }),
        childSign(loner, { folder: 'avatars' }),
        childSign(null, { folder: 'avatars' }),
        childSign(member, { folder: 'avatars' }, 'hi'),
      ]),
      runInChild({ cloudName: CONFIGURED.cloudName, apiKey: CONFIGURED.apiKey }, [childSign(admin, { folder: 'avatars' })]),
      runInChild(CONFIGURED, [childSign(admin, { folder: 'avatars' }), childSign(other, { folder: 'notices' })]),
      // Typical deployment slips: whitespace-only values, a secret with a trailing newline
      // (e.g. `echo secret | base64` into a Kubernetes secret).
      runInChild({ cloudName: '  ', apiKey: ' ', apiSecret: ' \n' }, [childSign(admin, { folder: 'avatars' })]),
      runInChild({ ...CONFIGURED, apiSecret: `${CONFIGURED.apiSecret}\n` }, [childSign(admin, { folder: 'avatars' })]),
    ]);
    window = { t0, t1: nowSeconds() };
  });

  it('not configured → 503 UPLOADS_NOT_CONFIGURED for admins and members', () => {
    for (const res of notConfigured.slice(0, 2)) {
      const error = assertError(res, 503, UPLOADS_NOT_CONFIGURED);
      assert.ok(!('details' in error));
      assert.ok(!('retry-after' in res.headers), 'retrying cannot help, so no Retry-After');
    }
  });

  it('not configured: 401 / 403 NO_FAMILY / 422 still win (checked before the configuration)', () => {
    assertValidation(notConfigured[2]);
    assertError(notConfigured[3], 403, 'NO_FAMILY');
    assertError(notConfigured[4], 401, 'UNAUTHORIZED');
  });

  it('partially configured (no API secret) → 503 UPLOADS_NOT_CONFIGURED', () => {
    assertError(partial[0], 503, UPLOADS_NOT_CONFIGURED);
  });

  it("not configured: the 503 message follows the caller's language (English fallback until translated)", () => {
    const res = notConfigured[5];
    const error = assertError(res, 503, UPLOADS_NOT_CONFIGURED);
    assert.equal(res.headers['content-language'], 'hi');
    assert.equal(error.message, localizeError(uploadsNotConfigured(), 'hi'));
  });

  it('whitespace-only credentials → 503 UPLOADS_NOT_CONFIGURED, not a payload with a blank cloud name', () => {
    const error = assertError(blank[0], 503, UPLOADS_NOT_CONFIGURED);
    assert.ok(!('details' in error));
    assert.ok(!('retry-after' in blank[0].headers));
  });

  it('a secret with a trailing newline never yields a signature made with the padded secret', () => {
    // Today: 503 UPLOADS_NOT_CONFIGURED (guard in uploads.service.js). Once config/env.js trims
    // CLOUDINARY_* (handoff b-core) the trimmed secret signs correctly — both are acceptable.
    const res = padded[0];
    if (res.status === 503) {
      assertError(res, 503, UPLOADS_NOT_CONFIGURED);
      return;
    }
    const data = assertOk(res);
    assert.equal(data.signature, cloudinarySignature({ folder: data.folder, timestamp: data.timestamp }, CONFIGURED.apiSecret));
  });

  it('configured → the configured cloud/key and a valid Cloudinary signature; the secret never leaves', () => {
    const cases = [
      { res: configured[0], familyId: admin.family.id, folder: 'avatars' },
      { res: configured[1], familyId: other.family.id, folder: 'notices' },
    ];
    for (const { res, familyId, folder } of cases) {
      assert.equal(res.status, 200, res.text);
      assert.equal(res.body.success, true);
      const { data } = res.body;
      assertSignature(data, { familyId, folder, ...window });
      assert.equal(data.cloudName, CONFIGURED.cloudName);
      assert.equal(data.apiKey, CONFIGURED.apiKey);
      assert.equal(data.signature, cloudinarySignature({ folder: data.folder, timestamp: data.timestamp }, CONFIGURED.apiSecret));
      assert.ok(!res.text.includes(CONFIGURED.apiSecret), 'API secret must never be returned');
      assert.match(res.headers['cache-control'] ?? '', /no-store/);
    }
  });
});
