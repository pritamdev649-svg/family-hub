/**
 * Backend foundation: lib/, middleware/, services/ and models/ working together
 * (docs/06-BACKEND_GUIDE.md §3–§5, docs/03-API_CONTRACT.md §1–§2).
 */
import { API, flushPushes, outbox, resetDb, sentPushes, setupTestApp, teardownTestApp } from './helpers.js';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, before, beforeEach, describe, it } from 'node:test';
import express from 'express';
import jwt from 'jsonwebtoken';
import mongoose from 'mongoose';
import supertest from 'supertest';
import { z } from 'zod';

const { env } = await import('../src/config/env.js');
const { ApiError, ErrorCodes } = await import('../src/lib/ApiError.js');
const constants = await import('../src/lib/constants.js');
const enums = await import('../src/models/enums.js');
const cryptoLib = await import('../src/lib/crypto.js');
const money = await import('../src/lib/money.js');
const dates = await import('../src/lib/dates.js');
const i18n = await import('../src/lib/i18n.js');
const v = await import('../src/lib/validate.js');
const { ok, paged } = await import('../src/lib/response.js');
const { paginate, paginateAggregate, paginateArray, normalizePage } = await import('../src/lib/pagination.js');
const { findInFamily, assertSelfOrAdmin, assertAdmin } = await import('../src/lib/access.js');
const { consentAge, isCountry, CURRENCIES, COUNTRIES } = await import('../src/lib/countries.js');
const { errorHandler, notFoundHandler } = await import('../src/middleware/error.js');
const { localeMiddleware } = await import('../src/middleware/locale.js');
const { requireAuth, requireFamily, requireAdmin, familyMember, familyAdmin } = await import('../src/middleware/auth.js');
const tokens = await import('../src/services/tokens.js');
const { sendToMembers } = await import('../src/services/push.js');
const { sendTemplate } = await import('../src/services/mailer.js');
const { serializeUser, serializeFamily, serializeMember, serializeMembers } = await import('../src/services/serializers.js');
const { getMemberMap, nameOf, countAdmins } = await import('../src/services/memberDirectory.js');
const { signUpload, isCloudinaryUrl, isFamilyAssetUrl } = await import('../src/services/cloudinary.js');
const models = await import('../src/models/index.js');
const { User, Family, Member, Device, RefreshToken, Otp, Task, LedgerEntry, Goal, Notice, SosAlert, EmergencyCard } = models;

let request;

before(async () => {
  ({ request } = await setupTestApp());
});
beforeEach(resetDb);
after(teardownTestApp);

// ---------------------------------------------------------------- helpers

function assertErrorEnvelope(res, status, code) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.equal(res.body.success, false);
  assert.equal(res.body.error.code, code);
  assert.equal(typeof res.body.error.message, 'string');
  assert.ok(res.body.error.message.length > 0);
  assert.ok(!('stack' in res.body.error), 'never returns a stack');
}

/** Mini app with the real locale + error middleware around `mount(app)`. */
function miniApp(mount) {
  const app = express();
  app.use(localeMiddleware);
  app.use(express.json({ limit: '100kb' }));
  mount(app);
  app.use(notFoundHandler);
  app.use(errorHandler);
  return supertest(app);
}

let seq = 0;
const unique = (tag) => `${tag}.${++seq}.${Date.now().toString(36)}@example.com`;
const oid = () => new mongoose.Types.ObjectId();

/** A family with an admin (account), a member (account) and a managed profile. */
async function seedFamily(tag = 'fam') {
  const adminUser = await User.create({ email: unique(`${tag}.admin`), passwordHash: 'x', name: 'Admin', locale: 'hi' });
  const family = await Family.create({ name: `${tag} family`, country: 'IN', currency: 'INR', timezone: 'Asia/Kolkata', ownerId: adminUser._id });
  const admin = await Member.create({
    familyId: family._id,
    userId: adminUser._id,
    name: 'Admin',
    role: 'admin',
    dateOfBirth: new Date('1980-01-01'),
    locationSharing: 'always',
    lastLocation: { lat: 1, lng: 2, accuracy: 3 },
  });
  const kidUser = await User.create({ email: unique(`${tag}.kid`), passwordHash: 'x', name: 'Kid', locale: 'ta' });
  const kid = await Member.create({ familyId: family._id, userId: kidUser._id, name: 'Kid', role: 'member', dateOfBirth: new Date('2010-01-01'), lastLocation: { lat: 5, lng: 6 } });
  const managed = await Member.create({ familyId: family._id, name: 'Grandma', role: 'member', dateOfBirth: null });
  await User.updateOne({ _id: adminUser._id }, { familyId: family._id, memberId: admin._id });
  await User.updateOne({ _id: kidUser._id }, { familyId: family._id, memberId: kid._id });
  return { family, adminUser, admin, kidUser, kid, managed };
}

const bearer = (user) => ({ Authorization: `Bearer ${tokens.signAccessToken(user)}` });

/** Replaces the loaded translation catalogs with `files` ({ 'hi/common.json': {...} | 'raw text' }) during `fn`. */
async function withCatalogs(files, fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'familyhub-i18n-'));
  try {
    for (const [rel, content] of Object.entries(files)) {
      const file = path.join(dir, rel);
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, typeof content === 'string' ? content : JSON.stringify(content));
    }
    i18n.loadTranslations(dir);
    return await fn();
  } finally {
    i18n.loadTranslations();
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

const EN_COMMON = JSON.parse(fs.readFileSync(new URL('../src/i18n/locales/en/common.json', import.meta.url), 'utf8'));

// ---------------------------------------------------------------- requireAuth

describe('middleware/auth.js', () => {
  const authReq = miniApp((app) => {
    app.get('/me', requireAuth, (req, res) => res.json({ user: req.user, member: req.member ? String(req.member._id) : null }));
    app.get('/family', requireAuth, requireFamily, (_req, res) => res.json({ ok: true }));
    app.get('/admin', requireAuth, requireAdmin, (_req, res) => res.json({ ok: true }));
    app.get('/chain/member', ...familyMember, (_req, res) => res.json({ ok: true }));
    app.get('/chain/admin', ...familyAdmin, (_req, res) => res.json({ ok: true }));
  });

  const sign = (sub, opts = {}, secret = env.JWT_ACCESS_SECRET) =>
    jwt.sign({}, secret, { subject: String(sub), issuer: constants.JWT_ISSUER, audience: constants.JWT_AUDIENCE, expiresIn: 60, ...opts });

  it('missing token → 401 UNAUTHORIZED', async () => {
    assertErrorEnvelope(await authReq.get('/me'), 401, 'UNAUTHORIZED');
  });

  it('malformed Authorization headers → 401 UNAUTHORIZED', async () => {
    for (const header of ['Bearer', 'Token abc', 'Bearer a b', 'Basic dXNlcjpwYXNz', 'Bearer not-a-jwt']) {
      assertErrorEnvelope(await authReq.get('/me').set('Authorization', header), 401, 'UNAUTHORIZED');
    }
  });

  it('expired token → 401 TOKEN_EXPIRED', async () => {
    const user = await User.create({ email: unique('expired'), passwordHash: 'x', name: 'Expired' });
    const expired = jwt.sign({ exp: Math.floor(Date.now() / 1000) - 10 }, env.JWT_ACCESS_SECRET, {
      subject: String(user._id),
      issuer: constants.JWT_ISSUER,
      audience: constants.JWT_AUDIENCE,
    });
    const res = await authReq.get('/me').set('Authorization', `Bearer ${expired}`);
    assertErrorEnvelope(res, 401, 'TOKEN_EXPIRED');
  });

  it('forged, foreign, alg=none and non-ObjectId tokens → 401 UNAUTHORIZED', async () => {
    const user = await User.create({ email: unique('forged'), passwordHash: 'x', name: 'Forged' });
    const cases = {
      forged: sign(user._id, {}, 'another-secret-that-is-long-enough-000000'),
      otherAudience: sign(user._id, { audience: 'someone-else' }),
      otherIssuer: sign(user._id, { issuer: 'someone-else' }),
      algNone: `${Buffer.from('{"alg":"none","typ":"JWT"}').toString('base64url')}.${Buffer.from(JSON.stringify({ sub: String(user._id) })).toString('base64url')}.`,
      badSub: sign('not-an-object-id'),
      deletedUser: sign(oid()),
    };
    for (const [name, token] of Object.entries(cases)) {
      const res = await authReq.get('/me').set('Authorization', `Bearer ${token}`);
      assert.equal(res.status, 401, name);
      assert.equal(res.body.error.code, 'UNAUTHORIZED', name);
    }
  });

  it('sets req.user with the exact contract shape (no family)', async () => {
    const user = await User.create({ email: unique('nofam'), passwordHash: 'x', name: 'No Fam', locale: 'fr' });
    const res = await authReq.get('/me').set(bearer(user));
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, {
      user: { id: String(user._id), email: user.email, name: 'No Fam', locale: 'fr', emailVerified: false, familyId: null, memberId: null, role: null },
      member: null,
    });
  });

  it('answers in the user locale without Accept-Language; the header wins when present', async () => {
    const user = await User.create({ email: unique('loc'), passwordHash: 'x', name: 'Loc', locale: 'fr' });
    const noHeader = await authReq.get('/family').set(bearer(user));
    assertErrorEnvelope(noHeader, 403, 'NO_FAMILY');
    assert.equal(noHeader.headers['content-language'], 'fr');
    const withHeader = await authReq.get('/family').set(bearer(user)).set('Accept-Language', 'es');
    assert.equal(withHeader.headers['content-language'], 'es');
  });

  it('requireFamily / requireAdmin and the familyMember / familyAdmin chains', async () => {
    const { adminUser, kidUser, kid, family } = await seedFamily('roles');
    const me = await authReq.get('/me').set(bearer(kidUser));
    assert.equal(me.body.user.familyId, String(family._id));
    assert.equal(me.body.user.memberId, String(kid._id));
    assert.equal(me.body.user.role, 'member');
    assert.equal(me.body.member, String(kid._id));

    assert.equal((await authReq.get('/family').set(bearer(kidUser))).status, 200);
    assert.equal((await authReq.get('/chain/member').set(bearer(kidUser))).status, 200);
    assertErrorEnvelope(await authReq.get('/admin').set(bearer(kidUser)), 403, 'FORBIDDEN');
    assertErrorEnvelope(await authReq.get('/chain/admin').set(bearer(kidUser)), 403, 'FORBIDDEN');
    assert.equal((await authReq.get('/admin').set(bearer(adminUser))).status, 200);
    assert.equal((await authReq.get('/chain/admin').set(bearer(adminUser))).status, 200);

    const loner = await User.create({ email: unique('loner'), passwordHash: 'x', name: 'Loner' });
    assertErrorEnvelope(await authReq.get('/chain/admin').set(bearer(loner)), 403, 'NO_FAMILY');

    // Member row deleted (removed from the family) → treated as "no family".
    await Member.deleteOne({ _id: kid._id });
    assertErrorEnvelope(await authReq.get('/family').set(bearer(kidUser)), 403, 'NO_FAMILY');
    assert.equal((await authReq.get('/me').set(bearer(kidUser))).body.user.role, null);
  });
});

// ---------------------------------------------------------------- error middleware

describe('middleware/error.js', () => {
  it('malformed JSON → 400 BAD_REQUEST envelope (real app)', async () => {
    const res = await request.post(`${API}/health`).set('Content-Type', 'application/json').send('{"broken":');
    assertErrorEnvelope(res, 400, 'BAD_REQUEST');
    assert.deepEqual(Object.keys(res.body).sort(), ['error', 'success']);
    assert.deepEqual(Object.keys(res.body.error).sort(), ['code', 'message']);
  });

  it('Accept-Language: hi falls back to English when there is no Hindi file', async () => {
    await withCatalogs({ 'en/common.json': EN_COMMON }, async () => {
      const res = await request
        .post(`${API}/health`)
        .set('Content-Type', 'application/json')
        .set('Accept-Language', 'hi-IN,hi;q=0.9')
        .send('{"broken":');
      assertErrorEnvelope(res, 400, 'BAD_REQUEST');
      assert.equal(res.headers['content-language'], 'hi');
      assert.equal(res.body.error.message, EN_COMMON.errors.BAD_REQUEST);
    });
  });

  it('uses the Hindi text when it exists, English for keys the Hindi file lacks', async () => {
    const HI_BAD_REQUEST = 'अनुरोध समझ में नहीं आया।';
    await withCatalogs({ 'en/common.json': EN_COMMON, 'hi/common.json': { errors: { BAD_REQUEST: HI_BAD_REQUEST } } }, async () => {
      const bad = await request.post(`${API}/health`).set('Content-Type', 'application/json').set('Accept-Language', 'hi').send('{');
      assert.equal(bad.body.error.message, HI_BAD_REQUEST);
      const missing = await request.get(`${API}/nope`).set('Accept-Language', 'hi');
      assertErrorEnvelope(missing, 404, 'NOT_FOUND');
      assert.equal(missing.body.error.message, EN_COMMON.errors.NOT_FOUND);
    });
  });

  const local = miniApp((app) => {
    app.get('/api-error', () => {
      throw ApiError.tooManyRequests(42);
    });
    app.get('/message-key', () => {
      throw ApiError.forbidden('English fallback', { messageKey: 'common.errors.LAST_ADMIN' });
    });
    app.get('/missing-key', () => {
      throw new ApiError(409, 'SOS_NOT_ACTIVE', 'fallback', { messageKey: 'sos.errors.doesNotExist' });
    });
    app.get('/zod', () => {
      z.object({ name: z.string() }).parse({});
    });
    app.get('/cast', async () => {
      await Member.findById('not-an-id');
    });
    app.get('/mongoose-validation', async () => {
      await Family.create({ name: 'x', country: 'IN', currency: 'INR', timezone: 'Mars/Olympus', ownerId: oid() });
    });
    app.get('/boom', async () => {
      throw new Error('secret internals');
    });
    app.get('/items/:id', v.validate({ params: v.idParams }), v.validate({ query: v.paginationQuery }), (req, res) => res.json(req.valid));
    app.post('/items', v.validate({ body: z.object({ title: z.string().min(1) }) }), (req, res) => res.json(req.valid.body));
  });

  it('ApiError keeps status, code, details, Retry-After and localized vars', async () => {
    const res = await local.get('/api-error');
    assertErrorEnvelope(res, 429, 'TOO_MANY_REQUESTS');
    assert.equal(res.body.error.details.retryAfterSeconds, 42);
    assert.equal(res.headers['retry-after'], '42');
    assert.match(res.body.error.message, /42/);
    assert.ok(!res.body.error.message.includes('{seconds}'));
  });

  it('messageKey is used when translated, otherwise common.errors.<CODE>', async () => {
    const withKey = await local.get('/message-key');
    assertErrorEnvelope(withKey, 403, 'FORBIDDEN');
    assert.equal(withKey.body.error.message, i18n.t('en', 'common.errors.LAST_ADMIN'));
    const missing = await local.get('/missing-key');
    assertErrorEnvelope(missing, 409, 'SOS_NOT_ACTIVE');
    assert.equal(missing.body.error.message, i18n.t('en', 'common.errors.SOS_NOT_ACTIVE'));
  });

  it('ZodError / mongoose ValidationError → 422 VALIDATION_ERROR with field details', async () => {
    const zodRes = await local.get('/zod');
    assertErrorEnvelope(zodRes, 422, 'VALIDATION_ERROR');
    assert.ok(zodRes.body.error.details.name);
    const mongooseRes = await local.get('/mongoose-validation');
    assertErrorEnvelope(mongooseRes, 422, 'VALIDATION_ERROR');
    assert.ok(mongooseRes.body.error.details.timezone);
  });

  it('CastError → 400 BAD_REQUEST', async () => {
    assertErrorEnvelope(await local.get('/cast'), 400, 'BAD_REQUEST');
  });

  it('unexpected error → 500 INTERNAL_ERROR without internals', async () => {
    const res = await local.get('/boom');
    assertErrorEnvelope(res, 500, 'INTERNAL_ERROR');
    assert.ok(!JSON.stringify(res.body).includes('secret internals'));
  });

  it('validate(): params → 400 BAD_REQUEST, query/body → 422, several validate() merge into req.valid', async () => {
    assertErrorEnvelope(await local.get('/items/not-an-id'), 400, 'BAD_REQUEST');
    assertErrorEnvelope(await local.get('/items/64b7f0c2a1b2c3d4e5f60718?limit=500'), 422, 'VALIDATION_ERROR');
    const good = await local.get('/items/64B7F0C2A1B2C3D4E5F60718?page=2');
    assert.equal(good.status, 200);
    assert.deepEqual(good.body, { params: { id: '64b7f0c2a1b2c3d4e5f60718' }, query: { page: 2, limit: 20 } });
    const bad = await local.post('/items').send({ title: '' });
    assertErrorEnvelope(bad, 422, 'VALIDATION_ERROR');
    assert.ok(bad.body.error.details.title);
  });
});

// ---------------------------------------------------------------- models ↔ error codes (b-models + b-core)

describe('unique indexes map to contract error codes', () => {
  const run = miniApp((app) => {
    app.post('/run', async (req, res) => {
      await actions[req.body.action]();
      res.json({ ok: true });
    });
  });
  let actions = {};
  const attempt = async (action) => run.post('/run').send({ action });

  it('duplicate user e-mail (any case) → 409 EMAIL_TAKEN without leaking the value', async () => {
    actions = {
      first: () => User.create({ email: 'Dup.User@Example.com', passwordHash: 'x', name: 'A' }),
      second: () => User.create({ email: 'dup.user@example.com', passwordHash: 'x', name: 'B' }),
    };
    assert.equal((await attempt('first')).status, 200);
    const res = await attempt('second');
    assertErrorEnvelope(res, 409, 'EMAIL_TAKEN');
    assert.ok(!JSON.stringify(res.body).includes('dup.user'), 'duplicate value must not leak');
    assert.deepEqual(res.body.error.details, { email: 'Already exists' });
  });

  it('member e-mail unique per family → 409 MEMBER_EMAIL_EXISTS; other families and empty e-mails are fine', async () => {
    const familyA = oid();
    const familyB = oid();
    actions = {
      a1: () => Member.create({ familyId: familyA, name: 'A', email: 'kid@example.com' }),
      a2: () => Member.create({ familyId: familyA, name: 'B', email: 'KID@example.com' }),
      b1: () => Member.create({ familyId: familyB, name: 'C', email: 'kid@example.com' }),
      noEmail: () => Member.create([{ familyId: familyA, name: 'D', email: '' }, { familyId: familyA, name: 'E', email: null }, { familyId: familyA, name: 'F' }]),
    };
    assert.equal((await attempt('a1')).status, 200);
    assertErrorEnvelope(await attempt('a2'), 409, 'MEMBER_EMAIL_EXISTS');
    assert.equal((await attempt('b1')).status, 200);
    assert.equal((await attempt('noEmail')).status, 200);
    assert.equal(await Member.countDocuments({ familyId: familyA, email: null }), 3);
  });

  it('one member per user account → 409 ALREADY_IN_FAMILY', async () => {
    const userId = oid();
    actions = {
      first: () => Member.create({ familyId: oid(), userId, name: 'A' }),
      second: () => Member.create({ familyId: oid(), userId, name: 'B' }),
    };
    assert.equal((await attempt('first')).status, 200);
    assertErrorEnvelope(await attempt('second'), 409, 'ALREADY_IN_FAMILY');
  });

  it('other unique keys → generic 409 CONFLICT (services retry / upsert instead)', async () => {
    const ownerId = oid();
    const memberId = oid();
    const family = { name: 'F', country: 'IN', currency: 'INR', timezone: 'Asia/Kolkata', ownerId };
    actions = {
      code1: () => Family.create({ ...family, inviteCode: 'demo2345' }),
      code2: () => Family.create({ ...family, inviteCode: 'DEMO2345' }),
      device1: () => Device.create({ userId: oid(), token: 'same-token', platform: 'android' }),
      device2: () => Device.create({ userId: oid(), token: 'same-token', platform: 'ios' }),
      otp1: () => Otp.create({ email: 'o@example.com', purpose: 'verify_email', codeHash: 'h', expiresAt: new Date(Date.now() + 60_000) }),
      otp2: () => Otp.create({ email: 'O@example.com', purpose: 'verify_email', codeHash: 'h2', expiresAt: new Date(Date.now() + 60_000) }),
      card1: () => EmergencyCard.create({ familyId: oid(), memberId }),
      card2: () => EmergencyCard.create({ familyId: oid(), memberId }),
    };
    for (const [first, second] of [['code1', 'code2'], ['device1', 'device2'], ['otp1', 'otp2'], ['card1', 'card2']]) {
      assert.equal((await attempt(first)).status, 200, first);
      assertErrorEnvelope(await attempt(second), 409, 'CONFLICT');
    }
  });
});

// ---------------------------------------------------------------- crypto

describe('lib/crypto.js', () => {
  it('encryptField / decryptField round-trip every JSON value, Unicode included', () => {
    const values = [
      ['Peanuts', 'पेनिसिलिन', 'حساسية', '🥜'],
      [],
      'P-123/ß',
      'मधुमेह — टाइप 2',
      42,
      0,
      false,
      { nested: { list: [1, 'two'] } },
      '',
    ];
    for (const value of values) {
      const enc = cryptoLib.encryptField(value);
      assert.equal(typeof enc, 'string');
      assert.match(enc, /^enc:v1:[\w-]+\.[\w-]+\.[\w-]+$/);
      assert.deepEqual(cryptoLib.decryptField(enc), value);
    }
  });

  it('uses a random IV (same input → different ciphertext) and never embeds the plaintext', () => {
    const a = cryptoLib.encryptField(['Asthma']);
    const b = cryptoLib.encryptField(['Asthma']);
    assert.notEqual(a, b);
    assert.ok(!a.includes('Asthma'));
    assert.ok(!Buffer.from(a.split('.').at(-1), 'base64url').toString('utf8').includes('Asthma'));
  });

  it('passes null / undefined / plaintext through unchanged', () => {
    assert.equal(cryptoLib.encryptField(null), null);
    assert.equal(cryptoLib.encryptField(undefined), undefined);
    assert.equal(cryptoLib.decryptField(null), null);
    assert.equal(cryptoLib.decryptField('legacy plaintext'), 'legacy plaintext');
    assert.equal(cryptoLib.decryptField(7), 7);
  });

  it('throws on tampered or malformed ciphertext (never returns wrong data)', () => {
    const enc = cryptoLib.encryptField(['Peanuts']);
    const [iv, tag, data] = enc.slice('enc:v1:'.length).split('.');
    const flipped = Buffer.from(data, 'base64url');
    flipped[0] ^= 0xff;
    assert.throws(() => cryptoLib.decryptField(`enc:v1:${iv}.${tag}.${flipped.toString('base64url')}`));
    assert.throws(() => cryptoLib.decryptField(`enc:v1:${iv}.${Buffer.alloc(16).toString('base64url')}.${data}`));
    assert.throws(() => cryptoLib.decryptField('enc:v1:only-one-part'), /malformed/);
    assert.throws(() => cryptoLib.decryptField(`enc:v1:${iv}..${data}`), /malformed/);
  });

  it('hashing, random codes and invite codes', () => {
    assert.equal(cryptoLib.sha256('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    assert.match(cryptoLib.randomDigits(6), /^\d{6}$/);
    assert.equal(cryptoLib.randomToken(48).length, 64);
    for (let i = 0; i < 200; i++) assert.match(cryptoLib.randomInviteCode(), enums.INVITE_CODE_REGEX);
    assert.equal(cryptoLib.safeEqual('abc', 'abc'), true);
    assert.equal(cryptoLib.safeEqual('abc', 'abd'), false);
    assert.equal(cryptoLib.safeEqual('abc', 'abcd'), false);
  });
});

// ---------------------------------------------------------------- money

describe('lib/money.js', () => {
  it('0.1 + 0.2 is stored as exactly 30 minor units and shown as 0.3', () => {
    assert.notEqual(0.1 + 0.2, 0.3); // the float problem we avoid
    assert.equal(money.toMinor(0.1 + 0.2), 30);
    assert.equal(money.toMinor(0.1) + money.toMinor(0.2), 30);
    assert.equal(money.fromMinor(money.toMinor(0.1) + money.toMinor(0.2)), 0.3);
    assert.equal(money.roundMoney(0.1 + 0.2), 0.3);
    assert.equal(money.fromMinor(money.sumMinor([money.toMinor(0.1), money.toMinor(0.2), null, undefined])), 0.3);
    // 0.1 added ten times as floats is 0.9999999999999999; as minor units it is exactly 1.
    let float = 0;
    let minor = 0;
    for (let i = 0; i < 10; i++) {
      float += 0.1;
      minor += money.toMinor(0.1);
    }
    assert.notEqual(float, 1);
    assert.equal(money.fromMinor(minor), 1);
  });

  it('toMinor rounds half away from zero on the decimal value', () => {
    assert.equal(money.toMinor(1250.5), 125050);
    assert.equal(money.toMinor(1.005), 101);
    assert.equal(money.toMinor(1.255), 126);
    assert.equal(money.toMinor(-1.005), -101);
    assert.equal(money.toMinor(0.004), 0);
    assert.equal(money.toMinor('12.30'), 1230);
    assert.equal(money.toMinor(1e12), 1e14);
    assert.ok(Object.is(money.toMinor(-0), 0));
    assert.equal(money.toMinor(1e-7), 0);
  });

  it('rejects non-numbers and out-of-range values', () => {
    for (const bad of [Number.NaN, Infinity, -Infinity, 'abc', null, undefined, {}]) {
      assert.throws(() => money.toMinor(bad), TypeError, String(bad));
    }
    assert.throws(() => money.toMinor(1e300), RangeError);
  });

  it('fromMinor returns major units with at most 2 decimals', () => {
    assert.equal(money.fromMinor(125050), 1250.5);
    assert.equal(money.fromMinor(1), 0.01);
    assert.equal(money.fromMinor(-150), -1.5);
    assert.equal(money.fromMinor(null), 0);
    assert.equal(money.fromMinor(undefined), 0);
    assert.equal(money.fromMinor('abc'), 0);
    assert.ok(Object.is(money.fromMinor(-0), 0));
  });

  it('isValidAmount / moneyAmount follow the contract (> 0, ≤ 1e12, ≥ 0.01)', () => {
    assert.equal(money.MAX_AMOUNT, 1e12);
    assert.equal(money.MAX_AMOUNT * money.MINOR_PER_MAJOR, enums.MAX_AMOUNT_MINOR);
    for (const good of [0.01, 1, 1250.5, 1e12]) {
      assert.equal(money.isValidAmount(good), true, String(good));
      assert.equal(v.moneyAmount.safeParse(good).success, true, String(good));
    }
    for (const bad of [0, -1, 0.001, 1e12 + 1, '5', Number.NaN, Infinity, null]) {
      assert.equal(money.isValidAmount(bad), false, String(bad));
      assert.equal(v.moneyAmount.safeParse(bad).success, false, String(bad));
    }
  });
});

// ---------------------------------------------------------------- dates

describe('lib/dates.js', () => {
  const range = (month, tz) => {
    const { start, end } = dates.monthRange(month, tz);
    return [start.toISOString(), end.toISOString()];
  };

  it('monthRange: Asia/Kolkata (UTC+05:30, no DST) incl. year rollover', () => {
    assert.deepEqual(range('2026-09', 'Asia/Kolkata'), ['2026-08-31T18:30:00.000Z', '2026-09-30T18:30:00.000Z']);
    assert.deepEqual(range('2026-12', 'Asia/Kolkata'), ['2026-11-30T18:30:00.000Z', '2026-12-31T18:30:00.000Z']);
    assert.deepEqual(range('2027-01', 'Asia/Kolkata'), ['2026-12-31T18:30:00.000Z', '2027-01-31T18:30:00.000Z']);
  });

  it('monthRange: America/Los_Angeles in normal and DST-change months', () => {
    assert.deepEqual(range('2026-07', 'America/Los_Angeles'), ['2026-07-01T07:00:00.000Z', '2026-08-01T07:00:00.000Z']);
    // DST starts 8 Mar 2026 (PST −8 → PDT −7): the month is one hour shorter.
    assert.deepEqual(range('2026-03', 'America/Los_Angeles'), ['2026-03-01T08:00:00.000Z', '2026-04-01T07:00:00.000Z']);
    // DST ends 1 Nov 2026 at 02:00 (midnight is still PDT): the month is one hour longer.
    assert.deepEqual(range('2026-11', 'America/Los_Angeles'), ['2026-11-01T07:00:00.000Z', '2026-12-01T08:00:00.000Z']);
    const march = dates.monthRange('2026-03', 'America/Los_Angeles');
    assert.equal(march.end - march.start, (31 * 24 - 1) * 3600 * 1000);
  });

  it('monthRange: other offsets and hemispheres (Kathmandu +05:45, Sydney, London, UTC leap year)', () => {
    assert.deepEqual(range('2026-01', 'Asia/Kathmandu'), ['2025-12-31T18:15:00.000Z', '2026-01-31T18:15:00.000Z']);
    // Sydney leaves DST on 5 Apr 2026 (AEDT +11 → AEST +10).
    assert.deepEqual(range('2026-04', 'Australia/Sydney'), ['2026-03-31T13:00:00.000Z', '2026-04-30T14:00:00.000Z']);
    // London enters BST on 29 Mar 2026.
    assert.deepEqual(range('2026-03', 'Europe/London'), ['2026-03-01T00:00:00.000Z', '2026-03-31T23:00:00.000Z']);
    assert.deepEqual(range('2028-02', 'UTC'), ['2028-02-01T00:00:00.000Z', '2028-03-01T00:00:00.000Z']);
  });

  it('monthRange: consecutive months tile without gaps, each starts at local midnight on the 1st', () => {
    const zones = ['Asia/Kolkata', 'America/Los_Angeles', 'America/Sao_Paulo', 'Europe/Berlin', 'Australia/Sydney', 'Pacific/Auckland', 'Asia/Dubai', 'UTC'];
    for (const tz of zones) {
      for (let m = 1; m <= 12; m++) {
        const month = `2026-${String(m).padStart(2, '0')}`;
        const next = m === 12 ? '2027-01' : `2026-${String(m + 1).padStart(2, '0')}`;
        const cur = dates.monthRange(month, tz);
        assert.equal(cur.end.getTime(), dates.monthRange(next, tz).start.getTime(), `${tz} ${month}`);
        const p = dates.zonedParts(cur.start, tz);
        assert.deepEqual([p.year, p.month, p.day, p.hour, p.minute], [2026, m, 1, 0, 0], `${tz} ${month}`);
      }
    }
  });

  it('monthRange: rejects malformed months; unknown zones fall back to UTC', () => {
    for (const bad of ['2026-13', '2026-9', '2026/09', '', null, undefined]) {
      assert.throws(() => dates.monthRange(bad, 'UTC'), RangeError, String(bad));
    }
    assert.deepEqual(range('2026-09', 'Mars/Olympus'), ['2026-09-01T00:00:00.000Z', '2026-10-01T00:00:00.000Z']);
  });

  it('currentMonth depends on the family time zone', () => {
    const instant = new Date('2026-09-30T19:00:00.000Z');
    assert.equal(dates.currentMonth('Asia/Kolkata', instant), '2026-10');
    assert.equal(dates.currentMonth('America/Los_Angeles', instant), '2026-09');
    assert.equal(dates.currentMonth('UTC', instant), '2026-09');
    for (const tz of ['Asia/Kolkata', 'America/Los_Angeles', 'Pacific/Kiritimati', 'Pacific/Pago_Pago']) {
      const { start, end } = dates.monthRange(dates.currentMonth(tz, instant), tz);
      assert.ok(start <= instant && instant < end, tz);
    }
  });

  it('startOfDay / startOfWeek / weekRange / ageFrom', () => {
    const now = new Date('2026-09-26T20:00:00.000Z'); // Sunday 27 Sep 01:30 in IST
    assert.equal(dates.startOfDay(now, 'Asia/Kolkata').toISOString(), '2026-09-26T18:30:00.000Z');
    assert.equal(dates.startOfWeek(now, 'Asia/Kolkata').toISOString(), '2026-09-20T18:30:00.000Z');
    assert.equal(dates.startOfWeek(now, 'UTC').toISOString(), '2026-09-21T00:00:00.000Z');
    const week = dates.weekRange(now, 'America/Los_Angeles');
    assert.equal(week.start.toISOString(), '2026-09-21T07:00:00.000Z');
    assert.equal(week.end.toISOString(), '2026-09-28T07:00:00.000Z');
    assert.equal(dates.ageFrom(new Date('2010-05-14T00:00:00.000Z'), new Date('2026-05-13T12:00:00.000Z')), 15);
    assert.equal(dates.ageFrom(new Date('2010-05-14T00:00:00.000Z'), new Date('2026-05-14T00:00:00.000Z')), 16);
    // Local midnight in IST stored as UTC is still the right birthday in the family zone.
    assert.equal(dates.ageFrom('2010-05-13T18:30:00.000Z', new Date('2026-05-13T20:00:00.000Z'), 'Asia/Kolkata'), 16);
    assert.equal(dates.ageFrom(null), null);
    assert.equal(dates.ageFrom('not a date'), null);
  });
});

// ---------------------------------------------------------------- i18n

describe('lib/i18n.js', () => {
  const fixture = {
    'en/common.json': { errors: { TOO_MANY_REQUESTS: 'Try again in {seconds} seconds.' }, email: { footer: '{appName} · {appName}' } },
    'en/tasks.json': { push: { assigned: { title: 'New task: {title}', body: '{name} assigned "{title}" to you' } } },
    'hi/tasks.json': { push: { assigned: { title: 'नया कार्य: {title}' } } },
    'de/common.json': '{ this is not json',
  };

  it('t() fills {placeholders}, including repeated ones and numbers', () =>
    withCatalogs(fixture, () => {
      assert.equal(i18n.t('en', 'common.errors.TOO_MANY_REQUESTS', { seconds: 42 }), 'Try again in 42 seconds.');
      assert.equal(i18n.t('en', 'common.errors.TOO_MANY_REQUESTS', { seconds: 0 }), 'Try again in 0 seconds.');
      assert.equal(i18n.t('en', 'common.email.footer', { appName: 'FamilyHub' }), 'FamilyHub · FamilyHub');
      assert.equal(i18n.t('en', 'tasks.push.assigned.body', { name: 'Amit', title: 'Homework' }), 'Amit assigned "Homework" to you');
    }));

  it('t() leaves unknown / null placeholders untouched and ignores extra vars', () =>
    withCatalogs(fixture, () => {
      assert.equal(i18n.t('en', 'common.errors.TOO_MANY_REQUESTS'), 'Try again in {seconds} seconds.');
      assert.equal(i18n.t('en', 'common.errors.TOO_MANY_REQUESTS', { seconds: null }), 'Try again in {seconds} seconds.');
      assert.equal(i18n.t('en', 'common.errors.TOO_MANY_REQUESTS', { other: 1, seconds: 5 }), 'Try again in 5 seconds.');
    }));

  it('t() falls back locale → English → key; locales are normalized', () =>
    withCatalogs(fixture, () => {
      assert.equal(i18n.t('hi', 'tasks.push.assigned.title', { title: 'गृहकार्य' }), 'नया कार्य: गृहकार्य');
      assert.equal(i18n.t('hi-IN', 'tasks.push.assigned.title', { title: 'X' }), 'नया कार्य: X');
      assert.equal(i18n.t('HI', 'tasks.push.assigned.body', { name: 'A', title: 'B' }), 'A assigned "B" to you');
      assert.equal(i18n.t('xx', 'tasks.push.assigned.title', { title: 'X' }), 'New task: X');
      assert.equal(i18n.t(undefined, 'tasks.push.assigned.title', { title: 'X' }), 'New task: X');
      assert.equal(i18n.t('hi', 'nope.missing.key', { a: 1 }), 'nope.missing.key');
      assert.equal(i18n.tOr('hi', 'nope.missing.key', 'Fallback {a}', { a: 1 }), 'Fallback 1');
      assert.equal(i18n.hasTranslation('tasks.push.assigned.body', 'hi'), true);
      assert.equal(i18n.hasTranslation('nope.missing.key', 'hi'), false);
    }));

  it('a broken translation file is skipped (English fallback) and reported', () =>
    withCatalogs(fixture, () => {
      assert.ok(i18n.loadErrors.some((e) => e.file.endsWith(path.join('de', 'common.json'))));
      assert.equal(i18n.t('de', 'common.errors.TOO_MANY_REQUESTS', { seconds: 3 }), 'Try again in 3 seconds.');
    }));

  it('pickLocale honours q-values and falls back to en', () => {
    assert.equal(i18n.pickLocale('ta-IN'), 'ta');
    assert.equal(i18n.pickLocale('de;q=0.5, ar;q=0.9'), 'ar');
    assert.equal(i18n.pickLocale('xx, fr;q=0.1'), 'fr');
    assert.equal(i18n.pickLocale('hi;q=0'), 'en');
    assert.equal(i18n.pickLocale(undefined), 'en');
    assert.equal(i18n.pickLocale('*'), 'en');
    assert.equal(i18n.pickLocale(['pt-BR', 'en']), 'pt');
  });

  it('the real English catalog covers every error code and the e-mail layout', () => {
    for (const code of Object.keys(ErrorCodes)) assert.ok(i18n.hasTranslation(`common.errors.${code}`, 'en'), code);
    for (const key of ['greeting', 'footer', 'signature']) assert.ok(i18n.hasTranslation(`common.email.${key}`, 'en'), key);
    const text = i18n.t('en', 'common.errors.TOO_MANY_REQUESTS', { seconds: 7 });
    assert.match(text, /7/);
    assert.ok(!text.includes('{seconds}'));
  });
});

// ---------------------------------------------------------------- validate.js building blocks

describe('lib/validate.js building blocks', () => {
  const patch = z.object({
    description: v.optionalText(10),
    dueDate: v.nullableIsoDate,
    assigneeId: v.nullableObjectId,
    email: v.nullableEmail,
    phone: v.nullablePhone,
    avatarUrl: v.nullableCloudinaryUrl,
    gender: v.nullableGender,
  });

  it('nullable blocks: absent stays absent, null / blank → null (PATCH-safe)', () => {
    assert.deepEqual(patch.parse({}), {});
    const cleared = patch.parse({ description: '   ', dueDate: null, assigneeId: null, email: '', phone: null, avatarUrl: '', gender: '' });
    assert.deepEqual(cleared, { description: null, dueDate: null, assigneeId: null, email: null, phone: null, avatarUrl: null, gender: null });
    const set = patch.parse({
      description: ' Ch. 4 ',
      dueDate: '2026-09-26T18:30:00.000Z',
      assigneeId: '64B7F0C2A1B2C3D4E5F60718',
      email: ' Kid@Example.COM ',
      phone: '+91 98765-43210',
      avatarUrl: 'https://res.cloudinary.com/demo/image/upload/a.jpg',
      gender: 'female',
    });
    assert.equal(set.description, 'Ch. 4');
    assert.equal(set.dueDate.toISOString(), '2026-09-26T18:30:00.000Z');
    assert.equal(set.assigneeId, '64b7f0c2a1b2c3d4e5f60718');
    assert.equal(set.email, 'kid@example.com');
    assert.equal(set.phone, '+919876543210');
    assert.equal(set.gender, 'female');
    const bad = patch.safeParse({ description: 'x'.repeat(11), dueDate: 'soon', assigneeId: 'nope', email: 'x', phone: '12', avatarUrl: 'https://evil.example.com/a.jpg', gender: 'x' });
    assert.deepEqual(Object.keys(v.zodIssuesToDetails(bad.error.issues)).sort(), ['assigneeId', 'avatarUrl', 'description', 'dueDate', 'email', 'gender', 'phone']);
  });

  it('isoDate: calendar-checked ISO dates / date-times with an explicit offset only', () => {
    for (const good of ['2026-09-26', '2024-02-29', '2026-09-26T10:15:00.000Z', '2026-09-26T10:15:00.123456Z', '2026-09-26T10:15:00+05:30']) {
      assert.equal(v.isoDate.safeParse(good).success, true, good);
    }
    for (const bad of ['2026-02-31', '2026-02-29', '2026-13-01', '2026-09-26 10:00', '2026-09-26T10:15:00', '26/09/2026', 'yesterday', '', 1790417700000]) {
      assert.equal(v.isoDate.safeParse(bad).success, false, String(bad));
    }
    assert.equal(v.isoDate.parse('2026-09-26T10:15:00+05:30').toISOString(), '2026-09-26T04:45:00.000Z');
  });

  it('inviteCode: case-insensitive, ignores spaces/dashes, accepts the demo code', () => {
    assert.equal(v.inviteCode.parse('k7q2m9xd'), 'K7Q2M9XD');
    assert.equal(v.inviteCode.parse(' demo-2345 '), 'DEMO2345');
    assert.equal(v.inviteCode.parse('DEMO 2345'), 'DEMO2345');
    for (const bad of ['DEMO234', 'DEMO23456', 'DEMO_234', 'ÄBCDEFGH', '', 12345678]) {
      assert.equal(v.inviteCode.safeParse(bad).success, false, String(bad));
    }
  });

  it('latLng: numbers only, bounded, accuracy optional', () => {
    assert.deepEqual(v.latLng.parse({ lat: 28.61, lng: 77.2 }), { lat: 28.61, lng: 77.2 });
    assert.deepEqual(v.latLng.parse({ lat: -90, lng: 180, accuracy: null }), { lat: -90, lng: 180, accuracy: null });
    for (const bad of [{ lat: null, lng: 0 }, { lat: '28.6', lng: 77 }, { lat: 91, lng: 0 }, { lat: 0, lng: -181 }, { lat: 0, lng: 0, accuracy: -1 }, { lat: true, lng: 0 }]) {
      assert.equal(v.latLng.safeParse(bad).success, false, JSON.stringify(bad));
    }
  });

  it('locale / country / currency / time zone / pagination / password', () => {
    assert.equal(v.locale.safeParse('hi').success, true);
    assert.equal(v.locale.safeParse('hi-IN').success, false);
    assert.equal(v.countryCode.parse(' in '), 'IN');
    assert.equal(v.countryCode.safeParse('ZZ').success, false);
    assert.equal(v.currencyCode.parse('eur'), 'EUR');
    assert.equal(v.currencyCode.safeParse('XXX').success, false);
    assert.equal(v.timeZone.safeParse('Asia/Kolkata').success, true);
    assert.equal(v.timeZone.safeParse('Mars/Olympus').success, false);
    assert.deepEqual(v.paginationQuery.parse({}), { page: 1, limit: 20 });
    assert.deepEqual(v.paginationQuery.parse({ page: '3', limit: '100' }), { page: 3, limit: 100 });
    for (const bad of [{ page: '0' }, { limit: '101' }, { limit: '0' }, { page: '1.5' }]) assert.equal(v.paginationQuery.safeParse(bad).success, false);
    assert.equal(v.password.safeParse('secret123').success, true);
    assert.equal(v.password.safeParse('पासवर्ड1234').success, true, 'letters of any script');
    for (const bad of ['short1', 'allletters', '12345678']) assert.equal(v.password.safeParse(bad).success, false, bad);
    assert.equal(v.personName.safeParse('  ').success, false);
    assert.equal(v.personName.safeParse('x'.repeat(61)).success, false);
  });
});

// ---------------------------------------------------------------- tokens

describe('services/tokens.js', () => {
  it('issues, rotates and detects reuse of refresh tokens', async () => {
    const user = await User.create({ email: unique('rot'), passwordHash: 'x', name: 'Rot' });
    const first = await tokens.issueTokens(user, { ip: '127.0.0.1', userAgent: 'test' });
    assert.equal(first.expiresIn, env.ACCESS_TOKEN_TTL_SECONDS);
    assert.equal(tokens.verifyAccessToken(first.accessToken).sub, String(user._id));
    assert.equal(Buffer.from(first.refreshToken, 'base64url').length, constants.REFRESH_TOKEN_BYTES);
    const stored = await RefreshToken.findOne({ userId: user._id }).lean();
    assert.equal(stored.tokenHash, cryptoLib.sha256(first.refreshToken), 'refresh token stored as sha256 only');
    assert.equal(JSON.stringify(stored).includes(first.refreshToken), false);

    const second = await tokens.rotateRefreshToken(first.refreshToken, {});
    assert.notEqual(second.refreshToken, first.refreshToken);
    // Reusing the rotated token revokes everything, including the new one.
    await assert.rejects(tokens.rotateRefreshToken(first.refreshToken), { code: 'INVALID_REFRESH_TOKEN' });
    await assert.rejects(tokens.rotateRefreshToken(second.refreshToken), { code: 'INVALID_REFRESH_TOKEN' });
    await assert.rejects(tokens.rotateRefreshToken('unknown'), { code: 'INVALID_REFRESH_TOKEN' });
    await assert.rejects(tokens.rotateRefreshToken(undefined), { code: 'INVALID_REFRESH_TOKEN' });
  });

  it('expired refresh tokens and deleted users are rejected', async () => {
    const user = await User.create({ email: unique('exp'), passwordHash: 'x', name: 'Exp' });
    const { refreshToken } = await tokens.issueTokens(user);
    await RefreshToken.updateOne({ tokenHash: cryptoLib.sha256(refreshToken) }, { expiresAt: new Date(Date.now() - 1000) });
    await assert.rejects(tokens.rotateRefreshToken(refreshToken), { code: 'INVALID_REFRESH_TOKEN' });
    const gone = await User.create({ email: unique('gone'), passwordHash: 'x', name: 'Gone' });
    const goneTokens = await tokens.issueTokens(gone);
    await User.deleteOne({ _id: gone._id });
    await assert.rejects(tokens.rotateRefreshToken(goneTokens.refreshToken), { code: 'INVALID_REFRESH_TOKEN' });
  });

  it('concurrent refreshes with one token: at most one succeeds', async () => {
    const user = await User.create({ email: unique('race'), passwordHash: 'x', name: 'Race' });
    const { refreshToken } = await tokens.issueTokens(user);
    const results = await Promise.allSettled([tokens.rotateRefreshToken(refreshToken), tokens.rotateRefreshToken(refreshToken)]);
    assert.ok(results.filter((r) => r.status === 'fulfilled').length <= 1);
  });

  it('logout revokes only the given token of that user; revokeAll revokes the rest', async () => {
    const user = await User.create({ email: unique('logout'), passwordHash: 'x', name: 'Out' });
    const other = await User.create({ email: unique('other'), passwordHash: 'x', name: 'Other' });
    const a = await tokens.issueTokens(user);
    const b = await tokens.issueTokens(user);
    assert.equal(await tokens.revokeRefreshToken(a.refreshToken, { userId: other._id }), false, 'not your token');
    assert.equal(await tokens.revokeRefreshToken(a.refreshToken, { userId: user._id }), true);
    assert.equal(await tokens.revokeRefreshToken(a.refreshToken), false, 'idempotent');
    await tokens.rotateRefreshToken(b.refreshToken);
    assert.equal(await tokens.revokeAllUserTokens(user._id), 1);
  });
});

// ---------------------------------------------------------------- push, mail, serializers, directory

describe('services: push, mailer, serializers, member directory, cloudinary', () => {
  it('push: resolves recipients, excludes the actor, localizes per device and records in tests', async () => {
    const { family, admin, kid, kidUser, adminUser } = await seedFamily('push');
    await Device.create({ userId: kidUser._id, token: 'tok-kid', platform: 'android' });
    await Device.create({ userId: adminUser._id, token: 'tok-admin', platform: 'ios', locale: 'es' });
    const summary = await sendToMembers({
      familyId: family._id,
      excludeMemberIds: [admin._id],
      type: 'task_assigned',
      id: 'abc',
      route: '/tasks/abc',
      titleKey: 'common.errors.NOT_FOUND',
      bodyKey: 'common.errors.TOO_MANY_REQUESTS',
      vars: { seconds: 3 },
    });
    assert.equal(summary.recipients, 1);
    const record = sentPushes.at(-1);
    assert.equal(record.type, 'task_assigned');
    assert.equal(record.channelId, 'general');
    assert.deepEqual(record.memberIds, [String(kid._id)]);
    assert.equal(record.messages.length, 1);
    assert.equal(record.messages[0].token, 'tok-kid');
    assert.equal(record.messages[0].locale, 'ta', 'user locale when the device has none');
    assert.match(record.messages[0].body, /3/);

    void sendToMembers({ familyId: family._id, type: 'sos', id: 'x', route: '/sos/alert/x', titleKey: 'a.b', bodyKey: 'c.d' });
    await flushPushes();
    const sos = sentPushes.at(-1);
    assert.equal(sos.highPriority, true);
    assert.equal(sos.channelId, 'sos_alerts');
    assert.equal(sos.memberIds.length, 2, 'managed profiles without account are skipped');
    assert.equal(sos.messages.find((m) => m.token === 'tok-admin').locale, 'es', 'device locale wins');
  });

  it('push: users no longer linked to the family receive nothing; bad input never throws', async () => {
    const { family, kidUser } = await seedFamily('unlinked');
    await Device.create({ userId: kidUser._id, token: 'tok-unlinked', platform: 'android' });
    await User.updateOne({ _id: kidUser._id }, { familyId: null, memberId: null });
    const summary = await sendToMembers({ familyId: family._id, type: 'notice', id: 'n', route: '/notices', titleKey: 'a.b', bodyKey: 'c.d' });
    assert.equal(summary.devices, 0);
    assert.deepEqual(await sendToMembers({ familyId: 'not-an-id', type: 'notice', titleKey: 'a', bodyKey: 'b' }), { recipients: 0, devices: 0, sent: 0, failed: 0, removed: 0 });
    assert.deepEqual(await sendToMembers({}), { recipients: 0, devices: 0, sent: 0, failed: 0, removed: 0 });
  });

  it('mailer: renders localized templates into the test outbox', async () => {
    const res = await sendTemplate({ to: 'x@example.com', locale: 'de', template: 'common.missing', vars: { name: 'Asha', code: '123456' } });
    assert.equal(res.sent, true);
    const mail = outbox.at(-1);
    assert.equal(mail.to, 'x@example.com');
    assert.equal(mail.locale, 'de');
    assert.equal(mail.vars.code, '123456');
    assert.match(mail.text, /Asha/);
    assert.match(mail.html, /<html lang="de" dir="ltr"/);
    const arabic = await sendTemplate({ to: 'y@example.com', locale: 'ar', template: 'common.missing', vars: { name: '<b>x</b>' } });
    assert.equal(arabic.sent, true);
    assert.match(outbox.at(-1).html, /dir="rtl"/);
    assert.ok(!outbox.at(-1).html.includes('<b>x</b>'), 'variables are HTML-escaped');
    assert.equal((await sendTemplate({ to: 'z@example.com', template: 'no-namespace' })).sent, false);
  });

  it('serializers apply privacy rules and contract ordering', async () => {
    const { family, admin, kid, managed, kidUser } = await seedFamily('ser');
    const members = await Member.find({ familyId: family._id }).lean();
    assert.deepEqual(serializeMembers(members).map((m) => m.name), ['Admin', 'Kid', 'Grandma']);
    const a = serializeMember(admin);
    assert.deepEqual(Object.keys(a).sort(), [
      'avatarUrl', 'createdAt', 'dateOfBirth', 'designation', 'email', 'familyId', 'gender', 'guardianConsent', 'hasAccount',
      'id', 'lastLocation', 'locationSharing', 'name', 'phone', 'role', 'updatedAt', 'userId',
    ]);
    assert.deepEqual(Object.keys(a.lastLocation), ['lat', 'lng', 'accuracy', 'recordedAt']);
    assert.equal(serializeMember(kid).lastLocation, null, 'never-sharing member hides location');
    assert.equal(serializeMember(kid).locationSharing, 'never', 'private by default');
    assert.equal(serializeMember(managed).hasAccount, false);
    assert.equal(serializeFamily(family, { isAdmin: false, memberCount: 3 }).inviteCode, null);
    assert.match(serializeFamily(family, { isAdmin: true, memberCount: 3 }).inviteCode, enums.INVITE_CODE_REGEX);
    const u = serializeUser(await User.findById(kidUser._id), kid);
    assert.deepEqual(Object.keys(u).sort(), ['createdAt', 'email', 'emailVerified', 'familyId', 'id', 'locale', 'memberId', 'name', 'role']);
    assert.equal(u.role, 'member');
    assert.equal(typeof u.createdAt, 'string');
    const map = await getMemberMap(String(family._id));
    assert.equal(nameOf(map, kid._id), 'Kid');
    assert.equal(nameOf(map, null), null);
    assert.equal(await countAdmins(family._id), 1);
  });

  it('pagination, response envelope, family scoping and access checks', async () => {
    const one = await seedFamily('scopeA');
    const two = await seedFamily('scopeB');
    const page = await paginate(Member, { familyId: one.family._id }, { page: 2, limit: 2, sort: { createdAt: 1, _id: 1 } });
    assert.deepEqual([page.total, page.items.length, page.page, page.limit], [3, 1, 2, 2]);
    const agg = await paginateAggregate(Member, [{ $match: { familyId: one.family._id } }, { $sort: { name: 1 } }], { page: 1, limit: 2 });
    assert.deepEqual(agg.items.map((m) => m.name), ['Admin', 'Grandma']);
    assert.equal(agg.total, 3);
    assert.deepEqual(paginateArray([1, 2, 3], { page: 2, limit: 2 }), { items: [3], page: 2, limit: 2, total: 3 });
    assert.deepEqual(normalizePage({ page: -1, limit: 1000 }), { page: 1, limit: constants.MAX_PAGE_LIMIT, skip: 0 });

    const envelope = miniApp((app) => {
      app.get('/paged', (_req, res) => paged(res, { items: [1, 2], page: 1, limit: 2, total: 3 }));
      app.get('/ok', (_req, res) => ok(res, null));
    });
    assert.deepEqual((await envelope.get('/paged')).body, { success: true, data: [1, 2], meta: { page: 1, limit: 2, total: 3, hasMore: true } });
    assert.deepEqual((await envelope.get('/ok')).body, { success: true, data: null });

    const found = await findInFamily(Member, String(one.kid._id), String(one.family._id));
    assert.equal(found.name, 'Kid');
    await assert.rejects(findInFamily(Member, String(one.kid._id), String(two.family._id)), { code: 'NOT_FOUND' });
    await assert.rejects(findInFamily(Member, 'bad-id', String(one.family._id)), { code: 'NOT_FOUND' });
    const req = { user: { familyId: String(one.family._id), memberId: String(one.kid._id), role: 'member' } };
    assert.doesNotThrow(() => assertSelfOrAdmin(req, one.kid._id));
    assert.throws(() => assertSelfOrAdmin(req, one.admin._id), { code: 'FORBIDDEN' });
    assert.throws(() => assertAdmin(req), { code: 'FORBIDDEN' });
    assert.throws(() => assertAdmin({ user: { familyId: null } }), { code: 'NO_FAMILY' });
  });

  it('cloudinary: signs uploads into the family folder; URL checks', () => {
    const familyId = '64b7f0c2a1b2c3d4e5f60718';
    const sig = signUpload({ familyId, folder: 'avatars' });
    assert.deepEqual(Object.keys(sig).sort(), ['apiKey', 'cloudName', 'folder', 'signature', 'timestamp']);
    assert.equal(sig.folder, `familyhub/${familyId}/avatars`);
    assert.match(sig.signature, /^[a-f0-9]{40}$/);
    assert.throws(() => signUpload({ familyId, folder: 'secrets' }), { code: 'VALIDATION_ERROR' });
    assert.equal(isCloudinaryUrl('https://res.cloudinary.com/demo/image/upload/a.jpg'), true);
    assert.equal(isCloudinaryUrl('http://res.cloudinary.com/demo/image/upload/a.jpg'), false);
    assert.equal(isCloudinaryUrl('https://res.cloudinary.com.evil.com/a.jpg'), false);
    assert.equal(isFamilyAssetUrl(`https://res.cloudinary.com/demo/image/upload/v1/familyhub/${familyId}/avatars/a.jpg`, familyId), true);
    assert.equal(isFamilyAssetUrl('https://res.cloudinary.com/demo/image/upload/v1/familyhub/64b7f0c2a1b2c3d4e5f60719/avatars/a.jpg', familyId), false);
  });
});

// ---------------------------------------------------------------- models vs docs/06 §4 + contract

describe('models match docs/06-BACKEND_GUIDE.md §4 and the contract', () => {
  const FIELDS = {
    User: ['email', 'passwordHash', 'name', 'locale', 'emailVerified', 'familyId', 'memberId', 'failedLoginCount', 'lockUntil', 'lastLoginAt', 'consentAcceptedAt'],
    RefreshToken: ['userId', 'tokenHash', 'expiresAt', 'revokedAt', 'replacedByHash', 'ip', 'userAgent'],
    Otp: ['email', 'purpose', 'codeHash', 'expiresAt', 'attempts', 'lastSentAt', 'userId'],
    Family: ['name', 'inviteCode', 'country', 'currency', 'timezone', 'ownerId'],
    Member: ['familyId', 'userId', 'name', 'email', 'phone', 'avatarUrl', 'dateOfBirth', 'gender', 'designation', 'role', 'locationSharing', 'lastLocation', 'guardianConsent', 'guardianConsentAt', 'guardianConsentById'],
    Device: ['userId', 'token', 'platform', 'locale', 'lastSeenAt'],
    Task: ['familyId', 'title', 'description', 'assigneeId', 'createdById', 'dueDate', 'category', 'priority', 'status', 'completedAt', 'completedById'],
    LedgerEntry: ['familyId', 'type', 'amountMinor', 'category', 'note', 'date', 'memberId', 'memberName', 'createdById', 'goalId'],
    Goal: ['familyId', 'title', 'description', 'targetMinor', 'savedMinor', 'targetDate', 'status', 'createdById', 'achievedAt'],
    Notice: ['familyId', 'title', 'body', 'imageUrl', 'pinned', 'authorId'],
    SosAlert: ['familyId', 'memberId', 'status', 'message', 'locationShared', 'lastLocation', 'trail', 'lastLocationAt', 'startedAt', 'expiresAt', 'resolvedAt', 'resolvedById', 'resolution'],
    EmergencyCard: ['familyId', 'memberId', 'bloodGroup', 'allergiesEnc', 'medicationsEnc', 'conditionsEnc', 'doctorName', 'doctorPhone', 'insuranceProvider', 'insurancePolicyNumberEnc', 'emergencyContacts', 'notesEnc', 'updatedById'],
  };
  // [model, key, options that must match]
  const INDEXES = [
    ['User', { email: 1 }, { unique: true }],
    ['RefreshToken', { tokenHash: 1 }, { unique: true }],
    ['RefreshToken', { expiresAt: 1 }, { expireAfterSeconds: 0 }],
    ['RefreshToken', { userId: 1 }, {}],
    ['Otp', { email: 1, purpose: 1 }, { unique: true }],
    ['Otp', { expiresAt: 1 }, { expireAfterSeconds: models.OTP_PURGE_GRACE_SECONDS }],
    ['Family', { inviteCode: 1 }, { unique: true }],
    ['Member', { familyId: 1, role: 1 }, {}],
    ['Member', { familyId: 1, email: 1 }, { unique: true, partialFilterExpression: { email: { $type: 'string' } } }],
    ['Member', { userId: 1 }, { unique: true, partialFilterExpression: { userId: { $type: 'objectId' } } }],
    ['Device', { token: 1 }, { unique: true }],
    ['Device', { userId: 1 }, {}],
    ['Device', { lastSeenAt: 1 }, { expireAfterSeconds: models.DEVICE_STALE_AFTER_SECONDS }],
    ['Task', { familyId: 1, status: 1, dueDate: 1 }, {}],
    ['Task', { familyId: 1, assigneeId: 1, status: 1 }, {}],
    ['LedgerEntry', { familyId: 1, date: -1 }, {}],
    ['LedgerEntry', { familyId: 1, memberId: 1, date: -1 }, {}],
    ['LedgerEntry', { goalId: 1 }, {}],
    ['Goal', { familyId: 1, status: 1 }, {}],
    ['Notice', { familyId: 1, pinned: -1, createdAt: -1 }, {}],
    ['SosAlert', { familyId: 1, status: 1 }, {}],
    ['SosAlert', { memberId: 1, status: 1 }, {}],
    ['EmergencyCard', { memberId: 1 }, { unique: true }],
  ];

  it('models/index.js exports all 12 models (named + default map) and initModels', () => {
    assert.deepEqual(Object.keys(models.models).sort(), Object.keys(FIELDS).sort());
    for (const name of Object.keys(FIELDS)) {
      assert.equal(models[name], models.models[name], name);
      assert.equal(models.default[name], models[name], name);
    }
    assert.equal(typeof models.initModels, 'function');
  });

  it('every documented field exists on its schema', () => {
    for (const [name, fields] of Object.entries(FIELDS)) {
      for (const field of fields) assert.ok(models[name].schema.path(field), `${name}.${field}`);
      assert.ok(models[name].schema.path('createdAt') && models[name].schema.path('updatedAt'), `${name} timestamps`);
    }
  });

  it('every documented index is declared and built in MongoDB', async () => {
    for (const [name, key, opts] of INDEXES) {
      const declared = models[name].schema.indexes().find(([k]) => JSON.stringify(k) === JSON.stringify(key));
      assert.ok(declared, `${name} ${JSON.stringify(key)} declared`);
      for (const [opt, value] of Object.entries(opts)) assert.deepEqual(declared[1][opt], value, `${name} ${JSON.stringify(key)} ${opt}`);
      const built = (await models[name].listIndexes()).find((ix) => JSON.stringify(ix.key) === JSON.stringify(key));
      assert.ok(built, `${name} ${JSON.stringify(key)} built`);
      if (opts.unique) assert.equal(built.unique, true, `${name} ${JSON.stringify(key)} unique in DB`);
      if ('expireAfterSeconds' in opts) assert.equal(built.expireAfterSeconds, opts.expireAfterSeconds);
    }
  });

  it('persisted enums equal the contract lists and constants re-exports them', () => {
    assert.deepEqual([...enums.LOCALES], ['en', 'hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'ar', 'es', 'fr', 'pt', 'de']);
    assert.deepEqual([...enums.ROLES], ['admin', 'member']);
    assert.deepEqual([...enums.LOCATION_SHARING], ['never', 'sos_only', 'always']);
    assert.deepEqual([...enums.GENDERS], ['male', 'female', 'other']);
    assert.deepEqual([...enums.TASK_CATEGORIES], ['study', 'chore', 'skill', 'health', 'errand', 'other']);
    assert.deepEqual([...enums.TASK_PRIORITIES], ['low', 'medium', 'high']);
    assert.deepEqual([...enums.TASK_STATUSES], ['pending', 'done']);
    assert.deepEqual([...enums.INCOME_CATEGORIES], ['salary', 'business', 'allowance', 'gift', 'interest', 'other_income']);
    assert.deepEqual([...enums.EXPENSE_CATEGORIES], [
      'groceries', 'utilities', 'rent', 'education', 'health', 'transport', 'dining', 'shopping', 'entertainment', 'household_help', 'savings', 'other_expense',
    ]);
    assert.deepEqual([...enums.GOAL_STATUSES], ['active', 'achieved', 'archived']);
    assert.deepEqual([...enums.SOS_STATUSES], ['active', 'resolved', 'expired']);
    assert.deepEqual([...enums.SOS_RESOLUTIONS], ['safe', 'false_alarm', 'helped']);
    assert.deepEqual([...enums.BLOOD_GROUPS], ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'unknown']);
    assert.deepEqual([...enums.DEVICE_PLATFORMS], ['android', 'ios']);
    assert.deepEqual([...constants.PUSH_TYPES], ['sos', 'sos_resolved', 'task_assigned', 'task_completed', 'notice', 'goal_achieved', 'member_joined']);
    assert.deepEqual({ ...constants.PUSH_CHANNELS }, { SOS: 'sos_alerts', GENERAL: 'general' });
    for (const key of Object.keys(enums)) assert.equal(constants[key], enums[key], `constants re-exports ${key}`);
    assert.equal(i18n.SUPPORTED_LOCALES, enums.LOCALES);
    assert.ok(Object.isFrozen(enums.LOCALES) && Object.isFrozen(enums.LIMITS));
  });

  it('ErrorCodes cover every contract code', () => {
    const contract = [
      'BAD_REQUEST', 'INVALID_OTP', 'OTP_EXPIRED', 'INVALID_INVITE_CODE', 'UNAUTHORIZED', 'TOKEN_EXPIRED', 'INVALID_CREDENTIALS',
      'INVALID_REFRESH_TOKEN', 'FORBIDDEN', 'NO_FAMILY', 'LOCATION_SHARING_DISABLED', 'NOT_FOUND', 'EMAIL_TAKEN', 'ALREADY_IN_FAMILY',
      'MEMBER_EMAIL_EXISTS', 'LAST_ADMIN', 'SOS_NOT_ACTIVE', 'VALIDATION_ERROR', 'GUARDIAN_CONSENT_REQUIRED', 'TOO_MANY_REQUESTS', 'INTERNAL_ERROR',
    ];
    for (const code of contract) assert.equal(ErrorCodes[code], code);
    assert.equal(new ApiError(418, 'X').messageKey, 'common.errors.X');
  });

  it('toJSON: `id` string, no `_id` / `__v`, ObjectIds flattened, secrets hidden', () => {
    const familyId = oid();
    const docs = {
      User: new User({ email: 'a@example.com', passwordHash: 'hash', name: 'A', familyId, failedLoginCount: 2, lastFailedLoginAt: new Date(), lockUntil: new Date(Date.now() + 60_000) }),
      RefreshToken: new RefreshToken({ userId: oid(), tokenHash: 'h', replacedByHash: 'r', expiresAt: new Date() }),
      Otp: new Otp({ email: 'a@example.com', purpose: 'verify_email', codeHash: 'h', expiresAt: new Date() }),
      Member: new Member({ familyId, name: 'M' }),
      EmergencyCard: new EmergencyCard({ familyId, memberId: oid(), allergies: ['Peanuts'], notes: 'n' }),
    };
    const hidden = {
      User: ['passwordHash', 'failedLoginCount', 'lastFailedLoginAt', 'lockUntil'],
      RefreshToken: ['tokenHash', 'replacedByHash'],
      Otp: ['codeHash'],
      Member: [],
      EmergencyCard: ['allergiesEnc', 'medicationsEnc', 'conditionsEnc', 'insurancePolicyNumberEnc', 'notesEnc'],
    };
    for (const [name, doc] of Object.entries(docs)) {
      const json = JSON.parse(JSON.stringify(doc));
      assert.equal(json.id, String(doc._id), name);
      assert.ok(!('_id' in json) && !('__v' in json), name);
      for (const field of hidden[name]) assert.ok(!(field in json), `${name}.${field} hidden`);
    }
    const member = JSON.parse(JSON.stringify(docs.Member));
    assert.equal(member.familyId, String(familyId));
    assert.equal(member.hasAccount, false);
    assert.equal(member.locationSharing, 'never');
    assert.equal(member.role, 'member');
    assert.deepEqual(JSON.parse(JSON.stringify(docs.EmergencyCard)).allergies, ['Peanuts']);
    assert.equal(JSON.parse(JSON.stringify(docs.User)).isLocked, true);
  });

  it('Family: random strict invite codes by default; the demo code DEMO2345 is storable and upper-cased', async () => {
    const base = { name: 'F', country: 'in', currency: 'inr', timezone: 'Asia/Kolkata', ownerId: oid() };
    const generated = await Family.create(base);
    assert.match(generated.inviteCode, enums.INVITE_CODE_REGEX);
    assert.equal(generated.country, 'IN');
    assert.equal(generated.currency, 'INR');
    const demo = await Family.create({ ...base, inviteCode: ' demo2345 ' });
    assert.equal(demo.inviteCode, 'DEMO2345');
    assert.equal(String((await Family.findOne({ inviteCode: v.inviteCode.parse('demo-2345') }))._id), String(demo._id));
    await assert.rejects(Family.create({ ...base, inviteCode: 'SHORT' }), mongoose.Error.ValidationError);
    await assert.rejects(Family.create({ ...base, timezone: 'Mars/Olympus' }), mongoose.Error.ValidationError);
    for (const code of Object.keys(COUNTRIES)) assert.match(code, /^[A-Z]{2}$/);
    for (const currency of CURRENCIES) assert.match(currency, /^[A-Z]{3}$/);
  });

  it('EmergencyCard: encrypted at rest, contract-shaped plaintext, empty card has the same keys', async () => {
    assert.deepEqual(Object.keys(models.ENCRYPTED_CARD_FIELDS), [...enums.EMERGENCY_CARD_ENCRYPTED_FIELDS]);
    const input = {
      bloodGroup: 'O+',
      allergies: ['Peanuts', 'पेनिसिलिन'],
      medications: ['Metformin 500mg'],
      conditions: ['Asthma'],
      doctorName: 'Dr. Rao',
      doctorPhone: '+919876543210',
      insuranceProvider: 'Star Health',
      insurancePolicyNumber: 'P-123',
      emergencyContacts: [{ name: 'Ravi', phone: '+919812345678', relation: 'Uncle' }],
      notes: 'Carries an inhaler',
    };
    const memberId = oid();
    const card = new EmergencyCard({ familyId: oid(), memberId });
    Object.assign(card, input);
    await card.save();
    const raw = await EmergencyCard.collection.findOne({ _id: card._id });
    for (const { path: enc } of Object.values(models.ENCRYPTED_CARD_FIELDS)) assert.match(raw[enc], /^enc:v1:/, enc);
    for (const secret of ['Peanuts', 'Metformin', 'Asthma', 'P-123', 'inhaler']) assert.ok(!JSON.stringify(raw).includes(secret), secret);
    const plain = (await EmergencyCard.findById(card._id)).toPlainCard();
    const { updatedAt, updatedById, memberId: mid, ...rest } = plain;
    assert.deepEqual(rest, input);
    assert.equal(mid, String(memberId));
    assert.equal(typeof updatedAt, 'string');
    assert.equal(updatedById, null);
    const empty = EmergencyCard.emptyCard(memberId);
    assert.deepEqual(Object.keys(empty).sort(), Object.keys(plain).sort());
    assert.equal(empty.updatedAt, null);
    card.allergies = [];
    card.notes = '   ';
    await card.save();
    const cleared = await EmergencyCard.collection.findOne({ _id: card._id });
    assert.equal(cleared.allergiesEnc, null);
    assert.equal(cleared.notesEnc, null);
    assert.deepEqual((await EmergencyCard.findById(card._id)).toPlainCard().allergies, []);
  });

  it('SOS / Goal / Ledger / Device / Task / Notice model rules', async () => {
    const familyId = oid();
    const memberId = oid();
    const startedAt = new Date(Date.now() - 20 * 60 * 1000); // expired 5 min ago
    const alert = await SosAlert.create({ familyId, memberId, startedAt });
    assert.equal(alert.expiresAt.getTime() - startedAt.getTime(), enums.SOS_DURATION_MS);
    assert.equal(alert.effectiveStatus(new Date(alert.expiresAt.getTime() - 1000)), 'active');
    assert.equal(alert.effectiveStatus(alert.expiresAt), 'expired');
    assert.equal(alert.isActive(), false);
    const points = Array.from({ length: enums.SOS_TRAIL_MAX + 5 }, (_, i) => ({ lat: 1, lng: i % 180, recordedAt: new Date(startedAt.getTime() + i * 1000) }));
    await SosAlert.updateOne({ _id: alert._id }, { $push: { trail: { $each: points, $slice: -enums.SOS_TRAIL_MAX } } });
    const trail = (await SosAlert.findById(alert._id)).trail;
    assert.equal(trail.length, enums.SOS_TRAIL_MAX);
    assert.equal(trail.at(-1).lng, points.at(-1).lng, 'newest points are kept');
    assert.equal(await SosAlert.expireStale({ familyId }), 1);
    assert.equal((await SosAlert.findById(alert._id)).status, 'expired');

    const goal = new Goal({ familyId, title: 'Goa vacation', targetMinor: money.toMinor(60000), savedMinor: money.toMinor(12500), createdById: memberId });
    assert.equal(goal.progress, 0.2083);
    goal.savedMinor = money.toMinor(70000);
    assert.equal(goal.progress, 1);

    const entry = { familyId, amountMinor: 100, date: new Date(), memberId, memberName: 'Priya', createdById: memberId };
    await assert.rejects(LedgerEntry.create({ ...entry, type: 'income', category: 'groceries' }), mongoose.Error.ValidationError);
    await assert.rejects(LedgerEntry.create({ ...entry, type: 'expense', category: 'groceries', amountMinor: 1.5 }), mongoose.Error.ValidationError);
    const saved = await LedgerEntry.create({ ...entry, type: 'expense', category: enums.SAVINGS_CATEGORY });
    await assert.rejects(
      LedgerEntry.updateOne({ _id: saved._id }, { $set: { type: 'income', category: 'rent' } }, { runValidators: true }),
      mongoose.Error.ValidationError,
    );

    const device = await Device.findOneAndUpdate(
      { token: 'fcm-1' },
      { $set: { userId: oid(), platform: 'android' } },
      { upsert: true, returnDocument: 'after' },
    );
    assert.ok(device.lastSeenAt instanceof Date);

    const task = new Task({ familyId, title: 'Homework', assigneeId: memberId, createdById: memberId, dueDate: new Date('2026-09-01') });
    assert.deepEqual([task.status, task.category, task.priority], ['pending', 'other', 'medium']);
    assert.equal(task.isOverdue(new Date('2026-09-02')), true);
    assert.equal(new Notice({ familyId, title: 't', body: 'b', authorId: memberId }).pinned, false);
  });
});

// ---------------------------------------------------------------- export contract

describe('shared module exports match docs/06-BACKEND_GUIDE.md §3', () => {
  const expected = {
    '../src/middleware/auth.js': ['requireAuth', 'requireFamily', 'requireAdmin', 'familyMember', 'familyAdmin'],
    '../src/middleware/rateLimit.js': ['authLimiter', 'globalLimiter', 'createRateLimiter'],
    '../src/middleware/error.js': ['errorHandler', 'notFoundHandler', 'toApiError', 'localizeError'],
    '../src/middleware/locale.js': ['localeMiddleware', 'setRequestLocale'],
    '../src/services/tokens.js': ['signAccessToken', 'verifyAccessToken', 'issueTokens', 'rotateRefreshToken', 'revokeRefreshToken', 'revokeAllUserTokens'],
    '../src/services/serializers.js': ['serializeUser', 'serializeFamily', 'serializeMember', 'serializeMembers', 'serializeLocation', 'sortMembers', 'idOf', 'iso'],
    '../src/services/memberDirectory.js': ['getMemberMap', 'nameOf', 'memberOf', 'avatarOf', 'countMembers', 'countAdmins'],
    '../src/services/mailer.js': ['sendMail', 'sendTemplate', 'renderTemplate', 'outbox', 'closeMailer'],
    '../src/services/push.js': ['initPush', 'isPushEnabled', 'sendToMembers', 'sentPushes', 'flushPushes'],
    '../src/services/cloudinary.js': ['isCloudinaryConfigured', 'signUpload', 'isCloudinaryUrl', 'isFamilyAssetUrl', 'familyFolder'],
    '../src/lib/access.js': ['findInFamily', 'familyFilter', 'isAdmin', 'isSelf', 'assertFamily', 'assertAdmin', 'assertSelfOrAdmin', 'toId', 'sameId', 'isObjectId'],
    '../src/lib/pagination.js': ['paginate', 'paginateAggregate', 'paginateArray', 'normalizePage'],
    '../src/lib/dates.js': ['monthRange', 'currentMonth', 'startOfDay', 'startOfNextDay', 'startOfWeek', 'dayRange', 'weekRange', 'ageFrom', 'isValidTimeZone', 'toIso'],
    '../src/lib/money.js': ['toMinor', 'fromMinor', 'roundMoney', 'sumMinor', 'isValidAmount', 'MAX_AMOUNT'],
    '../src/lib/i18n.js': ['t', 'tOr', 'pickLocale', 'SUPPORTED_LOCALES', 'normalizeLocale', 'isSupportedLocale', 'hasTranslation'],
    '../src/lib/crypto.js': ['sha256', 'randomToken', 'randomDigits', 'randomInviteCode', 'safeEqual', 'encryptField', 'decryptField'],
    '../src/lib/mongoosePlugins.js': ['toJsonPlugin'],
    '../src/lib/countries.js': ['COUNTRIES', 'COUNTRY_CODES', 'CURRENCIES', 'consentAge', 'isCountry', 'isCurrency', 'getCountry', 'emergencyNumber', 'currencyOf'],
    '../src/lib/response.js': ['ok', 'created', 'paged'],
    '../src/lib/validate.js': [
      'validate', 'zodIssuesToDetails', 'nullableField', 'objectId', 'nullableObjectId', 'idParams', 'email', 'nullableEmail', 'password',
      'trimmed', 'personName', 'optionalText', 'isoDate', 'nullableIsoDate', 'monthString', 'pagination', 'paginationQuery', 'locale',
      'nullableGender', 'countryCode', 'currencyCode', 'timeZone', 'inviteCode', 'phone', 'nullablePhone', 'cloudinaryUrl',
      'nullableCloudinaryUrl', 'moneyAmount', 'latLng',
    ],
    '../src/lib/ApiError.js': ['ApiError', 'ErrorCodes'],
    '../src/lib/logger.js': ['logger'],
    '../src/config/db.js': ['connectDb', 'disconnectDb', 'isDbUp'],
    '../src/config/env.js': ['env'],
    '../src/app.js': ['createApp', 'API_PREFIX'],
    '../src/server.js': ['startServer'],
  };
  for (const [file, names] of Object.entries(expected)) {
    it(file.replace('../src/', ''), async () => {
      const mod = await import(file);
      for (const name of names) assert.ok(name in mod, `${file} must export ${name}`);
    });
  }

  it('ApiError helpers produce contract codes', () => {
    const cases = [
      [ApiError.badRequest(), 400, 'BAD_REQUEST'],
      [ApiError.validation({ a: 'b' }), 422, 'VALIDATION_ERROR'],
      [ApiError.unauthorized(), 401, 'UNAUTHORIZED'],
      [ApiError.tokenExpired(), 401, 'TOKEN_EXPIRED'],
      [ApiError.invalidCredentials(), 401, 'INVALID_CREDENTIALS'],
      [ApiError.invalidRefreshToken(), 401, 'INVALID_REFRESH_TOKEN'],
      [ApiError.forbidden(), 403, 'FORBIDDEN'],
      [ApiError.noFamily(), 403, 'NO_FAMILY'],
      [ApiError.notFound(), 404, 'NOT_FOUND'],
      [ApiError.conflict('LAST_ADMIN'), 409, 'LAST_ADMIN'],
      [ApiError.conflict(), 409, 'CONFLICT'],
      [ApiError.tooManyRequests(0.2), 429, 'TOO_MANY_REQUESTS'],
      [ApiError.internal(), 500, 'INTERNAL_ERROR'],
      [ApiError.serviceUnavailable(), 503, 'SERVICE_UNAVAILABLE'],
    ];
    for (const [err, status, code] of cases) {
      assert.ok(err instanceof ApiError);
      assert.equal(err.status, status, code);
      assert.equal(err.code, code);
    }
    assert.equal(ApiError.tooManyRequests(0.2).details.retryAfterSeconds, 1, 'rounded up, at least 1 s');
    assert.equal(consentAge('IN'), 18);
    assert.equal(consentAge('us'), 13);
    assert.equal(consentAge('ZZ'), 18, 'unknown country → strictest');
    assert.ok(isCountry('de'));
  });
});
