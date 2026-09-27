/**
 * SOS module: docs/03-API_CONTRACT.md §10 (`/sos/*`), push payloads of §13.
 *
 * Covers: auth / NO_FAMILY on every route; POST /sos (201 vs idempotent 200, 15 min window, location
 * dropped for `never`, message rules, concurrent creates, pushes and recipients); GET /sos/active,
 * /sos/history (pagination, order, lazy expiry persisted), GET /sos/:id (trail oldest first, cap);
 * POST /sos/:id/location (owner only, 3 s throttle, `$slice` cap, 409 / 403 rules, mode switches,
 * concurrent updates); POST /sos/:id/resolve (owner or admin, idempotent, 409 on expired, pushes,
 * concurrent resolves); the permission matrix (admin / member / other family → 404); validation
 * (422 `details`, 400 on malformed ids); envelope shape, `no-store`, i18n keys and exported helpers.
 *
 * Time-dependent states (expiry, throttle window) are produced by moving `expiresAt` /
 * `lastLocationAt` in the database — no sleeping.
 */
import {
  API,
  flushPushes,
  joinFamilyAs,
  registerFamilyAdmin,
  resetDb,
  sentPushes,
  setupTestApp,
  teardownTestApp,
} from './helpers.js';
import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

const { SosAlert, Member } = await import('../src/models/index.js');
const { SOS_DURATION_MS, SOS_MIN_LOCATION_INTERVAL_MS, SOS_TRAIL_MAX, SOS_RESOLUTIONS } = await import(
  '../src/lib/constants.js'
);
const { t, hasTranslation } = await import('../src/lib/i18n.js');
const { getMemberMap } = await import('../src/services/memberDirectory.js');
const { serializeSosAlert, sosStatusOf, isSosActive } = await import('../src/modules/sos/sos.serializer.js');
const sosService = await import('../src/modules/sos/sos.service.js');
const { cleanSosMessage, createSosBody } = await import('../src/modules/sos/sos.schemas.js');

let request;

before(async () => {
  ({ request } = await setupTestApp());
});
beforeEach(resetDb);
after(teardownTestApp);

// ---------------------------------------------------------------- helpers

const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const CLOUD_URL = 'https://res.cloudinary.com/demo/image/upload/v1/familyhub/priya.jpg';
const MISSING_ID = '0123456789abcdef01234567';
const SOS_KEYS = [
  'id',
  'memberId',
  'memberName',
  'memberPhone',
  'memberAvatarUrl',
  'status',
  'message',
  'locationShared',
  'lastLocation',
  'trail',
  'startedAt',
  'expiresAt',
  'resolvedAt',
  'resolvedById',
  'resolution',
].sort();

function assertNoStore(res) {
  assert.match(String(res.headers['cache-control'] ?? ''), /no-store/);
}

function assertOk(res, status = 200) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.equal(res.body.success, true);
  assert.ok('data' in res.body);
  assert.ok(!('meta' in res.body), 'meta only on paginated lists');
  assert.ok(!('error' in res.body));
  assertNoStore(res);
  return res.body.data;
}

function assertPaged(res) {
  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.equal(res.body.success, true);
  assert.ok(Array.isArray(res.body.data));
  const { meta } = res.body;
  assert.deepEqual(Object.keys(meta).sort(), ['hasMore', 'limit', 'page', 'total']);
  assertNoStore(res);
  return { items: res.body.data, meta };
}

function assertError(res, status, code) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.equal(res.body.success, false);
  assert.equal(res.body.error.code, code);
  assert.equal(typeof res.body.error.message, 'string');
  assert.ok(res.body.error.message.length > 0);
  assert.ok(!('stack' in res.body.error));
  assert.ok(!('data' in res.body));
  return res.body.error;
}

function assertValidation(res, ...fields) {
  const error = assertError(res, 422, 'VALIDATION_ERROR');
  for (const field of fields) {
    assert.ok(error.details && typeof error.details[field] === 'string', `details.${field} in ${JSON.stringify(error.details)}`);
  }
  return error;
}

function assertLocation(loc, { lat, lng, accuracy = null }) {
  assert.ok(loc, 'location expected');
  assert.deepEqual(Object.keys(loc).sort(), ['accuracy', 'lat', 'lng', 'recordedAt']);
  assert.equal(loc.lat, lat);
  assert.equal(loc.lng, lng);
  assert.equal(loc.accuracy, accuracy);
  assert.match(loc.recordedAt, ISO);
}

/** Exact contract `SosAlert` shape. */
function assertSosShape(alert) {
  assert.deepEqual(Object.keys(alert).sort(), SOS_KEYS);
  assert.match(alert.id, /^[a-f0-9]{24}$/);
  assert.match(alert.memberId, /^[a-f0-9]{24}$/);
  assert.ok(['active', 'resolved', 'expired'].includes(alert.status));
  assert.equal(typeof alert.locationShared, 'boolean');
  assert.ok(Array.isArray(alert.trail));
  assert.match(alert.startedAt, ISO);
  assert.match(alert.expiresAt, ISO);
  assert.equal(Date.parse(alert.expiresAt) - Date.parse(alert.startedAt), SOS_DURATION_MS);
  if (alert.resolvedAt !== null) assert.match(alert.resolvedAt, ISO);
  assert.ok(!('_id' in alert) && !('__v' in alert) && !('familyId' in alert) && !('lastLocationAt' in alert));
  return alert;
}

// Requests
const raise = (user, body) => {
  const req = request.post(`${API}/sos`).set(user.auth);
  return body === undefined ? req.send() : req.send(body);
};
const getActive = (user) => request.get(`${API}/sos/active`).set(user.auth);
const getHistory = (user, query = '') => request.get(`${API}/sos/history${query}`).set(user.auth);
const getAlert = (user, id) => request.get(`${API}/sos/${id}`).set(user.auth);
const sendLocation = (user, id, body) => request.post(`${API}/sos/${id}/location`).set(user.auth).send(body);
const resolve = (user, id, body = { resolution: 'safe' }) => request.post(`${API}/sos/${id}/resolve`).set(user.auth).send(body);

async function setSharing(user, mode) {
  const res = await request.patch(`${API}/me`).set(user.auth).send({ locationSharing: mode });
  assert.equal(res.status, 200, JSON.stringify(res.body));
}

async function addDevice(user, token, locale) {
  const res = await request
    .post(`${API}/me/devices`)
    .set(user.auth)
    .send({ token, platform: 'android', ...(locale ? { locale } : {}) });
  assert.equal(res.status, 200, JSON.stringify(res.body));
}

async function raiseOk(user, body, status = 201) {
  return assertSosShape(assertOk(await raise(user, body), status));
}

/** Moves the alert past its window (the DB still says `active` until the next read). */
async function makeStale(id) {
  await SosAlert.updateOne(
    { _id: id },
    { $set: { startedAt: new Date(Date.now() - SOS_DURATION_MS - 60_000), expiresAt: new Date(Date.now() - 60_000) } },
  );
}

/** Moves the last stored point out of the throttle window. */
async function openThrottle(id) {
  await SosAlert.updateOne({ _id: id }, { $set: { lastLocationAt: new Date(Date.now() - SOS_MIN_LOCATION_INTERVAL_MS - 500) } });
}

const rawAlert = (id) => SosAlert.findById(id).lean();

async function clearPushes() {
  await flushPushes();
  sentPushes.length = 0;
}

const pushesOf = (type) => sentPushes.filter((p) => p.type === type);

/**
 * Managed profile (no account). Written through the model: `POST /family/members` belongs to the
 * family module, which is built in parallel (`addManagedMember` works once it lands).
 */
async function addChildProfile(admin) {
  const doc = await Member.create({
    familyId: admin.family.id,
    name: 'Anaya',
    dateOfBirth: new Date('2016-08-01T00:00:00.000Z'),
    role: 'member',
    guardianConsent: true,
    guardianConsentAt: new Date(),
    guardianConsentById: admin.member.id,
  });
  return { id: String(doc._id) };
}

/**
 * Family A: admin Amit, members Priya and Ravi, managed child Anaya. Family B: admin Olga + member Otto.
 * Push log cleared (joins send `member_joined`).
 */
async function setupFamilies({ other = true } = {}) {
  const admin = await registerFamilyAdmin({ name: 'Amit' });
  const priya = await joinFamilyAs(admin.family.inviteCode, { name: 'Priya' });
  const ravi = await joinFamilyAs(admin.family.inviteCode, { name: 'Ravi' });
  const child = await addChildProfile(admin);
  const result = { admin, priya, ravi, child };
  if (other) {
    result.olga = await registerFamilyAdmin({ name: 'Olga', family: { name: 'Other Family' } });
    result.otto = await joinFamilyAs(result.olga.family.inviteCode, { name: 'Otto' });
  }
  await clearPushes();
  return result;
}

// ---------------------------------------------------------------- auth & family guard

describe('SOS · authentication and family guard', () => {
  const routes = (id) => [
    ['post', '/sos'],
    ['get', '/sos/active'],
    ['get', '/sos/history'],
    ['get', `/sos/${id}`],
    ['post', `/sos/${id}/location`],
    ['post', `/sos/${id}/resolve`],
  ];

  it('401 UNAUTHORIZED on every route without or with a bad token', async () => {
    for (const [method, path] of routes(MISSING_ID)) {
      assertError(await request[method](`${API}${path}`).send({}), 401, 'UNAUTHORIZED');
      assertError(
        await request[method](`${API}${path}`).set({ Authorization: 'Bearer not-a-jwt' }).send({}),
        401,
        'UNAUTHORIZED',
      );
    }
  });

  it('403 NO_FAMILY on every route for a signed-in user without a family', async () => {
    const admin = await registerFamilyAdmin();
    const leaver = await joinFamilyAs(admin.family.inviteCode);
    const alert = await raiseOk(leaver, {});
    const left = await request.post(`${API}/me/leave-family`).set(leaver.auth).send();
    assert.equal(left.status, 200, JSON.stringify(left.body));
    for (const [method, path] of routes(alert.id)) {
      assertError(await request[method](`${API}${path}`).set(leaver.auth).send({ resolution: 'safe', lat: 1, lng: 1 }), 403, 'NO_FAMILY');
    }
  });
});

// ---------------------------------------------------------------- POST /sos

describe('POST /sos', () => {
  it('creates an alert (201) with the contract shape and a 15 minute window', async () => {
    const { priya } = await setupFamilies({ other: false });
    const before = Date.now();
    const alert = await raiseOk(priya, { message: '  Car broke down on NH48  ' });

    assert.equal(alert.memberId, priya.member.id);
    assert.equal(alert.memberName, 'Priya');
    assert.equal(alert.memberPhone, null);
    assert.equal(alert.memberAvatarUrl, null);
    assert.equal(alert.status, 'active');
    assert.equal(alert.message, 'Car broke down on NH48');
    assert.equal(alert.resolvedAt, null);
    assert.equal(alert.resolvedById, null);
    assert.equal(alert.resolution, null);
    assert.deepEqual(alert.trail, []);
    const started = Date.parse(alert.startedAt);
    assert.ok(started >= before - 1000 && started <= Date.now() + 1000);
    assert.equal(Date.parse(alert.expiresAt), started + SOS_DURATION_MS);

    const raw = await rawAlert(alert.id);
    assert.equal(String(raw.familyId), priya.family.id);
    assert.equal(raw.status, 'active');
  });

  it('drops the location when the sender shares `never` (the default)', async () => {
    const { priya } = await setupFamilies({ other: false });
    const alert = await raiseOk(priya, { location: { lat: 28.61, lng: 77.2, accuracy: 9 } });
    assert.equal(alert.locationShared, false);
    assert.equal(alert.lastLocation, null);

    const raw = await rawAlert(alert.id);
    assert.equal(raw.locationShared, false);
    assert.equal(raw.lastLocation, null);
    assert.deepEqual(raw.trail, []);
    assert.equal(raw.lastLocationAt, null);
  });

  it('stores the first fix for `sos_only` and `always` (lastLocation + first trail point)', async () => {
    const { priya, ravi } = await setupFamilies({ other: false });
    await setSharing(priya, 'sos_only');
    await setSharing(ravi, 'always');

    const a = await raiseOk(priya, { location: { lat: 28.61, lng: 77.2, accuracy: 12.5 } });
    assert.equal(a.locationShared, true);
    assertLocation(a.lastLocation, { lat: 28.61, lng: 77.2, accuracy: 12.5 });
    assert.equal(a.lastLocation.recordedAt, a.startedAt, 'server time of the request');
    assert.deepEqual(a.trail, [], 'POST response never carries the trail');
    const raw = await rawAlert(a.id);
    assert.equal(raw.trail.length, 1);
    assert.equal(raw.lastLocationAt.toISOString(), a.startedAt);

    const b = await raiseOk(ravi, { location: { lat: -33.86, lng: 151.2 } });
    assert.equal(b.locationShared, true);
    assertLocation(b.lastLocation, { lat: -33.86, lng: 151.2, accuracy: null });
  });

  it('shares later updates when sharing is on but the first request had no fix', async () => {
    const { priya } = await setupFamilies({ other: false });
    await setSharing(priya, 'sos_only');
    const alert = await raiseOk(priya, { location: null, message: '   ' });
    assert.equal(alert.locationShared, true);
    assert.equal(alert.lastLocation, null);
    assert.equal(alert.message, null, 'blank message → null');
    const raw = await rawAlert(alert.id);
    assert.equal(raw.lastLocationAt, null);
    assert.deepEqual(raw.trail, []);
  });

  it('accepts a request without any body (one-tap SOS)', async () => {
    const { priya } = await setupFamilies({ other: false });
    const alert = await raiseOk(priya, undefined);
    assert.equal(alert.message, null);
    assert.equal(alert.lastLocation, null);
  });

  it('strips unknown keys instead of failing an SOS', async () => {
    const { priya, ravi } = await setupFamilies({ other: false });
    const alert = await raiseOk(priya, {
      message: 'help',
      status: 'resolved',
      memberId: ravi.member.id,
      expiresAt: '2099-01-01T00:00:00.000Z',
      appVersion: '9.9.9',
    });
    assert.equal(alert.status, 'active');
    assert.equal(alert.memberId, priya.member.id);
    assert.equal(Date.parse(alert.expiresAt) - Date.parse(alert.startedAt), SOS_DURATION_MS);
  });

  it('is idempotent: a second POST returns the active alert unchanged (200) and sends no second push', async () => {
    const { priya } = await setupFamilies({ other: false });
    await setSharing(priya, 'sos_only');
    const first = await raiseOk(priya, { message: 'first', location: { lat: 1, lng: 2 } });
    const again = await raiseOk(priya, { message: 'second', location: { lat: 3, lng: 4 } }, 200);
    assert.deepEqual(again, first);
    assert.equal(await SosAlert.countDocuments({ memberId: priya.member.id }), 1);
    await flushPushes();
    assert.equal(pushesOf('sos').length, 1);
    const raw = await rawAlert(first.id);
    assert.equal(raw.trail.length, 1);
    assert.equal(raw.message, 'first');
  });

  it('starts a new alert once the previous one expired (and persists `expired`)', async () => {
    const { priya } = await setupFamilies({ other: false });
    const first = await raiseOk(priya, {});
    await makeStale(first.id);
    const second = await raiseOk(priya, {}, 201);
    assert.notEqual(second.id, first.id);
    assert.equal((await rawAlert(first.id)).status, 'expired');
    await flushPushes();
    assert.equal(pushesOf('sos').length, 2);
  });

  it('starts a new alert once the previous one was resolved', async () => {
    const { priya } = await setupFamilies({ other: false });
    const first = await raiseOk(priya, {});
    assertOk(await resolve(priya, first.id, { resolution: 'false_alarm' }));
    const second = await raiseOk(priya, {}, 201);
    assert.notEqual(second.id, first.id);
  });

  it('concurrent POSTs create exactly one alert and one push', async () => {
    const { priya } = await setupFamilies({ other: false });
    const responses = await Promise.all(Array.from({ length: 6 }, () => raise(priya, { message: 'help' })));
    const statuses = responses.map((r) => r.status).sort();
    assert.deepEqual(statuses, [200, 200, 200, 200, 200, 201], JSON.stringify(responses.map((r) => r.body)));
    const ids = new Set(responses.map((r) => r.body.data.id));
    assert.equal(ids.size, 1);
    assert.equal(await SosAlert.countDocuments({ memberId: priya.member.id, status: 'active' }), 1);
    await flushPushes();
    assert.equal(pushesOf('sos').length, 1);
  });

  describe('duplicate key on create (partial unique index on active alerts, if added)', () => {
    /** Makes the first `failures` upserts fail with E11000, then restores the real method. */
    async function withDuplicateKeys(failures, fn) {
      const original = SosAlert.findOneAndUpdate;
      let calls = 0;
      SosAlert.findOneAndUpdate = function stubbed(...args) {
        calls += 1;
        if (calls <= failures) {
          const err = new Error('E11000 duplicate key error collection: familyhub_test.sos_alerts');
          err.code = 11000;
          return Promise.reject(err);
        }
        return original.apply(this, args);
      };
      try {
        return await fn();
      } finally {
        SosAlert.findOneAndUpdate = original;
      }
    }

    it('answers with the concurrent winner (200, no push)', async () => {
      const { priya } = await setupFamilies({ other: false });
      const now = new Date();
      const winner = await SosAlert.create({
        familyId: priya.family.id,
        memberId: priya.member.id,
        startedAt: now,
        expiresAt: new Date(now.getTime() + SOS_DURATION_MS),
      });
      const alert = await withDuplicateKeys(1, () => raiseOk(priya, {}, 200));
      assert.equal(alert.id, String(winner._id));
      assert.equal(pushesOf('sos').length, 0);
    });

    it('retries once when the winner already ended, then creates (201)', async () => {
      const { priya } = await setupFamilies({ other: false });
      const alert = await withDuplicateKeys(1, () => raiseOk(priya, {}, 201));
      assert.equal(alert.status, 'active');
      assert.equal(pushesOf('sos').length, 1);
    });

    it('gives up with 409 CONFLICT after the retry', async () => {
      const { priya } = await setupFamilies({ other: false });
      await withDuplicateKeys(2, async () => assertError(await raise(priya, {}), 409, 'CONFLICT'));
      assert.equal(await SosAlert.countDocuments({}), 0);
    });
  });

  it('pushes a high-priority `sos` to every other member with an account', async () => {
    const { admin, priya, ravi, child } = await setupFamilies();
    await addDevice(admin, 'token-admin-1', 'en');
    await addDevice(ravi, 'token-ravi-1');
    await addDevice(priya, 'token-priya-1');
    await setSharing(priya, 'sos_only');
    await clearPushes();

    const alert = await raiseOk(priya, { location: { lat: 1, lng: 2 }, message: 'chest pain' });
    const [push] = pushesOf('sos');
    assert.ok(push, 'sos push recorded');
    assert.equal(sentPushes.length, 1);
    assert.equal(push.familyId, priya.family.id);
    assert.equal(push.id, alert.id);
    assert.equal(push.route, `/sos/alert/${alert.id}`);
    assert.equal(push.highPriority, true);
    assert.equal(push.channelId, 'sos_alerts');
    assert.equal(push.titleKey, 'sos.push.alert.title');
    assert.equal(push.bodyKey, 'sos.push.alert.body');
    assert.deepEqual(push.vars, { name: 'Priya' });
    assert.deepEqual(push.excludeMemberIds, [priya.member.id]);

    await flushPushes();
    assert.deepEqual([...push.memberIds].sort(), [admin.member.id, ravi.member.id].sort());
    assert.ok(!push.memberIds.includes(child.id), 'managed profiles have no devices');
    const tokens = push.messages.map((m) => m.token).sort();
    assert.deepEqual(tokens, ['token-admin-1', 'token-ravi-1']);
    for (const m of push.messages) {
      assert.equal(m.title, 'SOS from Priya');
      assert.match(m.body, /Priya/);
      assert.doesNotMatch(m.body, /chest pain/, 'the free-text message never goes into the notification');
    }
  });

  it('uses the no-location push text when the location is not shared', async () => {
    const { priya } = await setupFamilies({ other: false });
    await raiseOk(priya, { location: { lat: 1, lng: 2 } });
    const [push] = pushesOf('sos');
    assert.equal(push.bodyKey, 'sos.push.alert.bodyNoLocation');
  });

  it('admins can raise an SOS too; members get the push', async () => {
    const { admin, priya, ravi } = await setupFamilies({ other: false });
    const alert = await raiseOk(admin, {});
    assert.equal(alert.memberId, admin.member.id);
    await flushPushes();
    const [push] = pushesOf('sos');
    assert.deepEqual([...push.memberIds].sort(), [priya.member.id, ravi.member.id].sort());
  });

  it('fills memberPhone and memberAvatarUrl from the member profile', async () => {
    const { priya } = await setupFamilies({ other: false });
    const patch = await request.patch(`${API}/me`).set(priya.auth).send({ phone: '+91 98765 43210', avatarUrl: CLOUD_URL });
    assert.equal(patch.status, 200, JSON.stringify(patch.body));
    const alert = await raiseOk(priya, {});
    assert.equal(alert.memberPhone, '+919876543210');
    assert.equal(alert.memberAvatarUrl, CLOUD_URL);
  });

  it('keeps families separate: each family has its own active alert', async () => {
    const { priya, otto, admin, olga } = await setupFamilies();
    const a = await raiseOk(priya, {});
    const b = await raiseOk(otto, {});
    assert.notEqual(a.id, b.id);
    const mine = assertOk(await getActive(admin));
    assert.deepEqual(mine.map((x) => x.id), [a.id]);
    const theirs = assertOk(await getActive(olga));
    assert.deepEqual(theirs.map((x) => x.id), [b.id]);
  });

  it('422 VALIDATION_ERROR with field details (nothing is created, no push)', async () => {
    const { priya } = await setupFamilies({ other: false });
    const cases = [
      [{ message: 'x'.repeat(141) }, ['message']],
      [{ message: 42 }, ['message']],
      [{ location: { lat: 91, lng: 0 } }, ['location.lat']],
      [{ location: { lat: -90.5, lng: 0 } }, ['location.lat']],
      [{ location: { lat: 0, lng: 180.01 } }, ['location.lng']],
      [{ location: { lat: 0, lng: -181 } }, ['location.lng']],
      [{ location: { lat: 0, lng: 0, accuracy: -1 } }, ['location.accuracy']],
      [{ location: { lat: '28.6', lng: '77.2' } }, ['location.lat', 'location.lng']],
      [{ location: { lat: null, lng: true } }, ['location.lat', 'location.lng']],
      [{ location: {} }, ['location.lat', 'location.lng']],
      [{ location: 'here' }, ['location']],
      [{ location: { lat: 91 }, message: 'y'.repeat(200) }, ['location.lat', 'location.lng', 'message']],
    ];
    for (const [body, fields] of cases) {
      assertValidation(await raise(priya, body), ...fields);
    }
    assertValidation(await raise(priya, [1, 2]), 'body');
    assert.equal(await SosAlert.countDocuments({}), 0);
    await flushPushes();
    assert.equal(pushesOf('sos').length, 0);
  });

  it('accepts the boundaries (140 chars, ±90 / ±180, accuracy 0)', async () => {
    const { priya, ravi } = await setupFamilies({ other: false });
    await setSharing(priya, 'always');
    const a = await raiseOk(priya, { message: 'm'.repeat(140), location: { lat: -90, lng: 180, accuracy: 0 } });
    assert.equal(a.message.length, 140);
    assertLocation(a.lastLocation, { lat: -90, lng: 180, accuracy: 0 });
    await raiseOk(ravi, { location: { lat: 90, lng: -180 } });
  });

  it('400 BAD_REQUEST for malformed JSON', async () => {
    const { priya } = await setupFamilies({ other: false });
    const res = await request
      .post(`${API}/sos`)
      .set(priya.auth)
      .set('Content-Type', 'application/json')
      .send('{"message": "help"');
    assertError(res, 400, 'BAD_REQUEST');
  });
});

// ---------------------------------------------------------------- GET /sos/active

describe('GET /sos/active', () => {
  it('returns the family\'s active alerts (own included), newest first, without trails', async () => {
    const { admin, priya, ravi } = await setupFamilies({ other: false });
    await setSharing(priya, 'sos_only');
    const a = await raiseOk(priya, { location: { lat: 1, lng: 2 } });
    // Started a minute earlier (whole window shifted, still active).
    await SosAlert.updateOne(
      { _id: a.id },
      { $set: { startedAt: new Date(Date.parse(a.startedAt) - 60_000), expiresAt: new Date(Date.parse(a.expiresAt) - 60_000) } },
    );
    const b = await raiseOk(admin, {});

    for (const viewer of [admin, priya, ravi]) {
      const list = assertOk(await getActive(viewer));
      assert.deepEqual(list.map((x) => x.id), [b.id, a.id]);
      list.forEach(assertSosShape);
      for (const alert of list) assert.deepEqual(alert.trail, []);
    }
    const priyaAlert = assertOk(await getActive(ravi)).find((x) => x.id === a.id);
    assertLocation(priyaAlert.lastLocation, { lat: 1, lng: 2 });
    assert.equal(priyaAlert.memberName, 'Priya');
  });

  it('is an empty array when nothing is active', async () => {
    const { admin } = await setupFamilies({ other: false });
    assert.deepEqual(assertOk(await getActive(admin)), []);
  });

  it('excludes resolved alerts and lazily expires stale ones (persisted)', async () => {
    const { admin, priya, ravi } = await setupFamilies({ other: false });
    const resolved = await raiseOk(priya, {});
    assertOk(await resolve(priya, resolved.id));
    const stale = await raiseOk(ravi, {});
    await makeStale(stale.id);
    const live = await raiseOk(admin, {});

    const list = assertOk(await getActive(priya));
    assert.deepEqual(list.map((x) => x.id), [live.id]);
    assert.equal((await rawAlert(stale.id)).status, 'expired');
  });
});

// ---------------------------------------------------------------- GET /sos/history

describe('GET /sos/history', () => {
  async function seedHistory(family, count) {
    const ids = [];
    const now = Date.now();
    for (let i = 0; i < count; i += 1) {
      const startedAt = new Date(now - (i + 1) * 3_600_000);
      const doc = await SosAlert.create({
        familyId: family.priya.family.id,
        memberId: family.priya.member.id,
        status: i % 2 ? 'expired' : 'resolved',
        startedAt,
        expiresAt: new Date(startedAt.getTime() + SOS_DURATION_MS),
        resolvedAt: i % 2 ? null : new Date(startedAt.getTime() + 60_000),
        resolvedById: i % 2 ? null : family.priya.member.id,
        resolution: i % 2 ? null : 'safe',
        trail: [{ lat: 1, lng: 1, recordedAt: startedAt }],
        locationShared: true,
      });
      ids.push(String(doc._id));
    }
    return ids; // newest first
  }

  it('lists resolved / expired alerts newest first with pagination meta', async () => {
    const family = await setupFamilies();
    const ids = await seedHistory(family, 5);
    await raiseOk(family.ravi, {}); // active → not in history
    await raiseOk(family.otto, {}); // other family

    const p1 = assertPaged(await getHistory(family.admin, '?page=1&limit=2'));
    assert.deepEqual(p1.meta, { page: 1, limit: 2, total: 5, hasMore: true });
    assert.deepEqual(p1.items.map((x) => x.id), ids.slice(0, 2));
    const p3 = assertPaged(await getHistory(family.ravi, '?page=3&limit=2'));
    assert.deepEqual(p3.meta, { page: 3, limit: 2, total: 5, hasMore: false });
    assert.deepEqual(p3.items.map((x) => x.id), ids.slice(4));
    const beyond = assertPaged(await getHistory(family.ravi, '?page=9&limit=2'));
    assert.deepEqual(beyond.items, []);

    const all = assertPaged(await getHistory(family.priya));
    assert.deepEqual(all.meta, { page: 1, limit: 20, total: 5, hasMore: false });
    for (const alert of all.items) {
      assertSosShape(alert);
      assert.ok(['resolved', 'expired'].includes(alert.status));
      assert.deepEqual(alert.trail, [], 'lists never carry the trail');
    }
  });

  it('shows an alert that expired lazily, and persists the expiry', async () => {
    const { admin, priya } = await setupFamilies({ other: false });
    const alert = await raiseOk(priya, {});
    assert.equal(assertPaged(await getHistory(admin)).items.length, 0);
    await makeStale(alert.id);
    const { items } = assertPaged(await getHistory(admin));
    assert.deepEqual(items.map((x) => [x.id, x.status]), [[alert.id, 'expired']]);
    assert.equal((await rawAlert(alert.id)).status, 'expired');
  });

  it('keeps alerts of a removed member (memberName null)', async () => {
    const { admin, priya } = await setupFamilies({ other: false });
    const alert = await raiseOk(priya, {});
    assertOk(await resolve(priya, alert.id));
    await Member.deleteOne({ _id: priya.member.id });
    const { items } = assertPaged(await getHistory(admin));
    assert.equal(items[0].id, alert.id);
    assert.equal(items[0].memberName, null);
    assert.equal(items[0].memberPhone, null);
  });

  it('422 on invalid pagination', async () => {
    const { admin } = await setupFamilies({ other: false });
    assertValidation(await getHistory(admin, '?page=0'), 'page');
    assertValidation(await getHistory(admin, '?limit=0'), 'limit');
    assertValidation(await getHistory(admin, '?limit=101'), 'limit');
    assertValidation(await getHistory(admin, '?page=abc&limit=1.5'), 'page', 'limit');
    assertPaged(await getHistory(admin, '?limit=100'));
  });
});

// ---------------------------------------------------------------- GET /sos/:id

describe('GET /sos/:id', () => {
  it('returns the alert with its trail (oldest first) to any member of the family', async () => {
    const { admin, priya, ravi } = await setupFamilies({ other: false });
    await setSharing(priya, 'sos_only');
    const alert = await raiseOk(priya, { location: { lat: 10, lng: 20, accuracy: 30 } });
    await openThrottle(alert.id);
    assertOk(await sendLocation(priya, alert.id, { lat: 11, lng: 21 }));

    for (const viewer of [admin, priya, ravi]) {
      const data = assertSosShape(assertOk(await getAlert(viewer, alert.id)));
      assert.equal(data.trail.length, 2);
      assertLocation(data.trail[0], { lat: 10, lng: 20, accuracy: 30 });
      assertLocation(data.trail[1], { lat: 11, lng: 21 });
      assert.ok(Date.parse(data.trail[0].recordedAt) <= Date.parse(data.trail[1].recordedAt));
      assert.deepEqual(data.lastLocation, data.trail[1]);
    }
  });

  it('never exposes a location for an alert raised with sharing `never`', async () => {
    const { ravi, priya } = await setupFamilies({ other: false });
    const alert = await raiseOk(priya, { location: { lat: 1, lng: 1 } });
    const data = assertOk(await getAlert(ravi, alert.id));
    assert.equal(data.locationShared, false);
    assert.equal(data.lastLocation, null);
    assert.deepEqual(data.trail, []);
  });

  it('computes and persists the lazy expiry', async () => {
    const { ravi, priya } = await setupFamilies({ other: false });
    const alert = await raiseOk(priya, {});
    await makeStale(alert.id);
    const data = assertOk(await getAlert(ravi, alert.id));
    assert.equal(data.status, 'expired');
    assert.equal((await rawAlert(alert.id)).status, 'expired');
  });

  it('404 for another family\'s alert or an unknown id, 400 for a malformed id', async () => {
    const { priya, olga, otto } = await setupFamilies();
    const alert = await raiseOk(priya, {});
    assertError(await getAlert(olga, alert.id), 404, 'NOT_FOUND');
    assertError(await getAlert(otto, alert.id), 404, 'NOT_FOUND');
    assertError(await getAlert(priya, MISSING_ID), 404, 'NOT_FOUND');
    assertError(await getAlert(priya, 'not-an-id'), 400, 'BAD_REQUEST');
  });
});

// ---------------------------------------------------------------- POST /sos/:id/location

describe('POST /sos/:id/location', () => {
  async function sharingAlert(family, { location = null } = {}) {
    await setSharing(family.priya, 'sos_only');
    return raiseOk(family.priya, location ? { location } : {});
  }

  it('stores the point of the owner and returns the alert (200, no trail)', async () => {
    const family = await setupFamilies({ other: false });
    const alert = await sharingAlert(family);
    const before = Date.now();
    const data = assertSosShape(assertOk(await sendLocation(family.priya, alert.id, { lat: 12.97, lng: 77.59, accuracy: 8 })));
    assert.equal(data.id, alert.id);
    assert.equal(data.status, 'active');
    assert.equal(data.locationShared, true);
    assertLocation(data.lastLocation, { lat: 12.97, lng: 77.59, accuracy: 8 });
    assert.ok(Date.parse(data.lastLocation.recordedAt) >= before - 1000, 'server time');
    assert.deepEqual(data.trail, []);
    const raw = await rawAlert(alert.id);
    assert.equal(raw.trail.length, 1);
    assert.equal(raw.lastLocationAt.toISOString(), data.lastLocation.recordedAt);
  });

  it('accepts but does not store updates sooner than 3 s after the last stored one', async () => {
    const family = await setupFamilies({ other: false });
    const alert = await sharingAlert(family, { location: { lat: 1, lng: 1 } });

    const throttled = assertOk(await sendLocation(family.priya, alert.id, { lat: 2, lng: 2 }));
    assertLocation(throttled.lastLocation, { lat: 1, lng: 1 });
    assert.equal((await rawAlert(alert.id)).trail.length, 1);

    await openThrottle(alert.id);
    const stored = assertOk(await sendLocation(family.priya, alert.id, { lat: 3, lng: 3 }));
    assertLocation(stored.lastLocation, { lat: 3, lng: 3 });
    const again = assertOk(await sendLocation(family.priya, alert.id, { lat: 4, lng: 4 }));
    assertLocation(again.lastLocation, { lat: 3, lng: 3 });

    const trail = assertOk(await getAlert(family.ravi, alert.id)).trail.map((p) => p.lat);
    assert.deepEqual(trail, [1, 3]);
  });

  it('concurrent updates inside one window store exactly one point', async () => {
    const family = await setupFamilies({ other: false });
    const alert = await sharingAlert(family);
    const responses = await Promise.all(
      Array.from({ length: 5 }, (_, i) => sendLocation(family.priya, alert.id, { lat: i, lng: i })),
    );
    for (const res of responses) assertOk(res);
    const raw = await rawAlert(alert.id);
    assert.equal(raw.trail.length, 1);
    assert.equal(raw.lastLocation.lat, raw.trail[0].lat);
  });

  it(`keeps only the newest ${SOS_TRAIL_MAX} points ($push + $slice)`, async () => {
    const family = await setupFamilies({ other: false });
    const alert = await sharingAlert(family);
    const start = Date.now() - 10 * 60_000;
    const seeded = Array.from({ length: SOS_TRAIL_MAX }, (_, i) => ({
      lat: i / 1000,
      lng: 0,
      accuracy: null,
      recordedAt: new Date(start + i * 5000),
    }));
    await SosAlert.updateOne(
      { _id: alert.id },
      { $set: { trail: seeded, lastLocation: seeded.at(-1), lastLocationAt: seeded.at(-1).recordedAt } },
    );
    await openThrottle(alert.id);
    assertOk(await sendLocation(family.priya, alert.id, { lat: 45, lng: 45 }));

    const raw = await rawAlert(alert.id);
    assert.equal(raw.trail.length, SOS_TRAIL_MAX);
    assert.equal(raw.trail[0].lat, 0.001, 'the oldest point was dropped');
    assert.equal(raw.trail.at(-1).lat, 45, 'the newest point is last');

    const { trail } = assertOk(await getAlert(family.admin, alert.id));
    assert.equal(trail.length, SOS_TRAIL_MAX);
    assert.equal(trail[0].lat, 0.001);
    assert.equal(trail.at(-1).lat, 45);
  });

  it('403 FORBIDDEN for anyone but the owner (admins included); 404 across families', async () => {
    const family = await setupFamilies();
    const alert = await sharingAlert(family);
    const body = { lat: 1, lng: 1 };
    assertError(await sendLocation(family.ravi, alert.id, body), 403, 'FORBIDDEN');
    assertError(await sendLocation(family.admin, alert.id, body), 403, 'FORBIDDEN');
    assertError(await sendLocation(family.olga, alert.id, body), 404, 'NOT_FOUND');
    assertError(await sendLocation(family.otto, alert.id, body), 404, 'NOT_FOUND');
    assertError(await sendLocation(family.priya, MISSING_ID, body), 404, 'NOT_FOUND');
    assertError(await sendLocation(family.priya, 'xyz', body), 400, 'BAD_REQUEST');
    assert.equal((await rawAlert(alert.id)).trail.length, 0);
  });

  it('409 SOS_NOT_ACTIVE once resolved or expired (expiry persisted)', async () => {
    const family = await setupFamilies({ other: false });
    const alert = await sharingAlert(family);
    assertOk(await resolve(family.priya, alert.id));
    const error = assertError(await sendLocation(family.priya, alert.id, { lat: 1, lng: 1 }), 409, 'SOS_NOT_ACTIVE');
    assert.equal(error.message, t('en', 'sos.errors.notActive'));

    const second = await raiseOk(family.priya, {});
    await makeStale(second.id);
    assertError(await sendLocation(family.priya, second.id, { lat: 1, lng: 1 }), 409, 'SOS_NOT_ACTIVE');
    const raw = await rawAlert(second.id);
    assert.equal(raw.status, 'expired');
    assert.equal(raw.trail.length, 0);
  });

  it('403 LOCATION_SHARING_DISABLED while the owner shares `never`', async () => {
    const family = await setupFamilies({ other: false });
    const alert = await raiseOk(family.priya, {});
    const error = assertError(await sendLocation(family.priya, alert.id, { lat: 1, lng: 1 }), 403, 'LOCATION_SHARING_DISABLED');
    assert.equal(error.message, t('en', 'sos.errors.locationSharingDisabled'));
    assert.equal((await rawAlert(alert.id)).trail.length, 0);
  });

  it('409 comes before 403 LOCATION_SHARING_DISABLED for an ended alert', async () => {
    const family = await setupFamilies({ other: false });
    const alert = await raiseOk(family.priya, {});
    assertOk(await resolve(family.priya, alert.id));
    assertError(await sendLocation(family.priya, alert.id, { lat: 1, lng: 1 }), 409, 'SOS_NOT_ACTIVE');
  });

  it('follows the owner\'s current mode: `never` → `sos_only` starts sharing, back to `never` stops it', async () => {
    const family = await setupFamilies({ other: false });
    const alert = await raiseOk(family.priya, {});
    assert.equal(alert.locationShared, false);

    await setSharing(family.priya, 'sos_only');
    const shared = assertOk(await sendLocation(family.priya, alert.id, { lat: 5, lng: 6 }));
    assert.equal(shared.locationShared, true);
    assertLocation(shared.lastLocation, { lat: 5, lng: 6 });

    await setSharing(family.priya, 'never');
    await openThrottle(alert.id);
    assertError(await sendLocation(family.priya, alert.id, { lat: 7, lng: 8 }), 403, 'LOCATION_SHARING_DISABLED');
    assert.equal((await rawAlert(alert.id)).trail.length, 1);
  });

  it('422 VALIDATION_ERROR with details (no coercion)', async () => {
    const family = await setupFamilies({ other: false });
    const alert = await sharingAlert(family);
    const cases = [
      [{}, ['lat', 'lng']],
      [{ lat: 1 }, ['lng']],
      [{ lat: 90.0001, lng: 0 }, ['lat']],
      [{ lat: 0, lng: 180.5 }, ['lng']],
      [{ lat: 0, lng: 0, accuracy: -0.1 }, ['accuracy']],
      [{ lat: '10', lng: 10 }, ['lat']],
      [{ lat: null, lng: 10 }, ['lat']],
      [{ lat: true, lng: false }, ['lat', 'lng']],
    ];
    for (const [body, fields] of cases) assertValidation(await sendLocation(family.priya, alert.id, body), ...fields);
    assert.equal((await rawAlert(alert.id)).trail.length, 0);
  });
});

// ---------------------------------------------------------------- POST /sos/:id/resolve

describe('POST /sos/:id/resolve', () => {
  it('the owner resolves; everyone else gets `sos_resolved`', async () => {
    const { admin, priya, ravi } = await setupFamilies({ other: false });
    await addDevice(admin, 'token-admin-r');
    const alert = await raiseOk(priya, {});
    await clearPushes();

    const before = Date.now();
    const data = assertSosShape(assertOk(await resolve(priya, alert.id, { resolution: 'safe' })));
    assert.equal(data.status, 'resolved');
    assert.equal(data.resolution, 'safe');
    assert.equal(data.resolvedById, priya.member.id);
    assert.ok(Date.parse(data.resolvedAt) >= before - 1000);
    assert.deepEqual(data.trail, []);

    const [push] = pushesOf('sos_resolved');
    assert.ok(push);
    assert.equal(push.route, `/sos/alert/${alert.id}`);
    assert.equal(push.id, alert.id);
    assert.equal(push.channelId, 'general');
    assert.equal(push.titleKey, 'sos.push.resolved.title');
    assert.equal(push.bodyKey, 'sos.push.resolved.body.safe');
    assert.equal(push.vars.name, 'Priya');
    assert.deepEqual(push.excludeMemberIds, [priya.member.id]);
    await flushPushes();
    assert.deepEqual([...push.memberIds].sort(), [admin.member.id, ravi.member.id].sort());
    assert.equal(push.messages[0].title, 'SOS ended: Priya');
    assert.equal(push.messages[0].body, 'Priya says they are safe.');

    assert.deepEqual(assertOk(await getActive(ravi)), []);
    assert.deepEqual(assertPaged(await getHistory(ravi)).items.map((x) => x.id), [alert.id]);
  });

  it('an admin resolves someone else\'s alert; the owner is notified', async () => {
    const { admin, priya, ravi } = await setupFamilies({ other: false });
    const alert = await raiseOk(priya, {});
    await clearPushes();
    const data = assertOk(await resolve(admin, alert.id, { resolution: 'helped' }));
    assert.equal(data.resolvedById, admin.member.id);
    assert.equal(data.resolution, 'helped');
    const [push] = pushesOf('sos_resolved');
    assert.equal(push.bodyKey, 'sos.push.resolved.bodyByOther.helped');
    assert.deepEqual(push.vars, { name: 'Priya', resolver: 'Amit' });
    await flushPushes();
    assert.deepEqual([...push.memberIds].sort(), [priya.member.id, ravi.member.id].sort());
  });

  it('is idempotent on an already resolved alert (first resolution wins, no second push)', async () => {
    const { admin, priya } = await setupFamilies({ other: false });
    const alert = await raiseOk(priya, {});
    const first = assertOk(await resolve(priya, alert.id, { resolution: 'false_alarm' }));
    const again = assertOk(await resolve(priya, alert.id, { resolution: 'safe' }));
    const byAdmin = assertOk(await resolve(admin, alert.id, { resolution: 'helped' }));
    assert.deepEqual(again, first);
    assert.deepEqual(byAdmin, first);
    await flushPushes();
    assert.equal(pushesOf('sos_resolved').length, 1);
  });

  it('concurrent resolves by the owner and an admin end it once', async () => {
    const { admin, priya } = await setupFamilies({ other: false });
    const alert = await raiseOk(priya, {});
    const [a, b] = await Promise.all([
      resolve(priya, alert.id, { resolution: 'safe' }),
      resolve(admin, alert.id, { resolution: 'helped' }),
    ]);
    const x = assertOk(a);
    const y = assertOk(b);
    assert.deepEqual(x, y);
    await flushPushes();
    assert.equal(pushesOf('sos_resolved').length, 1);
  });

  it('403 FORBIDDEN for another member; 404 for other families and unknown ids', async () => {
    const { priya, ravi, olga, otto } = await setupFamilies();
    const alert = await raiseOk(priya, {});
    const error = assertError(await resolve(ravi, alert.id), 403, 'FORBIDDEN');
    assert.equal(error.message, t('en', 'sos.errors.resolveNotAllowed'));
    assertError(await resolve(olga, alert.id), 404, 'NOT_FOUND');
    assertError(await resolve(otto, alert.id), 404, 'NOT_FOUND');
    assertError(await resolve(priya, MISSING_ID), 404, 'NOT_FOUND');
    assertError(await resolve(priya, '123'), 400, 'BAD_REQUEST');
    assert.equal((await rawAlert(alert.id)).status, 'active');

    assertOk(await resolve(priya, alert.id));
    assertError(await resolve(ravi, alert.id), 403, 'FORBIDDEN');
  });

  it('409 SOS_NOT_ACTIVE for an expired alert (status persisted, no push)', async () => {
    const { priya } = await setupFamilies({ other: false });
    const alert = await raiseOk(priya, {});
    await makeStale(alert.id);
    await clearPushes();
    assertError(await resolve(priya, alert.id), 409, 'SOS_NOT_ACTIVE');
    const raw = await rawAlert(alert.id);
    assert.equal(raw.status, 'expired');
    assert.equal(raw.resolution, null);
    assert.equal(sentPushes.length, 0);
  });

  it('422 VALIDATION_ERROR for a missing or unknown resolution', async () => {
    const { priya } = await setupFamilies({ other: false });
    const alert = await raiseOk(priya, {});
    assertValidation(await resolve(priya, alert.id, {}), 'resolution');
    assertValidation(await resolve(priya, alert.id, { resolution: 'ok' }), 'resolution');
    assertValidation(await resolve(priya, alert.id, { resolution: null }), 'resolution');
    assertValidation(await resolve(priya, alert.id, ['safe']), 'body');
    assert.equal((await rawAlert(alert.id)).status, 'active');
  });
});

// ---------------------------------------------------------------- serializer, helpers, i18n

describe('SOS · serializer, exported helpers and translations', () => {
  it('serializeSosAlert: lazy status, privacy backstop, trail order and cap', () => {
    const now = new Date('2026-09-27T10:00:00.000Z');
    const members = new Map([['aaaaaaaaaaaaaaaaaaaaaaaa', { name: 'Priya', phone: '', avatarUrl: null, locationSharing: 'sos_only' }]]);
    const points = Array.from({ length: SOS_TRAIL_MAX + 20 }, (_, i) => ({
      lat: i,
      lng: 0,
      recordedAt: new Date(now.getTime() - (SOS_TRAIL_MAX + 20 - i) * 1000),
    })).reverse(); // stored out of order on purpose
    const alert = {
      _id: 'bbbbbbbbbbbbbbbbbbbbbbbb',
      memberId: 'aaaaaaaaaaaaaaaaaaaaaaaa',
      status: 'active',
      locationShared: true,
      lastLocation: { lat: 1, lng: 2, recordedAt: now },
      trail: points,
      startedAt: new Date(now.getTime() - SOS_DURATION_MS),
      expiresAt: now,
      message: '',
    };
    const out = serializeSosAlert(alert, members, { withTrail: true, now });
    assert.equal(out.status, 'expired', 'expiresAt ≤ now → expired');
    assert.equal(out.memberName, 'Priya');
    assert.equal(out.memberPhone, null);
    assert.equal(out.message, null);
    assert.equal(out.trail.length, SOS_TRAIL_MAX);
    assert.deepEqual(out.trail.map((p) => p.lat), Array.from({ length: SOS_TRAIL_MAX }, (_, i) => i + 20));
    assert.deepEqual(serializeSosAlert(alert, members, { now }).trail, [], 'lists: no trail');

    const hidden = serializeSosAlert({ ...alert, locationShared: false }, members, { withTrail: true, now });
    assert.equal(hidden.lastLocation, null);
    assert.deepEqual(hidden.trail, []);

    assert.equal(sosStatusOf({ status: 'active', expiresAt: new Date(now.getTime() + 1) }, now), 'active');
    assert.equal(sosStatusOf({ status: 'resolved', expiresAt: new Date(0) }, now), 'resolved');
    assert.equal(isSosActive({ status: 'expired', expiresAt: new Date(now.getTime() + 1000) }, now), false);
    assert.equal(serializeSosAlert(null, members), null);
    assert.equal(serializeSosAlert({ ...alert, memberId: 'cccccccccccccccccccccccc' }, members, { now }).memberName, null);
  });

  it('activeAlertsForFamily (dashboard helper) expires stale alerts and serializes the rest', async () => {
    const { priya, ravi, admin } = await setupFamilies({ other: false });
    const live = await raiseOk(priya, {});
    const stale = await raiseOk(ravi, {});
    await makeStale(stale.id);
    const list = await sosService.activeAlertsForFamily(admin.family.id);
    assert.deepEqual(list.map((x) => x.id), [live.id]);
    list.forEach(assertSosShape);
    assert.equal((await rawAlert(stale.id)).status, 'expired');
    assert.deepEqual(await sosService.activeAlertsForFamily('nope'), []);
    assert.equal(await sosService.expireStaleAlerts(null), 0);
  });

  it('notifySosResolved (cascade helper) sends the `closed` text and excludes the resolver', async () => {
    const { admin, priya, ravi } = await setupFamilies({ other: false });
    const alert = await raiseOk(priya, {});
    await clearPushes();
    await sosService.notifySosResolved({
      familyId: admin.family.id,
      alertId: alert.id,
      ownerMemberId: priya.member.id,
      resolverMemberId: admin.member.id,
      resolution: null,
    });
    const [push] = pushesOf('sos_resolved');
    assert.equal(push.bodyKey, 'sos.push.resolved.bodyByOther.closed');
    assert.deepEqual(push.vars, { name: 'Priya', resolver: 'Amit' });
    await flushPushes();
    assert.deepEqual([...push.memberIds].sort(), [priya.member.id, ravi.member.id].sort());

    await clearPushes();
    const members = await getMemberMap(admin.family.id);
    await sosService.notifySosResolved({ familyId: admin.family.id, alertId: alert.id, ownerMemberId: priya.member.id, members });
    assert.equal(pushesOf('sos_resolved')[0].bodyKey, 'sos.push.resolved.body.closed');
    assert.deepEqual(pushesOf('sos_resolved')[0].excludeMemberIds, []);

    // An unknown resolution never produces a missing translation key.
    await clearPushes();
    await sosService.notifySosResolved({
      familyId: admin.family.id,
      alertId: alert.id,
      ownerMemberId: priya.member.id,
      resolverMemberId: priya.member.id,
      resolution: 'unexpected',
      members,
    });
    assert.equal(pushesOf('sos_resolved')[0].bodyKey, 'sos.push.resolved.body.closed');
  });

  it('every push / error key used by the module exists in en/sos.json and interpolates names', () => {
    const vars = { name: 'Priya', resolver: 'Amit' };
    const keys = [
      'sos.push.alert.title',
      'sos.push.alert.body',
      'sos.push.alert.bodyNoLocation',
      'sos.push.resolved.title',
      ...[...SOS_RESOLUTIONS, 'closed'].flatMap((r) => [`sos.push.resolved.body.${r}`, `sos.push.resolved.bodyByOther.${r}`]),
    ];
    for (const key of keys) {
      assert.ok(hasTranslation(key, 'en'), `${key} missing`);
      const text = t('en', key, vars);
      assert.match(text, /Priya/, key);
      assert.doesNotMatch(text, /\{\w+\}/, `${key} has an unfilled placeholder`);
      if (key.includes('bodyByOther')) assert.match(text, /Amit/, key);
    }
    for (const key of ['notOwner', 'resolveNotAllowed', 'notActive', 'locationSharingDisabled']) {
      assert.ok(hasTranslation(`sos.errors.${key}`, 'en'), key);
    }
    assert.equal(t('en', 'sos.push.alert.title', vars), 'SOS from Priya');
    // Every language resolves (translated, or English until a translator adds sos.json).
    for (const locale of ['hi', 'ar', 'es']) {
      const text = t(locale, 'sos.push.alert.title', vars);
      assert.notEqual(text, 'sos.push.alert.title');
      assert.match(text, /Priya/);
    }
  });
});

// ---------------------------------------------------------------- hardening (adversarial review)

/** Special characters are built from code points so the source shows exactly what is sent. */
const cp = (...points) => String.fromCodePoint(...points);
const SIREN = cp(0x1f6a8); // one emoji, 2 UTF-16 units
const FAMILY = cp(0x1f468, 0x200d, 0x1f469, 0x200d, 0x1f467); // one grapheme, 8 UTF-16 units
const ZWSP = cp(0x200b);
const ZWJ = cp(0x200d);
const ZWNJ = cp(0x200c);
const WORD_JOINER = cp(0x2060);
const BOM = cp(0xfeff);
const RLM = cp(0x200f);
const RLO = cp(0x202e);
const PDF = cp(0x202c);
const LRI = cp(0x2066);
const PDI = cp(0x2069);
const NUL = cp(0);
const BEL = cp(7);
const ESC = cp(0x1b);
const LINE_SEPARATOR = cp(0x2028);
const LONE_SURROGATE = String.fromCharCode(0xd800);
const REPLACEMENT = cp(0xfffd);

describe('SOS · hardening (adversarial review)', () => {
  it('counts the message in UTF-16 units like the model and the app, and never echoes it in errors', async () => {
    const { priya, ravi } = await setupFamilies({ other: false });
    // 70 sirens = 140 UTF-16 units: the limit, accepted and stored unchanged.
    const atLimit = await raiseOk(priya, { message: SIREN.repeat(70) });
    assert.equal(atLimit.message, SIREN.repeat(70));
    assert.equal((await rawAlert(atLimit.id)).message, SIREN.repeat(70));

    // 71 sirens (142 units) or 18 ZWJ families (144 units) used to pass zod (which counts code points)
    // and then fail in Mongoose with a message quoting the text. Now: a clean 422, nothing stored.
    for (const message of [SIREN.repeat(71), FAMILY.repeat(18), `chest pain, diabetic ${'x'.repeat(130)}`]) {
      const error = assertValidation(await raise(ravi, { message }), 'message');
      assert.equal(error.details.message, 'Message must be at most 140 characters');
      assert.ok(!JSON.stringify(error).includes(message.slice(0, 10)), 'the text is never echoed back');
    }
    assert.equal(await SosAlert.countDocuments({ memberId: ravi.member.id }), 0);
    const familyAtLimit = await raiseOk(ravi, { message: FAMILY.repeat(17) }); // 136 units
    assert.equal(familyAtLimit.message, FAMILY.repeat(17));
  });

  it('cleans the message: controls, bidi overrides, line breaks, NFC; invisible-only text → null', () => {
    const parse = (message) => {
      const result = createSosBody.safeParse({ message });
      assert.ok(result.success, JSON.stringify(result.error?.issues));
      return result.data.message;
    };
    // NUL / BEL / ESC removed, CRLF and U+2028 → LF, tab → space.
    assert.equal(parse(`a${NUL}b${BEL}c${ESC}d\r\ne\tf${LINE_SEPARATOR}g`), 'abcd\ne f\ng');
    // Bidi override / isolate controls ("Trojan Source" spoofing on relatives' screens) removed.
    assert.equal(parse(`${RLO}nimda${PDF} is ${LRI}here${PDI}`), 'nimda is here');
    // NFC: "e" + combining acute → precomposed "é".
    assert.equal(parse(`Cafe${cp(0x301)}`), `Caf${cp(0xe9)}`);
    // Text with nothing visible in it is blank.
    for (const blank of [`${ZWSP}${WORD_JOINER}${ZWJ}${BOM}`, ` ${cp(0x3164)} `, `${NUL}${RLO}\n\t`, cp(0xfe0f)]) {
      assert.equal(parse(blank), null, JSON.stringify(blank));
    }
    // Invisible edges are trimmed; scripts, emoji sequences, ZWNJ and RLM inside real text are kept.
    assert.equal(parse(`${ZWSP}${BOM} help ${WORD_JOINER}`), 'help');
    const mixed = `ساعدوني ${RLM}112 ${FAMILY} मदद करो می${ZWNJ}خواهم`;
    assert.equal(parse(mixed), mixed);
    // A lone surrogate becomes U+FFFD (exactly what MongoDB would store), the SOS never fails on it.
    assert.equal(parse(`help ${LONE_SURROGATE} me`), `help ${REPLACEMENT} me`);
    // Non-strings are left for the schema to reject.
    assert.equal(cleanSosMessage(42), 42);
    assert.equal(createSosBody.safeParse({ message: ['help'] }).success, false);
    assert.equal(createSosBody.safeParse({ message: { toString: 'x' } }).success, false);
  });

  it('answers with exactly what it stored for dirty text (end to end)', async () => {
    const { priya, ravi } = await setupFamilies({ other: false });
    const alert = await raiseOk(priya, { message: `  Need help${BEL}\r\nat gate ${LONE_SURROGATE}3${RLO}  ` });
    assert.equal(alert.message, `Need help\nat gate ${REPLACEMENT}3`);
    assert.equal((await rawAlert(alert.id)).message, alert.message);
    assert.deepEqual(assertOk(await getAlert(ravi, alert.id)).message, alert.message);

    const invisible = await raiseOk(ravi, { message: `${ZWSP}${ZWSP}${WORD_JOINER}` });
    assert.equal(invisible.message, null);
    assert.equal((await rawAlert(invisible.id)).message, null);
  });

  it('rejects or ignores NoSQL operators in the body, the id and the query', async () => {
    const { priya, ravi, olga, otto } = await setupFamilies();
    await setSharing(priya, 'sos_only');
    assertValidation(await raise(priya, { message: { $ne: null } }), 'message');
    assertValidation(await raise(priya, { location: { lat: { $gt: -91 }, lng: 0 } }), 'location.lat');
    assertValidation(await raise(priya, { location: { $where: 'sleep(1000)' } }), 'location.lat', 'location.lng');
    assert.equal(await SosAlert.countDocuments({}), 0);

    const alert = await raiseOk(priya, {});
    assertValidation(await sendLocation(priya, alert.id, { lat: { $gt: 0 }, lng: { $ne: null } }), 'lat', 'lng');
    assertValidation(await resolve(priya, alert.id, { resolution: { $in: SOS_RESOLUTIONS } }), 'resolution');
    assert.equal((await rawAlert(alert.id)).status, 'active');
    for (const id of ['{"$ne":null}', '[$ne]=1', `${alert.id}' || '1'=='1`, `${alert.id}0`]) {
      assertError(await getAlert(ravi, encodeURIComponent(id)), 400, 'BAD_REQUEST');
      assertError(await resolve(ravi, encodeURIComponent(id)), 400, 'BAD_REQUEST');
    }

    // Operators and unknown filters in the query never widen the result: own family, ended alerts only.
    assertOk(await resolve(priya, alert.id));
    await raiseOk(otto, {});
    const { items, meta } = assertPaged(
      await getHistory(ravi, `?page[$gt]=0&limit[$ne]=1&status=active&familyId=${olga.family.id}&memberId[$ne]=x`),
    );
    assert.deepEqual(items.map((x) => x.id), [alert.id]);
    assert.deepEqual(meta, { page: 1, limit: 20, total: 1, hasMore: false });
    const active = await request.get(`${API}/sos/active?familyId=${olga.family.id}&status[$ne]=active`).set(ravi.auth);
    assert.deepEqual(assertOk(active), []);
  });

  it('ignores server-owned fields in every body (mass assignment)', async () => {
    const { admin, priya, ravi, olga } = await setupFamilies();
    await setSharing(priya, 'sos_only');
    const past = '2000-01-01T00:00:00.000Z';
    const forged = {
      _id: MISSING_ID,
      id: MISSING_ID,
      familyId: olga.family.id,
      memberId: ravi.member.id,
      status: 'resolved',
      locationShared: false,
      startedAt: past,
      expiresAt: '2099-01-01T00:00:00.000Z',
      resolvedById: admin.member.id,
      resolvedAt: past,
      resolution: 'safe',
      trail: Array.from({ length: 5 }, () => ({ lat: 0, lng: 0, recordedAt: past })),
      lastLocationAt: '2099-01-01T00:00:00.000Z',
    };
    const before = Date.now();
    const alert = await raiseOk(priya, { ...forged, location: { lat: 1, lng: 2, recordedAt: past, familyId: olga.family.id } });
    assert.notEqual(alert.id, MISSING_ID);
    assert.equal(alert.memberId, priya.member.id);
    assert.equal(alert.status, 'active');
    assert.equal(alert.locationShared, true);
    assert.equal(alert.resolution, null);
    assert.equal(alert.resolvedById, null);
    assert.ok(Date.parse(alert.startedAt) >= before - 1000, 'server time');
    assert.equal(alert.lastLocation.recordedAt, alert.startedAt, 'server time, not the client value');
    let raw = await rawAlert(alert.id);
    assert.equal(String(raw.familyId), priya.family.id);
    assert.equal(raw.trail.length, 1);
    assert.equal(raw.lastLocationAt.toISOString(), alert.startedAt);

    // Location body: only lat / lng / accuracy count.
    await openThrottle(alert.id);
    const moved = assertOk(
      await sendLocation(priya, alert.id, { lat: 3, lng: 4, ...forged, recordedAt: past, $set: { status: 'resolved' } }),
    );
    assert.equal(moved.status, 'active');
    assert.ok(Date.parse(moved.lastLocation.recordedAt) >= before - 1000);
    raw = await rawAlert(alert.id);
    assert.equal(raw.status, 'active');
    assert.equal(String(raw.familyId), priya.family.id);
    assert.equal(String(raw.memberId), priya.member.id);
    assert.equal(raw.trail.length, 2);

    // Resolve body: only `resolution` counts; who and when come from the server.
    const done = assertOk(await resolve(priya, alert.id, { ...forged, resolution: 'false_alarm', status: 'active' }));
    assert.equal(done.status, 'resolved');
    assert.equal(done.resolution, 'false_alarm');
    assert.equal(done.resolvedById, priya.member.id);
    assert.ok(Date.parse(done.resolvedAt) >= before - 1000);

    // A raw `__proto__` / `constructor` key cannot smuggle fields or pollute prototypes.
    const proto = await request
      .post(`${API}/sos`)
      .set(ravi.auth)
      .set('Content-Type', 'application/json')
      .send(
        `{"__proto__":{"status":"resolved","memberId":"${priya.member.id}"},"constructor":{"prototype":{"status":"resolved"}},"message":"x"}`,
      );
    const data = assertSosShape(assertOk(proto, 201));
    assert.equal(data.status, 'active');
    assert.equal(data.memberId, ravi.member.id);
    assert.equal({}.status, undefined, 'no prototype pollution');
  });

  it('handles numeric edge cases in coordinates (no coercion, no infinities, exact round trip)', async () => {
    const { priya } = await setupFamilies({ other: false });
    await setSharing(priya, 'always');
    const alert = await raiseOk(priya, {});
    const rawJson = (body) =>
      request.post(`${API}/sos/${alert.id}/location`).set(priya.auth).set('Content-Type', 'application/json').send(body);
    assertValidation(await rawJson('{"lat":1e400,"lng":0}'), 'lat');
    assertValidation(await rawJson('{"lat":0,"lng":-1e400}'), 'lng');
    assertValidation(await rawJson('{"lat":0,"lng":0,"accuracy":1e400}'), 'accuracy');
    for (const [body, field] of [
      [{ lat: 1e13, lng: 0 }, 'lat'],
      [{ lat: -90.0000001, lng: 0 }, 'lat'],
      [{ lat: 0, lng: '1e2' }, 'lng'],
      [{ lat: 0, lng: 0, accuracy: 100_000.5 }, 'accuracy'],
      [{ lat: 0, lng: 0, accuracy: '5' }, 'accuracy'],
      [{ lat: [1], lng: 0 }, 'lat'],
    ]) {
      assertValidation(await sendLocation(priya, alert.id, body), field);
    }
    assert.equal((await rawAlert(alert.id)).trail.length, 0);

    const exact = assertOk(await sendLocation(priya, alert.id, { lat: 0.1 + 0.2, lng: -0, accuracy: 100_000 }));
    assert.equal(exact.lastLocation.lat, 0.30000000000000004);
    assert.equal(exact.lastLocation.lng, 0);
    assert.equal(exact.lastLocation.accuracy, 100_000);
  });

  it('keeps pagination within safe integers (a huge page is empty, an unsafe one is 422)', async () => {
    const { priya } = await setupFamilies({ other: false });
    const alert = await raiseOk(priya, {});
    assertOk(await resolve(priya, alert.id));
    const huge = assertPaged(await getHistory(priya, `?page=${Number.MAX_SAFE_INTEGER}&limit=100`));
    assert.deepEqual(huge.items, []);
    assert.deepEqual(huge.meta, { page: Number.MAX_SAFE_INTEGER, limit: 100, total: 1, hasMore: false });
    assertValidation(await getHistory(priya, '?page=9007199254740992'), 'page');
    assertValidation(await getHistory(priya, '?page=1e16'), 'page');
    assertValidation(await getHistory(priya, '?page=-1&limit=-1'), 'page', 'limit');
    assertValidation(await getHistory(priya, '?page=1&page=2'), 'page');
    assertValidation(await getHistory(priya, '?limit=Infinity'), 'limit');
    assert.equal(assertPaged(await getHistory(priya, '?page=1&limit=1e2')).meta.limit, 100);
  });

  it('hides the location of every alert while its owner shares `never` (consent withdrawn), deleting nothing', async () => {
    const { admin, priya, ravi } = await setupFamilies({ other: false });
    await setSharing(priya, 'sos_only');
    const alert = await raiseOk(priya, { location: { lat: 10, lng: 20 } });
    await openThrottle(alert.id);
    assertOk(await sendLocation(priya, alert.id, { lat: 11, lng: 21 }));

    const assertHidden = (data) => {
      assert.ok(data, 'alert expected');
      assert.equal(data.locationShared, false);
      assert.equal(data.lastLocation, null);
      assert.deepEqual(data.trail, []);
    };
    await setSharing(priya, 'never');
    for (const viewer of [admin, ravi, priya]) {
      assertHidden(assertOk(await getActive(viewer)).find((x) => x.id === alert.id));
      assertHidden(assertOk(await getAlert(viewer, alert.id)));
    }
    assertHidden((await sosService.activeAlertsForFamily(admin.family.id)).find((x) => x.id === alert.id));
    assertHidden(assertOk(await raise(priya, {}), 200)); // idempotent repeat
    assert.equal((await rawAlert(alert.id)).trail.length, 2, 'nothing is deleted');

    // Sharing again shows the stored points again; ended alerts follow the same rule.
    await setSharing(priya, 'sos_only');
    assert.equal(assertOk(await getAlert(ravi, alert.id)).trail.length, 2);
    assertOk(await resolve(admin, alert.id, { resolution: 'helped' }));
    assertLocation(assertPaged(await getHistory(ravi)).items[0].lastLocation, { lat: 11, lng: 21 });
    await setSharing(priya, 'never');
    assertHidden(assertPaged(await getHistory(ravi)).items[0]);
    assertHidden(assertOk(await getAlert(admin, alert.id)));
  });

  it('shows no location for the alerts of a member who left the family', async () => {
    const { admin, priya } = await setupFamilies({ other: false });
    await setSharing(priya, 'always');
    const alert = await raiseOk(priya, { location: { lat: 1, lng: 2 } });
    const left = await request.post(`${API}/me/leave-family`).set(priya.auth).send();
    assert.equal(left.status, 200, JSON.stringify(left.body));

    const data = assertOk(await getAlert(admin, alert.id));
    assert.equal(data.status, 'resolved', 'the member cascade closed it');
    assert.equal(data.memberName, null);
    assert.equal(data.lastLocation, null);
    assert.deepEqual(data.trail, []);
    assert.equal(assertPaged(await getHistory(admin)).items[0].lastLocation, null);
  });

  it('localizes every push per recipient device (device → account locale → en) and reaches only the family', async () => {
    const admin = await registerFamilyAdmin({ name: 'Amit' });
    const priya = await joinFamilyAs(admin.family.inviteCode, { name: 'Priya' });
    const ravi = await joinFamilyAs(admin.family.inviteCode, { name: 'Ravi', locale: 'es' });
    const olga = await registerFamilyAdmin({ name: 'Olga', family: { name: 'Other Family' } });
    await addDevice(admin, 'tok-admin-hi', 'hi');
    await addDevice(admin, 'tok-admin-ar', 'ar');
    await addDevice(ravi, 'tok-ravi'); // no device locale → account locale `es`
    await addDevice(priya, 'tok-priya', 'ta');
    await addDevice(olga, 'tok-olga', 'de');
    await clearPushes();

    const alert = await raiseOk(priya, {});
    await flushPushes();
    const [push] = pushesOf('sos');
    const byToken = Object.fromEntries(push.messages.map((m) => [m.token, m]));
    assert.deepEqual(Object.keys(byToken).sort(), ['tok-admin-ar', 'tok-admin-hi', 'tok-ravi']);
    for (const [token, locale] of [
      ['tok-admin-hi', 'hi'],
      ['tok-admin-ar', 'ar'],
      ['tok-ravi', 'es'],
    ]) {
      assert.equal(byToken[token].locale, locale, token);
      assert.equal(byToken[token].title, t(locale, 'sos.push.alert.title', { name: 'Priya' }));
      assert.equal(byToken[token].body, t(locale, 'sos.push.alert.bodyNoLocation', { name: 'Priya' }));
    }

    await clearPushes();
    assertOk(await resolve(admin, alert.id, { resolution: 'safe' }));
    await flushPushes();
    const [done] = pushesOf('sos_resolved');
    assert.deepEqual(done.messages.map((m) => m.token).sort(), ['tok-priya', 'tok-ravi']);
    const tamil = done.messages.find((m) => m.token === 'tok-priya');
    assert.equal(tamil.locale, 'ta');
    assert.equal(tamil.body, t('ta', 'sos.push.resolved.bodyByOther.safe', { name: 'Priya', resolver: 'Amit' }));
  });

  it('location updates racing a resolve never write to the ended alert', async () => {
    const family = await setupFamilies({ other: false });
    await setSharing(family.priya, 'sos_only');
    for (let round = 0; round < 3; round += 1) {
      const alert = await raiseOk(family.priya, {}, 201);
      const responses = await Promise.all([
        resolve(family.admin, alert.id, { resolution: 'helped' }),
        ...Array.from({ length: 6 }, (_, i) => sendLocation(family.priya, alert.id, { lat: i, lng: i })),
      ]);
      assertOk(responses[0]);
      for (const res of responses.slice(1)) {
        if (res.status === 409) assertError(res, 409, 'SOS_NOT_ACTIVE');
        else assert.equal(assertOk(res).id, alert.id);
      }
      const raw = await rawAlert(alert.id);
      assert.equal(raw.status, 'resolved');
      assert.ok(raw.trail.length <= 1, 'one window, at most one stored point');
      for (const point of raw.trail) assert.ok(point.recordedAt <= raw.resolvedAt, 'no point after the end');
      if (raw.lastLocationAt) assert.ok(raw.lastLocationAt <= raw.resolvedAt);
    }
    await flushPushes();
    assert.equal(pushesOf('sos_resolved').length, 3);
  });

  it('two members raising at the same moment each get their own alert and everyone else hears about both', async () => {
    const { admin, priya, ravi } = await setupFamilies({ other: false });
    const burst = await Promise.all([
      ...Array.from({ length: 5 }, () => raise(priya, { message: 'A' })),
      ...Array.from({ length: 5 }, () => raise(ravi, { message: 'B' })),
    ]);
    const priyaIds = new Set(burst.slice(0, 5).map((r) => assertOk(r, r.status).id));
    const raviIds = new Set(burst.slice(5).map((r) => assertOk(r, r.status).id));
    assert.equal(priyaIds.size, 1);
    assert.equal(raviIds.size, 1);
    assert.deepEqual(burst.map((r) => r.status).filter((s) => s === 201).length, 2);
    const [x] = priyaIds;
    const [y] = raviIds;
    assert.notEqual(x, y);

    await flushPushes();
    const pushes = pushesOf('sos');
    assert.equal(pushes.length, 2);
    assert.deepEqual([...pushes.find((p) => p.id === x).memberIds].sort(), [admin.member.id, ravi.member.id].sort());
    assert.deepEqual([...pushes.find((p) => p.id === y).memberIds].sort(), [admin.member.id, priya.member.id].sort());
    assert.deepEqual(assertOk(await getActive(admin)).map((z) => z.id).sort(), [x, y].sort());
  });
});
