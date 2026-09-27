/**
 * Notices: docs/03-API_CONTRACT.md §9 (`GET|POST /notices`, `PATCH|DELETE /notices/:id`).
 *
 * Covers the Notice shape and envelope, pinned-first / newest-first ordering, pagination (meta,
 * boundaries, stable pages), the permission matrix (author / admin / other member / other family /
 * no family / no token), `pinned` (ignored on create for members, 403 on change for members, no-op
 * when unchanged), Cloudinary-only `imageUrl`, every contract limit with its boundary, 422 `details`,
 * 400 for malformed ids / JSON, forged read-only keys, authors who left the family, the `notice`
 * push (audience, localized text, no body content, shortened title), no-op PATCH (no write) and
 * concurrent deletes.
 *
 * Hardening review (b-notices-harden, last section): UTF-16 limits with emoji, invisible / control /
 * ill-formed text, RTL kept as typed, Cloudinary URL tricks (user info, port, canonical form), NoSQL
 * operator injection and mass assignment via body and query, pagination extremes, members who left
 * or moved to another family, concurrent PATCH / DELETE, per-recipient push locale, 413 payloads,
 * the per-account posting rate limit (child process, limiters are off in this process) and the
 * dashboard helper's defensive bounds.
 */
import {
  API,
  authHeader,
  flushPushes,
  joinFamilyAs,
  registerFamilyAdmin,
  resetDb,
  sentPushes,
  setupTestApp,
  teardownTestApp,
} from './helpers.js';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { after, before, beforeEach, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const { default: mongoose } = await import('mongoose');
const { env } = await import('../src/config/env.js');
const { Device, Member, Notice, User } = await import('../src/models/index.js');
const { loadTranslations, t } = await import('../src/lib/i18n.js');
const { listLatestNotices } = await import('../src/modules/notices/notices.service.js');
const { NOTICE_POST_RATE_LIMIT_PER_MINUTE } = await import('../src/modules/notices/notices.routes.js');

let request;

before(async () => {
  ({ request } = await setupTestApp());
});
beforeEach(resetDb);
after(teardownTestApp);

// ---------------------------------------------------------------- helpers

const OBJECT_ID = /^[a-f0-9]{24}$/;
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const UNKNOWN_ID = 'aaaaaaaaaaaaaaaaaaaaaaaa';
const IMAGE = 'https://res.cloudinary.com/demo/image/upload/v1700000000/familyhub/f/notices/photo.jpg';
const IMAGE_2 = 'https://res.cloudinary.com/demo/image/upload/v1700000001/familyhub/f/notices/other.png';
const AVATAR = 'https://res.cloudinary.com/demo/image/upload/v1/familyhub/f/avatars/me.jpg';

const NOTICE_KEYS = [
  'authorAvatarUrl',
  'authorId',
  'authorName',
  'body',
  'createdAt',
  'id',
  'imageUrl',
  'pinned',
  'title',
  'updatedAt',
].sort();

const url = (id) => (id ? `${API}/notices/${id}` : `${API}/notices`);
const list = (auth, query = {}) => request.get(url()).query(query).set(auth);
const post = (auth, body) => request.post(url()).set(auth).send(body);
const patch = (auth, id, body) => request.patch(url(id)).set(auth).send(body);
const del = (auth, id) => request.delete(url(id)).set(auth);

function assertOk(res, status = 200) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.equal(res.body.success, true);
  assert.ok('data' in res.body);
  assert.ok(!('error' in res.body));
  return res.body.data;
}

/** Non-paginated success: no `meta`. */
function assertItem(res, status = 200) {
  const data = assertOk(res, status);
  assert.ok(!('meta' in res.body), 'meta only on paginated lists');
  return data;
}

/** Paginated success: `data` array + exact `meta`. */
function assertPage(res, { page, limit, total }) {
  const data = assertOk(res);
  assert.ok(Array.isArray(data));
  assert.deepEqual(res.body.meta, { page, limit, total, hasMore: page * limit < total });
  return data;
}

function assertError(res, status, code) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.equal(res.body.success, false);
  assert.ok(!('data' in res.body));
  assert.equal(res.body.error.code, code);
  assert.equal(typeof res.body.error.message, 'string');
  assert.ok(res.body.error.message.length > 0);
  assert.ok(!('stack' in res.body.error));
  return res.body.error;
}

/** 422 VALIDATION_ERROR whose `details` contain every expected path. */
function assertValidation(res, ...paths) {
  const error = assertError(res, 422, 'VALIDATION_ERROR');
  assert.equal(typeof error.details, 'object', JSON.stringify(res.body));
  for (const path of paths) {
    assert.equal(typeof error.details[path], 'string', `details.${path} missing in ${JSON.stringify(error.details)}`);
    assert.ok(error.details[path].length > 0);
  }
  return error.details;
}

function assertNoticeShape(notice) {
  assert.deepEqual(Object.keys(notice).sort(), NOTICE_KEYS);
  assert.match(notice.id, OBJECT_ID);
  assert.match(notice.authorId, OBJECT_ID);
  assert.match(notice.createdAt, ISO);
  assert.match(notice.updatedAt, ISO);
  assert.equal(typeof notice.pinned, 'boolean');
  for (const forbidden of ['_id', '__v', 'familyId']) assert.ok(!(forbidden in notice), `${forbidden} must not be exposed`);
}

/**
 * Family A: admin (Amit) + member (Priya). Family B: its own admin. Join pushes are cleared.
 */
async function twoFamilies() {
  const admin = await registerFamilyAdmin({ name: 'Amit Sharma' });
  const member = await joinFamilyAs(admin.family.inviteCode, { name: 'Priya Sharma' });
  const otherAdmin = await registerFamilyAdmin({ name: 'Other Admin', family: { name: 'Other Family' } });
  await flushPushes();
  sentPushes.length = 0;
  return { admin, member, otherAdmin };
}

const noticeBody = (overrides = {}) => ({ title: 'Dinner at 8', body: 'Everyone home by 8 pm, please.', ...overrides });

async function createNotice(auth, overrides) {
  return assertItem(await post(auth, noticeBody(overrides)), 201);
}

/** Sets `createdAt` directly in MongoDB (Mongoose timestamps cannot be overridden on create). */
function setCreatedAt(id, date) {
  return Notice.collection.updateOne({ _id: new mongoose.Types.ObjectId(id) }, { $set: { createdAt: new Date(date) } });
}

function rawNotice(id) {
  return Notice.collection.findOne({ _id: new mongoose.Types.ObjectId(id) });
}

/** A signed-in user of a family whose member row is gone → `403 NO_FAMILY` (see middleware/auth.js). */
async function withoutFamily(account) {
  await User.updateOne({ _id: account.user.id }, { $set: { familyId: null, memberId: null } });
  return account;
}

const PROTECTED_ROUTES = [
  ['get', url()],
  ['post', url()],
  ['patch', url(UNKNOWN_ID)],
  ['delete', url(UNKNOWN_ID)],
];

// ---------------------------------------------------------------- auth

describe('/notices authentication', () => {
  it('401 UNAUTHORIZED without / with an invalid token on every route', async () => {
    for (const [method, path] of PROTECTED_ROUTES) {
      assertError(await request[method](path).send(noticeBody()), 401, 'UNAUTHORIZED');
      assertError(
        await request[method](path).set({ Authorization: 'Bearer not-a-jwt' }).send(noticeBody()),
        401,
        'UNAUTHORIZED',
      );
    }
  });

  it('403 NO_FAMILY for a signed-in user without a family on every route', async () => {
    const { member } = await twoFamilies();
    await withoutFamily(member);
    for (const [method, path] of PROTECTED_ROUTES) {
      assertError(await request[method](path).set(member.auth).send(noticeBody()), 403, 'NO_FAMILY');
    }
    assert.equal(await Notice.countDocuments(), 0);
  });
});

// ---------------------------------------------------------------- POST

describe('POST /notices', () => {
  it('lets a member post a notice → 201 contract Notice (trimmed, author filled in, not pinned)', async () => {
    const { member } = await twoFamilies();
    const res = await post(member.auth, { title: '  Dinner at 8  ', body: '\n Line one\nLine two \n' });
    const notice = assertItem(res, 201);
    assertNoticeShape(notice);
    assert.equal(notice.title, 'Dinner at 8');
    assert.equal(notice.body, 'Line one\nLine two', 'ends trimmed, inner line breaks kept');
    assert.equal(notice.imageUrl, null);
    assert.equal(notice.pinned, false);
    assert.equal(notice.authorId, member.member.id);
    assert.equal(notice.authorName, 'Priya Sharma');
    assert.equal(notice.authorAvatarUrl, null);
    assert.equal(notice.createdAt, notice.updatedAt);

    const raw = await rawNotice(notice.id);
    assert.equal(String(raw.familyId), member.family.id);
    assert.equal(String(raw.authorId), member.member.id);
  });

  it('lets an admin post a pinned notice with a Cloudinary image', async () => {
    const { admin } = await twoFamilies();
    const notice = await createNotice(admin.auth, { pinned: true, imageUrl: IMAGE });
    assert.equal(notice.pinned, true);
    assert.equal(notice.imageUrl, IMAGE);
    assert.equal(notice.authorName, 'Amit Sharma');
  });

  it('silently ignores `pinned` from a member (201, stored unpinned)', async () => {
    const { member } = await twoFamilies();
    const notice = await createNotice(member.auth, { pinned: true });
    assert.equal(notice.pinned, false);
    assert.equal((await rawNotice(notice.id)).pinned, false);
  });

  it('treats a null or blank imageUrl as "no image"', async () => {
    const { member } = await twoFamilies();
    assert.equal((await createNotice(member.auth, { imageUrl: null })).imageUrl, null);
    assert.equal((await createNotice(member.auth, { imageUrl: '   ' })).imageUrl, null);
  });

  it("returns the author's avatar as authorAvatarUrl", async () => {
    const { member } = await twoFamilies();
    await Member.updateOne({ _id: member.member.id }, { $set: { avatarUrl: AVATAR } });
    assert.equal((await createNotice(member.auth)).authorAvatarUrl, AVATAR);
  });

  it('ignores forged read-only keys (authorId, familyId, id, createdAt)', async () => {
    const { admin, member, otherAdmin } = await twoFamilies();
    const notice = await createNotice(member.auth, {
      authorId: admin.member.id,
      familyId: otherAdmin.family.id,
      id: UNKNOWN_ID,
      createdAt: '2000-01-01T00:00:00.000Z',
    });
    assert.equal(notice.authorId, member.member.id);
    assert.notEqual(notice.id, UNKNOWN_ID);
    assert.notEqual(notice.createdAt, '2000-01-01T00:00:00.000Z');
    assert.equal(String((await rawNotice(notice.id)).familyId), member.family.id);
  });

  it('accepts the contract boundaries (title 1 and 100, body 1 and 2000 chars)', async () => {
    const { member } = await twoFamilies();
    const min = await createNotice(member.auth, { title: 'A', body: 'B' });
    assert.equal(min.title, 'A');
    const max = await createNotice(member.auth, { title: 'T'.repeat(100), body: 'b'.repeat(2000) });
    assert.equal(max.title.length, 100);
    assert.equal(max.body.length, 2000);
    const multilingual = await createNotice(member.auth, { title: 'पारिवारिक बैठक 🎉', body: 'اجتماع العائلة يوم الأحد' });
    assert.equal(multilingual.title, 'पारिवारिक बैठक 🎉');
    assert.equal(multilingual.body, 'اجتماع العائلة يوم الأحد');
  });

  it('422 VALIDATION_ERROR with field details for invalid bodies, and writes nothing', async () => {
    const { admin } = await twoFamilies();
    const cases = [
      [{}, ['title', 'body']],
      [{ title: null, body: null }, ['title', 'body']],
      [{ title: '   ', body: '\n\t ' }, ['title', 'body']],
      [{ title: 'T'.repeat(101) }, ['title']],
      [{ body: 'b'.repeat(2001) }, ['body']],
      [{ title: 42, body: ['x'] }, ['title', 'body']],
      [{ imageUrl: 'https://example.com/photo.jpg' }, ['imageUrl']],
      [{ imageUrl: 'http://res.cloudinary.com/demo/image/upload/a.jpg' }, ['imageUrl']],
      [{ imageUrl: 'https://res.cloudinary.com.evil.example/a.jpg' }, ['imageUrl']],
      [{ imageUrl: 'res.cloudinary.com/a.jpg' }, ['imageUrl']],
      [{ imageUrl: `https://res.cloudinary.com/${'a'.repeat(1100)}.jpg` }, ['imageUrl']],
      [{ imageUrl: 123 }, ['imageUrl']],
      [{ pinned: 'true' }, ['pinned']],
      [{ pinned: 1 }, ['pinned']],
      [{ pinned: null }, ['pinned']],
    ];
    for (const [overrides, paths] of cases) {
      const input = Object.keys(overrides).length ? { ...noticeBody(), ...overrides } : {};
      assertValidation(await post(admin.auth, input), ...paths);
    }
    assert.equal(await Notice.countDocuments(), 0);
    assert.equal(sentPushes.length, 0);
  });

  it('400 BAD_REQUEST for malformed JSON', async () => {
    const { member } = await twoFamilies();
    const res = await request.post(url()).set(member.auth).set('Content-Type', 'application/json').send('{"title": "x",');
    assertError(res, 400, 'BAD_REQUEST');
    assert.equal(await Notice.countDocuments(), 0);
  });
});

// ---------------------------------------------------------------- push

describe('POST /notices push', () => {
  /** Family with admin, two members with accounts and a managed child; every account has a device. */
  async function familyWithDevices() {
    const { admin, member, otherAdmin } = await twoFamilies();
    const member2 = await joinFamilyAs(admin.family.inviteCode, { name: 'Dadi Sharma' });
    const child = await Member.create({
      familyId: admin.family.id,
      name: 'Anaya',
      role: 'member',
      dateOfBirth: new Date('2016-08-01T00:00:00.000Z'),
      guardianConsent: true,
    });
    await Device.create([
      { userId: admin.user.id, token: 'token-admin', platform: 'android', locale: 'en' },
      { userId: member.user.id, token: 'token-member', platform: 'ios', locale: 'en' },
      { userId: member2.user.id, token: 'token-member2', platform: 'android', locale: 'hi' },
      { userId: otherAdmin.user.id, token: 'token-other', platform: 'android', locale: 'en' },
    ]);
    await flushPushes();
    sentPushes.length = 0;
    return { admin, member, member2, child, otherAdmin };
  }

  it('sends one `notice` push to every other member with an account (author, managed profiles, other families excluded)', async () => {
    const { admin, member, member2 } = await familyWithDevices();
    const body = 'Secret family plans: the surprise party is on Sunday.';
    const notice = await createNotice(member.auth, { title: 'Party!', body });

    assert.equal(sentPushes.length, 1);
    const push = sentPushes[0];
    assert.equal(push.type, 'notice');
    assert.equal(push.id, notice.id);
    assert.equal(push.route, '/notices');
    assert.equal(push.familyId, member.family.id);
    assert.equal(push.channelId, 'general');
    assert.equal(push.highPriority, false);
    assert.equal(push.titleKey, 'notices.push.new.title');
    assert.equal(push.bodyKey, 'notices.push.new.body');
    assert.deepEqual(push.vars, { name: 'Priya Sharma', title: 'Party!' });
    assert.deepEqual(push.excludeMemberIds, [member.member.id]);

    await flushPushes();
    assert.deepEqual([...push.memberIds].sort(), [admin.member.id, member2.member.id].sort());
    const tokens = push.messages.map((m) => m.token).sort();
    assert.deepEqual(tokens, ['token-admin', 'token-member2']);
    for (const message of push.messages) {
      // Each device in its own locale (`hi` falls back to English until notices.json is translated);
      // never the notice body.
      assert.equal(message.locale, message.token === 'token-member2' ? 'hi' : 'en');
      assert.equal(message.title, t(message.locale, 'notices.push.new.title', { name: 'Priya Sharma' }));
      assert.equal(message.body, t(message.locale, 'notices.push.new.body', { title: 'Party!' }));
      assert.ok(message.title.includes('Priya Sharma') && message.body.includes('Party!'));
      assert.ok(!message.title.includes(body) && !message.body.includes(body), 'the body never leaves in a push');
    }
  });

  it('uses the "important" title for a notice an admin pins on creation', async () => {
    const { admin } = await familyWithDevices();
    await createNotice(admin.auth, { pinned: true, title: 'Rent due' });
    assert.equal(sentPushes.length, 1);
    assert.equal(sentPushes[0].titleKey, 'notices.push.new.titlePinned');
    await flushPushes();
    for (const message of sentPushes[0].messages) {
      assert.equal(message.title, t(message.locale, 'notices.push.new.titlePinned', { name: 'Amit Sharma' }));
    }
    assert.equal(t('en', 'notices.push.new.titlePinned', { name: 'Amit Sharma' }), 'Important notice from Amit Sharma');
  });

  it('a member asking for `pinned` still gets the normal push title', async () => {
    const { member } = await familyWithDevices();
    await createNotice(member.auth, { pinned: true });
    assert.equal(sentPushes[0].titleKey, 'notices.push.new.title');
  });

  it('shortens long titles in the push text (≤ 60 characters, ellipsis)', async () => {
    const { member } = await familyWithDevices();
    const title = 'X'.repeat(100);
    const notice = await createNotice(member.auth, { title });
    assert.equal(notice.title, title, 'the notice itself keeps the full title');
    const pushed = sentPushes[0].vars.title;
    assert.equal(Array.from(pushed).length, 60);
    assert.ok(pushed.endsWith('…'));
  });

  it('sends no push when nobody else in the family has an account', async () => {
    const admin = await registerFamilyAdmin({ name: 'Solo Admin' });
    await Member.create({ familyId: admin.family.id, name: 'Baby', role: 'member', guardianConsent: true });
    sentPushes.length = 0;
    await createNotice(admin.auth);
    assert.equal(sentPushes.length, 0);
  });

  it('PATCH and DELETE never push', async () => {
    const { admin, member } = await familyWithDevices();
    const notice = await createNotice(member.auth);
    sentPushes.length = 0;
    assertItem(await patch(member.auth, notice.id, { title: 'Changed' }));
    assertItem(await patch(admin.auth, notice.id, { pinned: true }));
    assertItem(await del(admin.auth, notice.id));
    assert.equal(sentPushes.length, 0);
  });
});

// ---------------------------------------------------------------- GET

describe('GET /notices', () => {
  it('returns an empty page with meta when the board is empty', async () => {
    const { member } = await twoFamilies();
    const data = assertPage(await list(member.auth), { page: 1, limit: 20, total: 0 });
    assert.deepEqual(data, []);
  });

  it('sorts pinned notices first, then newest first (createdAt desc)', async () => {
    const { admin, member } = await twoFamilies();
    const oldPinned = await createNotice(admin.auth, { title: 'old pinned', pinned: true });
    const newPinned = await createNotice(admin.auth, { title: 'new pinned', pinned: true });
    const oldest = await createNotice(member.auth, { title: 'oldest' });
    const middle = await createNotice(admin.auth, { title: 'middle' });
    const newest = await createNotice(member.auth, { title: 'newest' });
    await setCreatedAt(oldPinned.id, '2026-01-01T00:00:00.000Z');
    await setCreatedAt(newPinned.id, '2026-02-01T00:00:00.000Z');
    await setCreatedAt(oldest.id, '2026-01-15T00:00:00.000Z');
    await setCreatedAt(middle.id, '2026-03-01T00:00:00.000Z');
    await setCreatedAt(newest.id, '2026-04-01T00:00:00.000Z');

    const data = assertPage(await list(member.auth), { page: 1, limit: 20, total: 5 });
    assert.deepEqual(
      data.map((n) => n.title),
      ['new pinned', 'old pinned', 'newest', 'middle', 'oldest'],
    );
    data.forEach(assertNoticeShape);
    assert.equal(data[0].createdAt, '2026-02-01T00:00:00.000Z');
    assert.equal(data.find((n) => n.title === 'oldest').authorName, 'Priya Sharma');
    assert.equal(data.find((n) => n.title === 'middle').authorName, 'Amit Sharma');
  });

  it('paginates with stable, non-overlapping pages even when createdAt ties', async () => {
    const { admin, member } = await twoFamilies();
    const docs = Array.from({ length: 25 }, (_, i) => ({
      familyId: admin.family.id,
      title: `Notice ${i}`,
      body: 'Body',
      pinned: i % 10 === 0,
      authorId: i % 2 ? member.member.id : admin.member.id,
    }));
    await Notice.insertMany(docs);
    await Notice.collection.updateMany({}, { $set: { createdAt: new Date('2026-05-05T05:05:05.000Z') } });

    const p1 = assertPage(await list(member.auth, { page: 1, limit: 10 }), { page: 1, limit: 10, total: 25 });
    const p2 = assertPage(await list(member.auth, { page: '2', limit: '10' }), { page: 2, limit: 10, total: 25 });
    const p3 = assertPage(await list(member.auth, { page: 3, limit: 10 }), { page: 3, limit: 10, total: 25 });
    const p4 = assertPage(await list(member.auth, { page: 4, limit: 10 }), { page: 4, limit: 10, total: 25 });
    assert.equal(p1.length, 10);
    assert.equal(p2.length, 10);
    assert.equal(p3.length, 5);
    assert.deepEqual(p4, [], 'a page past the end is empty, not an error');
    const ids = [...p1, ...p2, ...p3].map((n) => n.id);
    assert.equal(new Set(ids).size, 25, 'no notice appears twice');
    assert.deepEqual(
      p1.slice(0, 3).map((n) => n.pinned),
      [true, true, true],
      'the 3 pinned notices lead the first page',
    );
    assert.ok([...p1.slice(3), ...p2, ...p3].every((n) => !n.pinned));

    const all = assertPage(await list(member.auth, { limit: 100 }), { page: 1, limit: 100, total: 25 });
    assert.deepEqual(all.map((n) => n.id), ids, 'pages concatenate to the full list');
  });

  it('422 VALIDATION_ERROR for invalid pagination', async () => {
    const { member } = await twoFamilies();
    assertValidation(await list(member.auth, { page: 0 }), 'page');
    assertValidation(await list(member.auth, { page: 'abc' }), 'page');
    assertValidation(await list(member.auth, { page: 1.5 }), 'page');
    assertValidation(await list(member.auth, { limit: 0 }), 'limit');
    assertValidation(await list(member.auth, { limit: 101 }), 'limit');
    assertValidation(await list(member.auth, { page: -1, limit: 1000 }), 'page', 'limit');
    assertPage(await list(member.auth, { limit: 1 }), { page: 1, limit: 1, total: 0 });
    assertPage(await list(member.auth, { limit: 100 }), { page: 1, limit: 100, total: 0 });
  });

  it("never shows another family's notices", async () => {
    const { admin, member, otherAdmin } = await twoFamilies();
    await createNotice(admin.auth, { title: 'Family A' });
    await createNotice(otherAdmin.auth, { title: 'Family B' });

    const a = assertPage(await list(member.auth), { page: 1, limit: 20, total: 1 });
    assert.deepEqual(a.map((n) => n.title), ['Family A']);
    const b = assertPage(await list(otherAdmin.auth), { page: 1, limit: 20, total: 1 });
    assert.deepEqual(b.map((n) => n.title), ['Family B']);
  });

  it('keeps notices of an author who left the family, with authorName / authorAvatarUrl null', async () => {
    const { admin, member } = await twoFamilies();
    await Member.updateOne({ _id: member.member.id }, { $set: { avatarUrl: AVATAR } });
    const notice = await createNotice(member.auth);
    await Member.deleteOne({ _id: member.member.id });

    const [listed] = assertPage(await list(admin.auth), { page: 1, limit: 20, total: 1 });
    assertNoticeShape(listed);
    assert.equal(listed.id, notice.id);
    assert.equal(listed.authorId, member.member.id);
    assert.equal(listed.authorName, null);
    assert.equal(listed.authorAvatarUrl, null);
  });
});

// ---------------------------------------------------------------- PATCH

describe('PATCH /notices/:id', () => {
  it('lets the author edit title, body and image (trimmed, updatedAt moves)', async () => {
    const { member } = await twoFamilies();
    const notice = await createNotice(member.auth);
    await new Promise((resolve) => setTimeout(resolve, 5));

    const updated = assertItem(
      await patch(member.auth, notice.id, { title: '  New title ', body: ' New body ', imageUrl: IMAGE }),
    );
    assertNoticeShape(updated);
    assert.equal(updated.id, notice.id);
    assert.equal(updated.title, 'New title');
    assert.equal(updated.body, 'New body');
    assert.equal(updated.imageUrl, IMAGE);
    assert.equal(updated.pinned, false);
    assert.equal(updated.authorId, member.member.id);
    assert.equal(updated.authorName, 'Priya Sharma');
    assert.equal(updated.createdAt, notice.createdAt);
    assert.ok(updated.updatedAt > notice.updatedAt, 'updatedAt moves forward');
  });

  it("changes only the keys sent (others untouched) and replaces / removes the image", async () => {
    const { member } = await twoFamilies();
    const notice = await createNotice(member.auth, { imageUrl: IMAGE });

    const replaced = assertItem(await patch(member.auth, notice.id, { imageUrl: IMAGE_2 }));
    assert.equal(replaced.imageUrl, IMAGE_2);
    assert.equal(replaced.title, notice.title);
    assert.equal(replaced.body, notice.body);

    assert.equal(assertItem(await patch(member.auth, notice.id, { imageUrl: null })).imageUrl, null);
    assert.equal((await rawNotice(notice.id)).imageUrl, null);

    assertItem(await patch(member.auth, notice.id, { imageUrl: IMAGE }));
    assert.equal(assertItem(await patch(member.auth, notice.id, { imageUrl: '' })).imageUrl, null, 'blank clears too');
  });

  it("lets an admin edit a member's notice", async () => {
    const { admin, member } = await twoFamilies();
    const notice = await createNotice(member.auth);
    const updated = assertItem(await patch(admin.auth, notice.id, { title: 'Edited by admin' }));
    assert.equal(updated.title, 'Edited by admin');
    assert.equal(updated.authorId, member.member.id, 'the author does not change');
  });

  it("403 FORBIDDEN (localized) when a member edits someone else's notice; nothing changes", async () => {
    const { admin, member } = await twoFamilies();
    const member2 = await joinFamilyAs(admin.family.inviteCode, { name: 'Dadi Sharma' });
    const adminsNotice = await createNotice(admin.auth, { title: 'Admin notice' });
    const peersNotice = await createNotice(member.auth, { title: 'Peer notice' });

    const error = assertError(await patch(member.auth, adminsNotice.id, { title: 'Hijacked' }), 403, 'FORBIDDEN');
    assert.equal(error.message, t('en', 'notices.errors.editNotAllowed'));
    assertError(await patch(member2.auth, peersNotice.id, { title: 'Hijacked' }), 403, 'FORBIDDEN');
    assertError(await patch(member2.auth, peersNotice.id, {}), 403, 'FORBIDDEN');
    assert.equal((await rawNotice(adminsNotice.id)).title, 'Admin notice');
    assert.equal((await rawNotice(peersNotice.id)).title, 'Peer notice');
  });

  it('lets an admin pin and unpin any notice', async () => {
    const { admin, member } = await twoFamilies();
    const notice = await createNotice(member.auth);
    assert.equal(assertItem(await patch(admin.auth, notice.id, { pinned: true })).pinned, true);
    const [first] = assertPage(await list(member.auth), { page: 1, limit: 20, total: 1 });
    assert.equal(first.pinned, true);
    assert.equal(assertItem(await patch(admin.auth, notice.id, { pinned: false })).pinned, false);
  });

  it('403 FORBIDDEN (localized) when a member changes `pinned`, even on their own notice; nothing is written', async () => {
    const { admin, member } = await twoFamilies();
    const own = await createNotice(member.auth);
    const error = assertError(await patch(member.auth, own.id, { pinned: true, title: 'Also this' }), 403, 'FORBIDDEN');
    assert.equal(error.message, t('en', 'notices.errors.pinAdminOnly'));
    const raw = await rawNotice(own.id);
    assert.equal(raw.pinned, false);
    assert.equal(raw.title, own.title, 'the whole request is rejected');

    // An author who is no longer admin cannot unpin their (admin-pinned) notice either.
    assertItem(await patch(admin.auth, own.id, { pinned: true }));
    assertError(await patch(member.auth, own.id, { pinned: false }), 403, 'FORBIDDEN');
    assert.equal((await rawNotice(own.id)).pinned, true);
  });

  it('allows a member to send the unchanged `pinned` value (the app sends full forms)', async () => {
    const { admin, member } = await twoFamilies();
    const own = await createNotice(member.auth);
    const updated = assertItem(await patch(member.auth, own.id, { pinned: false, title: 'Renamed' }));
    assert.equal(updated.title, 'Renamed');
    assert.equal(updated.pinned, false);

    assertItem(await patch(admin.auth, own.id, { pinned: true }));
    const again = assertItem(await patch(member.auth, own.id, { pinned: true, body: 'Still pinned' }));
    assert.equal(again.pinned, true);
    assert.equal(again.body, 'Still pinned');
  });

  it('an empty or unchanged PATCH returns the notice without writing (updatedAt kept)', async () => {
    const { member } = await twoFamilies();
    const notice = await createNotice(member.auth, { imageUrl: IMAGE });
    await new Promise((resolve) => setTimeout(resolve, 5));

    assert.deepEqual(assertItem(await patch(member.auth, notice.id, {})), notice);
    const same = assertItem(
      await patch(member.auth, notice.id, {
        title: ` ${notice.title} `,
        body: notice.body,
        imageUrl: IMAGE,
        pinned: false,
        authorId: UNKNOWN_ID,
      }),
    );
    assert.deepEqual(same, notice);
    assert.equal((await rawNotice(notice.id)).updatedAt.toISOString(), notice.updatedAt);
  });

  it("404 NOT_FOUND for another family's notice or an unknown id; 400 for a malformed id", async () => {
    const { admin, otherAdmin } = await twoFamilies();
    const notice = await createNotice(admin.auth, { title: 'Family A' });

    assertError(await patch(otherAdmin.auth, notice.id, { title: 'Taken over' }), 404, 'NOT_FOUND');
    assertError(await patch(otherAdmin.auth, notice.id, { pinned: true }), 404, 'NOT_FOUND');
    assertError(await patch(admin.auth, UNKNOWN_ID, { title: 'x' }), 404, 'NOT_FOUND');
    assertError(await patch(admin.auth, 'not-an-id', { title: 'x' }), 400, 'BAD_REQUEST');
    assertError(await patch(admin.auth, 'not-an-id', { title: '' }), 400, 'BAD_REQUEST');
    assert.equal((await rawNotice(notice.id)).title, 'Family A');
  });

  it('422 VALIDATION_ERROR with field details for invalid bodies; nothing changes', async () => {
    const { admin } = await twoFamilies();
    const notice = await createNotice(admin.auth);
    const cases = [
      [{ title: null }, 'title'],
      [{ title: '' }, 'title'],
      [{ title: '  ' }, 'title'],
      [{ title: 'T'.repeat(101) }, 'title'],
      [{ body: null }, 'body'],
      [{ body: 'b'.repeat(2001) }, 'body'],
      [{ imageUrl: 'https://cdn.example.com/a.jpg' }, 'imageUrl'],
      [{ pinned: 'yes' }, 'pinned'],
      [{ pinned: null }, 'pinned'],
    ];
    for (const [body, path] of cases) assertValidation(await patch(admin.auth, notice.id, body), path);
    const raw = await rawNotice(notice.id);
    assert.equal(raw.title, notice.title);
    assert.equal(raw.body, notice.body);
    assert.equal(raw.pinned, false);
  });

  it('keeps working after the author left: only admins may edit, name shows as null', async () => {
    const { admin, member } = await twoFamilies();
    const member2 = await joinFamilyAs(admin.family.inviteCode, { name: 'Dadi Sharma' });
    const notice = await createNotice(member.auth);
    await Member.deleteOne({ _id: member.member.id });

    assertError(await patch(member2.auth, notice.id, { title: 'x' }), 403, 'FORBIDDEN');
    const updated = assertItem(await patch(admin.auth, notice.id, { title: 'Kept by admin' }));
    assert.equal(updated.title, 'Kept by admin');
    assert.equal(updated.authorName, null);
  });
});

// ---------------------------------------------------------------- DELETE

describe('DELETE /notices/:id', () => {
  it('lets the author delete their notice → data null', async () => {
    const { member } = await twoFamilies();
    const notice = await createNotice(member.auth);
    const data = assertItem(await del(member.auth, notice.id));
    assert.equal(data, null);
    assert.equal(await Notice.countDocuments(), 0);
    assertPage(await list(member.auth), { page: 1, limit: 20, total: 0 });
  });

  it("lets an admin delete a member's notice", async () => {
    const { admin, member } = await twoFamilies();
    const notice = await createNotice(member.auth);
    assert.equal(assertItem(await del(admin.auth, notice.id)), null);
    assert.equal(await Notice.countDocuments(), 0);
  });

  it("403 FORBIDDEN when a member deletes someone else's notice; it stays", async () => {
    const { admin, member } = await twoFamilies();
    const notice = await createNotice(admin.auth);
    const error = assertError(await del(member.auth, notice.id), 403, 'FORBIDDEN');
    assert.equal(error.message, t('en', 'notices.errors.editNotAllowed'));
    assert.equal(await Notice.countDocuments(), 1);
  });

  it("404 NOT_FOUND for another family's notice, an unknown id or a repeat; 400 for a malformed id", async () => {
    const { admin, otherAdmin } = await twoFamilies();
    const notice = await createNotice(admin.auth);

    assertError(await del(otherAdmin.auth, notice.id), 404, 'NOT_FOUND');
    assert.equal(await Notice.countDocuments(), 1);
    assertError(await del(admin.auth, UNKNOWN_ID), 404, 'NOT_FOUND');
    assertError(await del(admin.auth, '123'), 400, 'BAD_REQUEST');

    assertItem(await del(admin.auth, notice.id));
    assertError(await del(admin.auth, notice.id), 404, 'NOT_FOUND');
  });

  it('concurrent deletes: exactly one succeeds, the others get 404', async () => {
    const { admin, member } = await twoFamilies();
    const notice = await createNotice(member.auth);
    const results = await Promise.all([
      del(admin.auth, notice.id),
      del(member.auth, notice.id),
      del(admin.auth, notice.id),
    ]);
    const statuses = results.map((r) => r.status).sort();
    assert.deepEqual(statuses, [200, 404, 404]);
    for (const res of results.filter((r) => r.status === 404)) assertError(res, 404, 'NOT_FOUND');
    assert.equal(await Notice.countDocuments(), 0);
  });

  it('PATCH after a delete → 404', async () => {
    const { member } = await twoFamilies();
    const notice = await createNotice(member.auth);
    assertItem(await del(member.auth, notice.id));
    assertError(await patch(member.auth, notice.id, { title: 'Too late' }), 404, 'NOT_FOUND');
  });
});

// ---------------------------------------------------------------- dashboard helper

describe('listLatestNotices (dashboard helper)', () => {
  it('returns at most `limit` serialized notices of the family, pinned first then newest', async () => {
    const { admin, member, otherAdmin } = await twoFamilies();
    const a = await createNotice(member.auth, { title: 'a' });
    const b = await createNotice(member.auth, { title: 'b' });
    const pinned = await createNotice(admin.auth, { title: 'pinned', pinned: true });
    const c = await createNotice(member.auth, { title: 'c' });
    await createNotice(otherAdmin.auth, { title: 'other family' });
    await setCreatedAt(a.id, '2026-01-01T00:00:00.000Z');
    await setCreatedAt(b.id, '2026-02-01T00:00:00.000Z');
    await setCreatedAt(pinned.id, '2025-01-01T00:00:00.000Z');
    await setCreatedAt(c.id, '2026-03-01T00:00:00.000Z');

    const latest = await listLatestNotices(admin.family.id);
    assert.deepEqual(latest.map((n) => n.title), ['pinned', 'c', 'b']);
    latest.forEach(assertNoticeShape);
    assert.equal(latest[1].authorName, 'Priya Sharma');

    assert.deepEqual((await listLatestNotices(admin.family.id, { limit: 1 })).map((n) => n.title), ['pinned']);
    assert.deepEqual(await listLatestNotices(null), []);
    assert.deepEqual(await listLatestNotices(admin.family.id, { limit: 0 }), []);
    assert.deepEqual(await listLatestNotices(otherAdmin.family.id, { limit: 3 }).then((l) => l.map((n) => n.title)), [
      'other family',
    ]);
  });
});

// ================================================================ hardening review (b-notices-harden)

const execFileAsync = promisify(execFile);
const LOCALES_DIR = fileURLToPath(new URL('../src/i18n/locales', import.meta.url));
const MAX_SAFE_PAGE_PLUS_TWO = '9007199254740993';

describe('hardening: text normalisation and UTF-16 limits', () => {
  it('counts title / body limits in UTF-16 code units (emoji = 2) with a clean 422, on POST and PATCH', async () => {
    const { member } = await twoFamilies();
    // 50 emoji = 100 code units: exactly the limit. zod counts code points, Mongoose code units.
    const atLimit = await createNotice(member.auth, { title: '😀'.repeat(50), body: '🎉'.repeat(1000) });
    assert.equal(atLimit.title.length, 100);
    assert.equal(atLimit.body.length, 2000);

    const tooLong = await post(member.auth, noticeBody({ title: '😀'.repeat(51), body: '🎉'.repeat(1001) }));
    const details = assertValidation(tooLong, 'title', 'body');
    assert.equal(details.title, 'Title must be at most 100 characters');
    assert.equal(details.body, 'Body must be at most 2000 characters');
    assert.ok(!JSON.stringify(tooLong.body).includes('😀'), 'the error never echoes the input (raw Mongoose message)');

    const patched = await patch(member.auth, atLimit.id, { title: `${'😀'.repeat(50)}a` });
    assert.equal(assertValidation(patched, 'title').title, 'Title must be at most 100 characters');
    assert.equal(await Notice.countDocuments(), 1);
    assert.equal((await rawNotice(atLimit.id)).title, atLimit.title);
  });

  it('rejects titles / bodies made only of invisible characters (zero-width, joiners, spaces)', async () => {
    const { member } = await twoFamilies();
    const invisible = ['​', '​‌‍', '⁠ 　', ' ‎‏ '];
    for (const text of invisible) {
      assertValidation(await post(member.auth, { title: text, body: text }), 'title', 'body');
    }
    const notice = await createNotice(member.auth);
    assertValidation(await patch(member.auth, notice.id, { title: '​' }), 'title');
    assertValidation(await patch(member.auth, notice.id, { body: '‍\t\n' }), 'body');
    assert.equal(await Notice.countDocuments(), 1);
    assert.equal(sentPushes.length, 1, 'only the valid notice was pushed');
  });

  it('title → one line without control characters; body keeps line breaks / tabs but no other controls', async () => {
    const { admin, member } = await twoFamilies();
    await Device.create({ userId: admin.user.id, token: 'token-admin', platform: 'android', locale: 'en' });
    const notice = await createNotice(member.auth, {
      title: 'Line\none\u0000\tx\r\n',
      body: 'a\r\nb\rc\u0007d\u0000\te\u001B[31m',
    });
    assert.equal(notice.title, 'Line one x');
    assert.equal(notice.body, 'a\nb\ncd\te[31m');
    const raw = await rawNotice(notice.id);
    assert.equal(raw.title, notice.title, 'the response equals what was saved');
    assert.equal(raw.body, notice.body);
    assert.equal(sentPushes[0].vars.title, 'Line one x', 'the push title is one clean line');

    const edited = assertItem(await patch(member.auth, notice.id, { title: 'New\u0085title', body: 'x\u0000\ny' }));
    assert.equal(edited.title, 'New title');
    assert.equal(edited.body, 'x\ny');
  });

  it('stores ill-formed UTF-16 (lone surrogates) as U+FFFD, so the response equals the database', async () => {
    const { member } = await twoFamilies();
    const notice = await createNotice(member.auth, { title: 'Hi \uD83D', body: '\uDE00 body' });
    assert.equal(notice.title, 'Hi �');
    assert.equal(notice.body, '� body');
    const raw = await rawNotice(notice.id);
    assert.equal(raw.title, notice.title);
    assert.equal(raw.body, notice.body);
    // Re-sending the same (ill-formed) text is recognised as "unchanged" → no write.
    assert.deepEqual(assertItem(await patch(member.auth, notice.id, { title: 'Hi \uD83D' })), notice);
  });

  it('keeps RTL text, bidi marks, combining marks and ZWJ emoji exactly as typed', async () => {
    const { member } = await twoFamilies();
    const title = '‏اجتماع العائلة 👨‍👩‍👧';
    const body = 'क्षत्रिय परिवार\nשלום עליכם‎ (10:00)';
    const notice = await createNotice(member.auth, { title, body });
    assert.equal(notice.title, title);
    assert.equal(notice.body, body);
  });
});

describe('hardening: imageUrl', () => {
  it('rejects Cloudinary look-alikes with user info or a non-default port', async () => {
    const { member } = await twoFamilies();
    const bad = [
      'https://evil.example@res.cloudinary.com/demo/image/upload/a.jpg',
      'https://user:pass@res.cloudinary.com/demo/image/upload/a.jpg',
      'https://res.cloudinary.com:8443/demo/image/upload/a.jpg',
      'javascript://res.cloudinary.com/%0aalert(1)',
      'data:image/png;base64,iVBORw0KGgo=',
      'https://res.cloudinary.com.evil.example/a.jpg',
      'https://res-cloudinary.com/a.jpg',
    ];
    for (const imageUrl of bad) {
      assertValidation(await post(member.auth, noticeBody({ imageUrl })), 'imageUrl');
    }
    const notice = await createNotice(member.auth);
    for (const imageUrl of bad) assertValidation(await patch(member.auth, notice.id, { imageUrl }), 'imageUrl');
    assert.equal(await Notice.countDocuments(), 1);
    assert.equal((await rawNotice(notice.id)).imageUrl, null);
  });

  it('stores the canonical URL form (no parser can see a different host later)', async () => {
    const { member } = await twoFamilies();
    const cases = [
      ['HTTPS://RES.CLOUDINARY.COM/demo/image/upload/a.jpg', 'https://res.cloudinary.com/demo/image/upload/a.jpg'],
      ['https://res.cloudinary.com:443/demo/image/upload/a.jpg', 'https://res.cloudinary.com/demo/image/upload/a.jpg'],
      ['https://res.cloudinary.com\\@evil.example/a.jpg', 'https://res.cloudinary.com/@evil.example/a.jpg'],
      ['https://res.cloudinary.com/demo/image/upload/my photo.jpg', 'https://res.cloudinary.com/demo/image/upload/my%20photo.jpg'],
      [IMAGE, IMAGE],
    ];
    for (const [input, stored] of cases) {
      const notice = await createNotice(member.auth, { imageUrl: input });
      assert.equal(notice.imageUrl, stored, input);
      assert.equal((await rawNotice(notice.id)).imageUrl, stored);
      assert.equal(new URL(notice.imageUrl).hostname, 'res.cloudinary.com');
    }
    const [first] = await Notice.find().sort({ createdAt: 1, _id: 1 }).lean();
    const patched = assertItem(await patch(member.auth, first._id.toString(), { imageUrl: 'HTTPS://res.cloudinary.com/demo/image/upload/b.jpg' }));
    assert.equal(patched.imageUrl, 'https://res.cloudinary.com/demo/image/upload/b.jpg');
  });

  it('checks the 1024-character limit after canonicalisation (percent-encoding can grow a URL)', async () => {
    const { member } = await twoFamilies();
    const imageUrl = `https://res.cloudinary.com/demo/image/upload/${' '.repeat(400)}a.jpg`;
    assert.ok(imageUrl.length < 1024 && new URL(imageUrl).href.length > 1024);
    const details = assertValidation(await post(member.auth, noticeBody({ imageUrl })), 'imageUrl');
    assert.equal(details.imageUrl, 'Image URL must be at most 1024 characters');
    assert.equal(await Notice.countDocuments(), 0);
  });
});

describe('hardening: injection and mass assignment', () => {
  it('422 for operator objects / arrays in body fields (POST and PATCH), nothing written', async () => {
    const { admin, member } = await twoFamilies();
    const injections = [
      { title: { $ne: null }, body: { $gt: '' } },
      { title: ['a'], body: 'x', imageUrl: { $regex: '.*' } },
      { title: 'x', body: 'y', pinned: { $ne: false } },
    ];
    for (const input of injections) {
      const res = await post(member.auth, input);
      assertError(res, 422, 'VALIDATION_ERROR');
    }
    const notice = await createNotice(member.auth);
    for (const input of injections) assertError(await patch(admin.auth, notice.id, input), 422, 'VALIDATION_ERROR');
    assert.equal(await Notice.countDocuments(), 1);
    const raw = await rawNotice(notice.id);
    assert.equal(raw.title, notice.title);
    assert.equal(raw.pinned, false);
  });

  it('PATCH ignores update operators and read-only keys (familyId, authorId, _id, timestamps, pinned via $set)', async () => {
    const { admin, member, otherAdmin } = await twoFamilies();
    const notice = await createNotice(member.auth);
    const forged = {
      $set: { pinned: true, familyId: otherAdmin.family.id, authorId: admin.member.id, title: 'Owned' },
      $unset: { title: 1, body: 1 },
      $rename: { title: 'x' },
      familyId: otherAdmin.family.id,
      authorId: admin.member.id,
      _id: UNKNOWN_ID,
      id: UNKNOWN_ID,
      createdAt: '2000-01-01T00:00:00.000Z',
      updatedAt: '2000-01-01T00:00:00.000Z',
      __v: 99,
    };
    assert.deepEqual(assertItem(await patch(member.auth, notice.id, forged)), notice, 'nothing changes (no-op)');
    const raw = await rawNotice(notice.id);
    assert.equal(String(raw.familyId), member.family.id);
    assert.equal(String(raw.authorId), member.member.id);
    assert.equal(raw.pinned, false);
    assert.equal(raw.title, notice.title);
    assert.equal(raw.createdAt.toISOString(), notice.createdAt);
    assert.equal(await Notice.countDocuments({ _id: new mongoose.Types.ObjectId(UNKNOWN_ID) }), 0);
    assertPage(await list(otherAdmin.auth), { page: 1, limit: 20, total: 0 });

    // The forged keys next to a real change: only the real change is applied.
    const renamed = assertItem(await patch(member.auth, notice.id, { ...forged, title: 'Renamed' }));
    assert.equal(renamed.title, 'Renamed');
    assert.equal(renamed.authorId, member.member.id);
    assert.equal(String((await rawNotice(notice.id)).familyId), member.family.id);
  });

  it('POST ignores update operators at the top level', async () => {
    const { member, otherAdmin } = await twoFamilies();
    const notice = await createNotice(member.auth, { $set: { pinned: true, familyId: otherAdmin.family.id }, $where: '1' });
    assert.equal(notice.pinned, false);
    assert.equal(String((await rawNotice(notice.id)).familyId), member.family.id);
  });

  it('GET: operator / bracket / foreign keys in the query never widen the family scope', async () => {
    const { admin, member, otherAdmin } = await twoFamilies();
    await createNotice(admin.auth, { title: 'Family A' });
    await createNotice(otherAdmin.auth, { title: 'Family B' });
    const res = await request
      .get(`${url()}?page[$gt]=0&limit[$ne]=1&familyId=${otherAdmin.family.id}&familyId[$ne]=x&authorId[$exists]=true&$where=1`)
      .set(member.auth);
    // Express 5's default "simple" query parser keeps `page[$gt]` as a literal (unknown) key.
    if (res.status === 200) {
      const data = assertPage(res, { page: 1, limit: 20, total: 1 });
      assert.deepEqual(data.map((n) => n.title), ['Family A']);
    } else {
      assertError(res, 422, 'VALIDATION_ERROR');
    }
  });

  it('pagination extremes: huge pages are empty (no 500), unsafe integers / repeats / blanks are 422', async () => {
    const { member } = await twoFamilies();
    await createNotice(member.auth);
    for (const page of ['1e15', String(Number.MAX_SAFE_INTEGER)]) {
      const data = assertPage(await list(member.auth, { page }), { page: Number(page), limit: 20, total: 1 });
      assert.deepEqual(data, []);
    }
    assertValidation(await list(member.auth, { page: MAX_SAFE_PAGE_PLUS_TWO }), 'page');
    assertValidation(await list(member.auth, { page: 'Infinity' }), 'page');
    assertValidation(await list(member.auth, { limit: 'NaN' }), 'limit');
    assertValidation(await list(member.auth, { limit: '-0' }), 'limit');
    assertValidation(await request.get(`${url()}?page=1&page=2`).set(member.auth), 'page');
    assertValidation(await request.get(`${url()}?limit=`).set(member.auth), 'limit');
    assertPage(await list(member.auth, { page: ' 1 ', limit: '1e1' }), { page: 1, limit: 10, total: 1 });
  });

  it('413 PAYLOAD_TOO_LARGE for oversized bodies; nothing is written or pushed', async () => {
    const { member } = await twoFamilies();
    const notice = await createNotice(member.auth);
    sentPushes.length = 0;
    assertError(await post(member.auth, noticeBody({ body: 'b'.repeat(150_000) })), 413, 'PAYLOAD_TOO_LARGE');
    assertError(await patch(member.auth, notice.id, { body: 'b'.repeat(150_000) }), 413, 'PAYLOAD_TOO_LARGE');
    assert.equal(await Notice.countDocuments(), 1);
    assert.equal((await rawNotice(notice.id)).body, notice.body);
    assert.equal(sentPushes.length, 0);
  });
});

describe('hardening: members who left or moved', () => {
  it('403 NO_FAMILY once the member row is gone, even with a still-valid token pointing at the family', async () => {
    const { admin, member } = await twoFamilies();
    const own = await createNotice(member.auth, { title: 'Mine' });
    await Member.deleteOne({ _id: member.member.id }); // user.familyId / memberId still set
    for (const [method, path] of [['get', url()], ['post', url()], ['patch', url(own.id)], ['delete', url(own.id)]]) {
      assertError(await request[method](path).set(member.auth).send({ title: 'x', body: 'y' }), 403, 'NO_FAMILY');
    }
    assert.equal(await Notice.countDocuments(), 1);
    assert.equal((await rawNotice(own.id)).title, 'Mine');
    assert.equal(assertPage(await list(admin.auth), { page: 1, limit: 20, total: 1 })[0].authorName, null);
  });

  it('an author who moved to another family cannot reach their old notices by id (404) nor see them', async () => {
    const { admin, member, otherAdmin } = await twoFamilies();
    const old = await createNotice(member.auth, { title: 'Old family notice' });
    // Move Priya to family B (what leave + join does): new member row, user re-linked.
    await Member.deleteOne({ _id: member.member.id });
    const moved = await Member.create({ familyId: otherAdmin.family.id, userId: member.user.id, name: 'Priya Sharma', role: 'admin' });
    await User.updateOne({ _id: member.user.id }, { $set: { familyId: otherAdmin.family.id, memberId: moved._id } });

    assertError(await patch(member.auth, old.id, { title: 'Still mine?' }), 404, 'NOT_FOUND');
    assertError(await patch(member.auth, old.id, { pinned: true }), 404, 'NOT_FOUND');
    assertError(await del(member.auth, old.id), 404, 'NOT_FOUND');
    assertPage(await list(member.auth), { page: 1, limit: 20, total: 0 });
    const raw = await rawNotice(old.id);
    assert.equal(raw.title, 'Old family notice');
    assert.equal(raw.pinned, false);
    assert.equal(String(raw.familyId), admin.family.id);

    // Family A's new notices no longer reach the moved user.
    await Device.create({ userId: member.user.id, token: 'token-moved', platform: 'ios', locale: 'en' });
    sentPushes.length = 0;
    await createNotice(admin.auth, { title: 'After the move' });
    await flushPushes();
    assert.ok(!sentPushes[0]?.messages?.some((m) => m.token === 'token-moved'));
  });
});

describe('hardening: concurrency', () => {
  it('PATCH racing DELETE: the delete wins once, every PATCH is 200 or 404, the notice never comes back', async () => {
    const { admin, member } = await twoFamilies();
    for (let round = 0; round < 5; round += 1) {
      const notice = await createNotice(member.auth, { title: `Round ${round}` });
      const results = await Promise.all([
        patch(member.auth, notice.id, { title: 'Edited' }),
        del(admin.auth, notice.id),
        patch(admin.auth, notice.id, { pinned: true }),
        patch(member.auth, notice.id, { body: 'Edited body', imageUrl: IMAGE }),
      ]);
      assert.equal(results[1].status, 200, JSON.stringify(results[1].body));
      for (const res of [results[0], results[2], results[3]]) {
        if (res.status === 404) assertError(res, 404, 'NOT_FOUND');
        else assertItem(res);
      }
      assert.equal(await Notice.countDocuments({ _id: new mongoose.Types.ObjectId(notice.id) }), 0, 'no upsert');
    }
  });

  it('concurrent PATCHes of different fields never overwrite each other (only changed keys are written)', async () => {
    const { admin, member } = await twoFamilies();
    const notice = await createNotice(member.auth);
    // (No `pinned` from the member here: if the admin's pin lands first, a member's `pinned: false`
    // is a real change and correctly 403s — covered deterministically in the PATCH section.)
    const results = await Promise.all([
      patch(member.auth, notice.id, { title: 'New title' }),
      patch(admin.auth, notice.id, { pinned: true }),
      patch(admin.auth, notice.id, { body: 'New body' }),
      patch(member.auth, notice.id, { imageUrl: IMAGE }),
    ]);
    results.forEach((res) => assertItem(res));
    const raw = await rawNotice(notice.id);
    assert.equal(raw.title, 'New title');
    assert.equal(raw.body, 'New body');
    assert.equal(raw.imageUrl, IMAGE);
    assert.equal(raw.pinned, true, 'no concurrent PATCH rewrote a field it did not change');
  });
});

describe('hardening: push language and audience', () => {
  it('localizes per recipient (device locale → account locale → English), never by the author request', async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'fh-notices-i18n-'));
    try {
      await fs.cp(LOCALES_DIR, tmp, { recursive: true });
      for (const [lang, title] of [
        ['hi', '{name} की नई सूचना'],
        ['ar', 'إشعار جديد من {name}'],
      ]) {
        await fs.mkdir(path.join(tmp, lang), { recursive: true });
        const catalog = { push: { new: { title, titlePinned: title, body: '«{title}»' } } };
        await fs.writeFile(path.join(tmp, lang, 'notices.json'), JSON.stringify(catalog));
      }
      loadTranslations(tmp);

      const { admin, member } = await twoFamilies();
      const hindi = await joinFamilyAs(admin.family.inviteCode, { name: 'Dadi', locale: 'en' });
      const arabic = await joinFamilyAs(admin.family.inviteCode, { name: 'Layla', locale: 'ar' });
      await Device.create([
        { userId: admin.user.id, token: 'token-admin', platform: 'android', locale: 'en' },
        { userId: hindi.user.id, token: 'token-hi', platform: 'android', locale: 'hi' },
        { userId: arabic.user.id, token: 'token-ar', platform: 'ios', locale: null },
        { userId: member.user.id, token: 'token-author', platform: 'ios', locale: 'hi' },
      ]);
      await flushPushes();
      sentPushes.length = 0;

      // The author's own request language plays no role for the recipients.
      const res = await request.post(url()).set(member.auth).set('Accept-Language', 'hi').send({ title: 'Picnic', body: 'Private details' });
      assertItem(res, 201);
      await flushPushes();
      const byToken = Object.fromEntries(sentPushes[0].messages.map((m) => [m.token, m]));
      assert.deepEqual(Object.keys(byToken).sort(), ['token-admin', 'token-ar', 'token-hi'], 'author excluded');
      assert.equal(byToken['token-admin'].title, 'New notice from Priya Sharma');
      assert.equal(byToken['token-hi'].title, 'Priya Sharma की नई सूचना');
      assert.equal(byToken['token-ar'].locale, 'ar', 'no device locale → account locale');
      assert.equal(byToken['token-ar'].title, 'إشعار جديد من Priya Sharma');
      assert.equal(byToken['token-ar'].body, '«Picnic»');
      for (const message of Object.values(byToken)) assert.ok(!message.body.includes('Private details'));
    } finally {
      await flushPushes();
      loadTranslations();
      await fs.rm(tmp, { recursive: true, force: true });
    }
    // The real catalogs are back.
    assert.notEqual(t('hi', 'notices.push.new.title', { name: 'x' }), 'x की नई सूचना');
    assert.equal(t('en', 'notices.push.new.title', { name: 'x' }), 'New notice from x');
  });

  it('a notice by an author with an Accept-Language header still reaches English recipients in English', async () => {
    const { admin, member } = await twoFamilies();
    await Device.create({ userId: admin.user.id, token: 'token-admin', platform: 'android', locale: 'en' });
    sentPushes.length = 0;
    assertItem(await request.post(url()).set(member.auth).set('Accept-Language', 'ar').send(noticeBody()), 201);
    await flushPushes();
    assert.equal(sentPushes[0].messages[0].title, 'New notice from Priya Sharma');
  });
});

describe('hardening: per-account posting rate limit (child process with limiters on)', () => {
  const MARKER = '__FH_NOTICES_CHILD_RESULT__';
  const CHILD_SCRIPT = `
import http from 'node:http';
const { connectDb, disconnectDb } = await import(process.env.FH_DB_MODULE);
const { createApp } = await import(process.env.FH_APP_MODULE);
const { sentPushes, flushPushes } = await import(process.env.FH_PUSH_MODULE);
await connectDb(process.env.MONGODB_URI);
const server = http.createServer(createApp());
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const base = 'http://127.0.0.1:' + server.address().port;
const results = [];
for (const r of JSON.parse(process.env.FH_REQUESTS)) {
  const res = await fetch(base + r.path, { method: r.method, headers: r.headers, body: r.body });
  results.push({ status: res.status, headers: Object.fromEntries(res.headers), text: await res.text() });
}
await flushPushes();
process.stdout.write('\\n' + process.env.FH_MARKER + JSON.stringify({ results, pushes: sentPushes.length }) + '\\n');
server.closeAllConnections();
server.close();
await disconnectDb();
process.exit(0);
`;

  function mongoUri() {
    const { host, port, name } = mongoose.connection;
    return `mongodb://${host}:${port}/${name}`;
  }

  const req = (account, method, body) => ({
    method,
    path: url(),
    headers: { 'Content-Type': 'application/json', 'Accept-Language': 'en', ...authHeader(account.tokens) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  async function runInChild(requests) {
    const cwd = await fs.mkdtemp(path.join(os.tmpdir(), 'fh-notices-'));
    const childEnv = {
      PATH: process.env.PATH,
      HOME: process.env.HOME,
      TMPDIR: process.env.TMPDIR,
      SystemRoot: process.env.SystemRoot,
      NODE_ENV: 'test',
      RATE_LIMIT_IN_TEST: 'true',
      LOG_LEVEL: 'silent',
      MONGODB_URI: mongoUri(),
      JWT_ACCESS_SECRET: env.JWT_ACCESS_SECRET,
      FH_DB_MODULE: new URL('../src/config/db.js', import.meta.url).href,
      FH_APP_MODULE: new URL('../src/app.js', import.meta.url).href,
      FH_PUSH_MODULE: new URL('../src/services/push.js', import.meta.url).href,
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
      const { results, pushes } = JSON.parse(line.slice(MARKER.length));
      return { pushes, results: results.map((r) => ({ ...r, body: JSON.parse(r.text) })) };
    } finally {
      await fs.rm(cwd, { recursive: true, force: true });
    }
  }

  it(`${NOTICE_POST_RATE_LIMIT_PER_MINUTE} posts / minute / account, then 429 (also for invalid bodies); others unaffected`, async () => {
    assert.equal(NOTICE_POST_RATE_LIMIT_PER_MINUTE, 10);
    const { admin, member } = await twoFamilies();
    const burst = Array.from({ length: NOTICE_POST_RATE_LIMIT_PER_MINUTE }, (_, i) =>
      req(member, 'POST', noticeBody({ title: `Spam ${i}` })),
    );
    const { results, pushes } = await runInChild([
      ...burst,
      req(member, 'POST', noticeBody({ title: 'One too many' })),
      req(member, 'POST', { title: '' }),
      req(member, 'GET'),
      req(admin, 'POST', noticeBody({ title: 'Admin still posts' })),
    ]);
    results.slice(0, NOTICE_POST_RATE_LIMIT_PER_MINUTE).forEach((res) => assert.equal(res.status, 201, res.text));
    for (const limited of results.slice(NOTICE_POST_RATE_LIMIT_PER_MINUTE, NOTICE_POST_RATE_LIMIT_PER_MINUTE + 2)) {
      assert.equal(limited.status, 429, limited.text);
      assert.equal(limited.body.success, false);
      assert.equal(limited.body.error.code, 'TOO_MANY_REQUESTS');
      const seconds = limited.body.error.details?.retryAfterSeconds;
      assert.ok(Number.isInteger(seconds) && seconds >= 1 && seconds <= 60, `retryAfterSeconds=${seconds}`);
      assert.equal(limited.headers['retry-after'], String(seconds));
    }
    assert.equal(results.at(-2).status, 200, 'reading the board is not limited');
    assert.equal(results.at(-1).status, 201, 'keyed by account, not by the shared home IP');

    assert.equal(await Notice.countDocuments(), NOTICE_POST_RATE_LIMIT_PER_MINUTE + 1);
    assert.equal(await Notice.countDocuments({ title: 'One too many' }), 0);
    assert.equal(pushes, NOTICE_POST_RATE_LIMIT_PER_MINUTE + 1, 'no push for a refused post');
  });
});

describe('hardening: listLatestNotices bounds', () => {
  it('returns [] for a malformed family id (no CastError) and caps the limit at 100', async () => {
    const { admin } = await twoFamilies();
    assert.deepEqual(await listLatestNotices('not-an-id'), []);
    assert.deepEqual(await listLatestNotices({ $ne: null }), []);
    assert.deepEqual(await listLatestNotices(admin.family.id, { limit: 'abc' }), []);
    assert.deepEqual(await listLatestNotices(admin.family.id, { limit: -5 }), []);
    await Notice.insertMany(
      Array.from({ length: 105 }, (_, i) => ({ familyId: admin.family.id, title: `N${i}`, body: 'b', authorId: admin.member.id })),
    );
    assert.equal((await listLatestNotices(admin.family.id, { limit: 1000 })).length, 100);
    assert.equal((await listLatestNotices(new mongoose.Types.ObjectId(admin.family.id), { limit: 2.9 })).length, 2);
  });
});
