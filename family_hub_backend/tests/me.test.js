/**
 * Me module: docs/03-API_CONTRACT.md §5 (`/me/*`) and the shared member-removal cascade
 * (src/modules/me/memberCascade.js, also used by `DELETE /family/members/:id`).
 *
 * Covers: auth on every route, PATCH /me (account + member fields, clearing, strict body, no-family
 * rule, GAP-04 location clearing, GAP-05 consent age), PUT /me/location (sharing modes, atomic
 * check, validation), device upsert / token move / cap / own-only delete, GET /me/export (scope,
 * decryption, no secrets), DELETE /me (password + lockout, LAST_ADMIN, family deletion, erasure of
 * tokens/devices/OTPs, owner transfer) and POST /me/leave-family (cascade, sessions kept), plus
 * races between concurrent leaves.
 *
 * The "hardening" suite at the end (b-me-harden) holds one test per issue found while trying to
 * break the module: operator injection, mass assignment, unicode/control characters, payload
 * size, numeric and time-zone edge cases, stale sessions, race-safe LAST_ADMIN, sos_resolved
 * pushes and erasure of location data.
 *
 * Other modules' endpoints (family, tasks, ledger …) are built in parallel, so fixture data is
 * written straight through the models.
 */
import {
  API,
  DEFAULT_PASSWORD,
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
import { after, before, beforeEach, describe, it } from 'node:test';

const { User, Family, Member, Device, RefreshToken, Otp, Task, LedgerEntry, Goal, Notice, SosAlert, EmergencyCard } =
  await import('../src/models/index.js');
const cascade = await import('../src/modules/me/memberCascade.js');
const meService = await import('../src/modules/me/me.service.js');
const { MAX_DEVICES_PER_USER } = meService;
const { EXPORT_FORMAT_VERSION } = await import('../src/modules/me/me.export.js');
const { resetPhantomLockouts } = await import('../src/modules/auth/auth.passwords.js');
const { consentAge } = await import('../src/lib/countries.js');
const { zonedParts, zonedTimeToUtc } = await import('../src/lib/dates.js');

let request;

before(async () => {
  ({ request } = await setupTestApp());
});
beforeEach(async () => {
  await resetDb();
  resetPhantomLockouts();
});
after(teardownTestApp);

// ---------------------------------------------------------------- helpers

const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const CLOUD_URL = 'https://res.cloudinary.com/demo/image/upload/v1/familyhub/avatar.jpg';
const DAY_MS = 24 * 60 * 60 * 1000;

function assertOk(res, status = 200) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.equal(res.body.success, true);
  assert.ok('data' in res.body);
  assert.ok(!('meta' in res.body), 'meta only on paginated lists');
  assert.ok(!('error' in res.body));
  return res.body.data;
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

/** Admin + a joined member in the same family. */
async function familyOfTwo() {
  const admin = await registerFamilyAdmin();
  const member = await joinFamilyAs(admin.family.inviteCode);
  return { admin, member, familyId: admin.family.id };
}

/** A managed profile (no account) written straight to the DB. */
function createManaged(familyId, overrides = {}) {
  return Member.create({
    familyId,
    name: 'Anaya',
    dateOfBirth: new Date('2016-08-01T00:00:00.000Z'),
    gender: 'female',
    role: 'member',
    guardianConsent: true,
    ...overrides,
  });
}

const promote = (memberId) => Member.updateOne({ _id: memberId }, { $set: { role: 'admin' } });

async function saveCard(familyId, memberId, fields = {}) {
  const card = new EmergencyCard({ familyId, memberId, bloodGroup: 'O+', ...fields });
  card.allergies = ['Peanuts'];
  card.notes = 'Carries an inhaler';
  card.insurancePolicyNumber = 'P-123';
  await card.save();
  return card;
}

/**
 * Personal data of `memberId` plus data of `otherId` in the same family:
 * tasks (pending/done assigned, pending created for the other), ledger entries, a notice,
 * an active and an expired SOS, an emergency card.
 */
async function seedMemberData(familyId, memberId, otherId, { name = 'Priya' } = {}) {
  const now = Date.now();
  const tasks = await Task.create([
    { familyId, title: 'Mine pending', assigneeId: memberId, createdById: otherId, category: 'chore', priority: 'low' },
    {
      familyId,
      title: 'Mine done',
      assigneeId: memberId,
      createdById: otherId,
      status: 'done',
      completedAt: new Date(),
      completedById: memberId,
    },
    { familyId, title: 'Created for other', assigneeId: otherId, createdById: memberId },
    { familyId, title: 'Not mine', assigneeId: otherId, createdById: otherId },
  ]);
  const entries = await LedgerEntry.create([
    {
      familyId,
      type: 'expense',
      amountMinor: 125050,
      category: 'groceries',
      date: new Date(),
      memberId,
      memberName: name,
      createdById: memberId,
    },
    {
      familyId,
      type: 'income',
      amountMinor: 500000,
      category: 'salary',
      date: new Date(),
      memberId,
      memberName: name,
      createdById: otherId,
    },
    {
      familyId,
      type: 'expense',
      amountMinor: 999,
      category: 'dining',
      date: new Date(),
      memberId: otherId,
      memberName: 'Other',
      createdById: otherId,
    },
  ]);
  const notices = await Notice.create([
    { familyId, title: 'My notice', body: 'Hello family', authorId: memberId },
    { familyId, title: 'Other notice', body: 'Hi', authorId: otherId },
  ]);
  const activeSos = await SosAlert.create({
    familyId,
    memberId,
    message: 'Help',
    locationShared: true,
    lastLocation: { lat: 28.6, lng: 77.2, accuracy: 10, recordedAt: new Date() },
    trail: [{ lat: 28.6, lng: 77.2, accuracy: 10, recordedAt: new Date() }],
  });
  const expiredSos = await SosAlert.create({
    familyId,
    memberId,
    startedAt: new Date(now - 60 * 60 * 1000),
    expiresAt: new Date(now - 45 * 60 * 1000),
  });
  const otherSos = await SosAlert.create({ familyId, memberId: otherId });
  const card = await saveCard(familyId, memberId);
  return { tasks, entries, notices, activeSos, expiredSos, otherSos, card };
}

const patchMe = (auth, body) => request.patch(`${API}/me`).set(auth).send(body);
const putLocation = (auth, body) => request.put(`${API}/me/location`).set(auth).send(body);
const addDevice = (auth, body) => request.post(`${API}/me/devices`).set(auth).send(body);
const deleteMe = (auth, body) => request.delete(`${API}/me`).set(auth).send(body);
const leave = (auth) => request.post(`${API}/me/leave-family`).set(auth).send();

// ---------------------------------------------------------------- auth on every route

describe('auth', () => {
  const routes = [
    ['patch', '/me'],
    ['put', '/me/location'],
    ['post', '/me/devices'],
    ['delete', '/me/devices/abc'],
    ['get', '/me/export'],
    ['delete', '/me'],
    ['post', '/me/leave-family'],
  ];

  for (const [method, path] of routes) {
    it(`${method.toUpperCase()} ${path} without a token → 401 UNAUTHORIZED`, async () => {
      assertError(await request[method](`${API}${path}`).send({}), 401, 'UNAUTHORIZED');
    });
  }

  it('a malformed token is rejected before validation', async () => {
    assertError(await patchMe(authHeader('not-a-jwt'), { role: 'admin' }), 401, 'UNAUTHORIZED');
  });
});

// ---------------------------------------------------------------- PATCH /me

describe('PATCH /me', () => {
  it('updates account and member fields and returns { user, member }', async () => {
    const admin = await registerFamilyAdmin();
    const data = assertOk(
      await patchMe(admin.auth, {
        name: '  Amit Kumar  ',
        phone: '+91 98765-43210',
        avatarUrl: CLOUD_URL,
        locale: 'hi',
        gender: 'male',
        dateOfBirth: '1984-03-10T00:00:00.000Z',
      }),
    );
    assert.deepEqual(Object.keys(data).sort(), ['member', 'user']);
    assert.equal(data.user.id, admin.user.id);
    assert.equal(data.user.name, 'Amit Kumar');
    assert.equal(data.user.locale, 'hi');
    assert.equal(data.user.role, 'admin');
    assert.equal(data.user.familyId, admin.family.id);
    assert.equal(data.member.id, admin.member.id);
    assert.equal(data.member.name, 'Amit Kumar');
    assert.equal(data.member.phone, '+919876543210');
    assert.equal(data.member.avatarUrl, CLOUD_URL);
    assert.equal(data.member.gender, 'male');
    assert.equal(data.member.dateOfBirth, '1984-03-10T00:00:00.000Z');
    assert.equal(data.member.role, 'admin');
    assert.equal(data.member.designation, admin.member.designation, 'designation untouched');
    assert.ok(!('passwordHash' in data.user));

    const user = await User.findById(admin.user.id).lean();
    const member = await Member.findById(admin.member.id).lean();
    assert.equal(user.name, 'Amit Kumar');
    assert.equal(user.locale, 'hi');
    assert.equal(member.name, 'Amit Kumar');
    assert.equal(member.phone, '+919876543210');
  });

  it('an empty body changes nothing', async () => {
    const admin = await registerFamilyAdmin();
    const data = assertOk(await patchMe(admin.auth, {}));
    assert.equal(data.user.name, admin.user.name);
    assert.equal(data.member.name, admin.member.name);
    assert.equal(data.member.updatedAt, admin.member.updatedAt);
  });

  it('null or blank clears the nullable fields; absent fields stay', async () => {
    const admin = await registerFamilyAdmin();
    assertOk(await patchMe(admin.auth, { phone: '+14155550100', avatarUrl: CLOUD_URL, gender: 'male' }));
    const data = assertOk(await patchMe(admin.auth, { phone: '', avatarUrl: null, dateOfBirth: null }));
    assert.equal(data.member.phone, null);
    assert.equal(data.member.avatarUrl, null);
    assert.equal(data.member.dateOfBirth, null);
    assert.equal(data.member.gender, 'male', 'absent key is left unchanged');
    const cleared = assertOk(await patchMe(admin.auth, { gender: null }));
    assert.equal(cleared.member.gender, null);
  });

  it('a member (non-admin) edits only their own profile', async () => {
    const { admin, member } = await familyOfTwo();
    const data = assertOk(await patchMe(member.auth, { name: 'Priya S', locationSharing: 'sos_only' }));
    assert.equal(data.member.id, member.member.id);
    assert.equal(data.member.role, 'member');
    assert.equal(data.member.locationSharing, 'sos_only');
    const adminRow = await Member.findById(admin.member.id).lean();
    assert.equal(adminRow.name, admin.member.name);
    assert.equal(adminRow.locationSharing, 'never');
  });

  it('rejects fields that cannot be changed here (role, designation, email) and writes nothing', async () => {
    const { member } = await familyOfTwo();
    for (const body of [{ role: 'admin' }, { designation: 'CEO' }, { email: 'x@example.com' }, { name: 'X', role: 'admin' }]) {
      const error = assertValidation(await patchMe(member.auth, body), 'body');
      assert.match(error.details.body, /Unrecognized key/);
    }
    const row = await Member.findById(member.member.id).lean();
    assert.equal(row.role, 'member');
    assert.equal(row.name, member.member.name);
  });

  it('validates every field (422 with details per field)', async () => {
    const admin = await registerFamilyAdmin();
    const cases = [
      [{ name: '' }, 'name'],
      [{ name: '   ' }, 'name'],
      [{ name: 'x'.repeat(61) }, 'name'],
      [{ name: null }, 'name'],
      [{ name: 42 }, 'name'],
      [{ phone: 'abc' }, 'phone'],
      [{ phone: '12345' }, 'phone'],
      [{ avatarUrl: 'https://evil.example.com/a.jpg' }, 'avatarUrl'],
      [{ avatarUrl: 'http://res.cloudinary.com/demo/a.jpg' }, 'avatarUrl'],
      [{ avatarUrl: 'not a url' }, 'avatarUrl'],
      [{ locale: 'xx' }, 'locale'],
      [{ locale: null }, 'locale'],
      [{ locationSharing: 'sometimes' }, 'locationSharing'],
      [{ locationSharing: null }, 'locationSharing'],
      [{ gender: 'robot' }, 'gender'],
      [{ dateOfBirth: 'yesterday' }, 'dateOfBirth'],
      [{ dateOfBirth: '2026-02-31' }, 'dateOfBirth'],
      [{ dateOfBirth: new Date(Date.now() + 3 * DAY_MS).toISOString() }, 'dateOfBirth'],
      [{ dateOfBirth: '1850-01-01' }, 'dateOfBirth'],
    ];
    for (const [body, field] of cases) assertValidation(await patchMe(admin.auth, body), field);
    // Several invalid fields are reported together.
    assertValidation(await patchMe(admin.auth, { name: '', locale: 'xx', gender: 'robot' }), 'name', 'locale', 'gender');
    const row = await Member.findById(admin.member.id).lean();
    assert.equal(row.name, admin.member.name);
  });

  it('switching location sharing away from always clears the stored location (GAP-04)', async () => {
    const admin = await registerFamilyAdmin();
    assertOk(await patchMe(admin.auth, { locationSharing: 'always' }));
    assertOk(await putLocation(admin.auth, { lat: 12.97, lng: 77.59, accuracy: 8 }));
    assert.ok((await Member.findById(admin.member.id).lean()).lastLocation);

    const data = assertOk(await patchMe(admin.auth, { locationSharing: 'sos_only' }));
    assert.equal(data.member.locationSharing, 'sos_only');
    assert.equal(data.member.lastLocation, null);
    assert.equal((await Member.findById(admin.member.id).lean()).lastLocation, null);
  });

  it('keeps the location while sharing stays always', async () => {
    const admin = await registerFamilyAdmin();
    assertOk(await patchMe(admin.auth, { locationSharing: 'always' }));
    assertOk(await putLocation(admin.auth, { lat: 1, lng: 2 }));
    const data = assertOk(await patchMe(admin.auth, { locationSharing: 'always', name: 'Amit' }));
    assert.deepEqual({ lat: data.member.lastLocation.lat, lng: data.member.lastLocation.lng }, { lat: 1, lng: 2 });
  });

  it('a date of birth below the consent age needs guardian consent (GAP-05)', async () => {
    const admin = await registerFamilyAdmin(); // family in IN
    const minAge = consentAge('IN');
    const young = new Date(Date.now() - (minAge - 2) * 365.25 * DAY_MS).toISOString();
    const error = assertError(await patchMe(admin.auth, { dateOfBirth: young }), 422, 'GUARDIAN_CONSENT_REQUIRED');
    assert.equal(error.details.consentAge, minAge);
    assert.equal((await Member.findById(admin.member.id).lean()).dateOfBirth.toISOString(), admin.member.dateOfBirth);

    // With recorded guardian consent (set by an admin) the same change is accepted.
    await Member.updateOne({ _id: admin.member.id }, { $set: { guardianConsent: true } });
    const data = assertOk(await patchMe(admin.auth, { dateOfBirth: young }));
    assert.equal(data.member.dateOfBirth, new Date(young).toISOString());
  });

  it('without a family: name/locale update the account, member fields → 403 NO_FAMILY', async () => {
    const { member } = await familyOfTwo();
    assertOk(await leave(member.auth));

    const data = assertOk(await patchMe(member.auth, { name: 'Solo', locale: 'es' }));
    assert.equal(data.member, null);
    assert.equal(data.user.name, 'Solo');
    assert.equal(data.user.locale, 'es');
    assert.equal(data.user.familyId, null);
    assert.equal(data.user.role, null);

    for (const body of [{ phone: '+14155550100' }, { locationSharing: 'always' }, { name: 'X', gender: 'male' }]) {
      assertError(await patchMe(member.auth, body), 403, 'NO_FAMILY');
    }
    assert.equal((await User.findById(member.user.id).lean()).name, 'Solo', 'nothing written on NO_FAMILY');
  });
});

// ---------------------------------------------------------------- PUT /me/location

describe('PUT /me/location', () => {
  it('stores the location when sharing is always and returns { recordedAt }', async () => {
    const { admin, member } = await familyOfTwo();
    assertOk(await patchMe(member.auth, { locationSharing: 'always' }));
    const before = Date.now();
    const data = assertOk(await putLocation(member.auth, { lat: -33.86, lng: 151.2, accuracy: 12.5 }));
    assert.deepEqual(Object.keys(data), ['recordedAt']);
    assert.match(data.recordedAt, ISO);
    assert.ok(new Date(data.recordedAt).getTime() >= before - 1000);

    const row = await Member.findById(member.member.id).lean();
    assert.equal(row.lastLocation.lat, -33.86);
    assert.equal(row.lastLocation.lng, 151.2);
    assert.equal(row.lastLocation.accuracy, 12.5);
    assert.equal(row.lastLocation.recordedAt.toISOString(), data.recordedAt);

    // Visible to the family because the mode is `always`.
    const me = assertOk(await request.get(`${API}/auth/me`).set(admin.auth));
    assert.ok(me.member);
    const session = assertOk(await request.get(`${API}/auth/me`).set(member.auth));
    assert.deepEqual(session.member.lastLocation, { lat: -33.86, lng: 151.2, accuracy: 12.5, recordedAt: data.recordedAt });
  });

  it('accuracy is optional (stored as null)', async () => {
    const admin = await registerFamilyAdmin();
    assertOk(await patchMe(admin.auth, { locationSharing: 'always' }));
    assertOk(await putLocation(admin.auth, { lat: 90, lng: -180 }));
    assertOk(await putLocation(admin.auth, { lat: -90, lng: 180, accuracy: null }));
    const row = await Member.findById(admin.member.id).lean();
    assert.deepEqual([row.lastLocation.lat, row.lastLocation.lng, row.lastLocation.accuracy], [-90, 180, null]);
  });

  it('403 LOCATION_SHARING_DISABLED for never (default) and sos_only; nothing stored', async () => {
    const admin = await registerFamilyAdmin();
    assertError(await putLocation(admin.auth, { lat: 1, lng: 2 }), 403, 'LOCATION_SHARING_DISABLED');
    assertOk(await patchMe(admin.auth, { locationSharing: 'sos_only' }));
    assertError(await putLocation(admin.auth, { lat: 1, lng: 2 }), 403, 'LOCATION_SHARING_DISABLED');
    assert.equal((await Member.findById(admin.member.id).lean()).lastLocation, null);
  });

  it('validates coordinates (no coercion)', async () => {
    const admin = await registerFamilyAdmin();
    assertOk(await patchMe(admin.auth, { locationSharing: 'always' }));
    const cases = [
      [{ lat: 90.01, lng: 0 }, 'lat'],
      [{ lat: -91, lng: 0 }, 'lat'],
      [{ lat: 0, lng: 180.5 }, 'lng'],
      [{ lat: 0, lng: -181 }, 'lng'],
      [{ lat: 0, lng: 0, accuracy: -1 }, 'accuracy'],
      [{ lat: '12', lng: 0 }, 'lat'],
      [{ lat: null, lng: 0 }, 'lat'],
      [{ lat: true, lng: 0 }, 'lat'],
      [{ lng: 0 }, 'lat'],
      [{ lat: 0 }, 'lng'],
    ];
    for (const [body, field] of cases) assertValidation(await putLocation(admin.auth, body), field);
    assert.equal((await Member.findById(admin.member.id).lean()).lastLocation, null);
  });

  it('403 NO_FAMILY without a family', async () => {
    const { member } = await familyOfTwo();
    assertOk(await leave(member.auth));
    assertError(await putLocation(member.auth, { lat: 1, lng: 2 }), 403, 'NO_FAMILY');
  });
});

// ---------------------------------------------------------------- devices

describe('POST /me/devices', () => {
  it('registers a device → { registered: true }', async () => {
    const admin = await registerFamilyAdmin();
    const data = assertOk(await addDevice(admin.auth, { token: 'fcm:token-1', platform: 'android', locale: 'ta' }));
    assert.deepEqual(data, { registered: true });
    const rows = await Device.find({ userId: admin.user.id }).lean();
    assert.equal(rows.length, 1);
    assert.equal(rows[0].token, 'fcm:token-1');
    assert.equal(rows[0].platform, 'android');
    assert.equal(rows[0].locale, 'ta');
  });

  it('upserts by token: registering again updates the same row', async () => {
    const admin = await registerFamilyAdmin();
    assertOk(await addDevice(admin.auth, { token: 'tok-A', platform: 'android', locale: 'hi' }));
    const first = await Device.findOne({ token: 'tok-A' }).lean();
    await new Promise((r) => setTimeout(r, 5));
    assertOk(await addDevice(admin.auth, { token: '  tok-A  ', platform: 'ios' }));
    const rows = await Device.find({ token: 'tok-A' }).lean();
    assert.equal(rows.length, 1);
    assert.equal(String(rows[0]._id), String(first._id));
    assert.equal(rows[0].platform, 'ios');
    assert.equal(rows[0].locale, null, 'absent locale → account locale is used for pushes');
    assert.ok(rows[0].lastSeenAt > first.lastSeenAt);
  });

  it('a token moves to the latest user (even across families)', async () => {
    const a = await registerFamilyAdmin();
    const b = await registerFamilyAdmin();
    assertOk(await addDevice(a.auth, { token: 'shared-phone', platform: 'android', locale: 'hi' }));
    assertOk(await addDevice(b.auth, { token: 'shared-phone', platform: 'android' }));
    const rows = await Device.find({ token: 'shared-phone' }).lean();
    assert.equal(rows.length, 1);
    assert.equal(String(rows[0].userId), b.user.id);
    assert.equal(rows[0].locale, null);
    assert.equal(await Device.countDocuments({ userId: a.user.id }), 0);
  });

  it('concurrent first registrations of one token end in one row', async () => {
    const admin = await registerFamilyAdmin();
    const results = await Promise.all(
      Array.from({ length: 5 }, () => addDevice(admin.auth, { token: 'race-token', platform: 'ios' })),
    );
    for (const res of results) assertOk(res);
    assert.equal(await Device.countDocuments({ token: 'race-token' }), 1);
  });

  it(`keeps only the ${MAX_DEVICES_PER_USER} most recently seen devices per account`, async () => {
    const admin = await registerFamilyAdmin();
    for (let i = 0; i < MAX_DEVICES_PER_USER + 2; i += 1) {
      assertOk(await addDevice(admin.auth, { token: `tok-${i}`, platform: 'android' }));
    }
    const tokens = (await Device.find({ userId: admin.user.id }).lean()).map((d) => d.token);
    assert.equal(tokens.length, MAX_DEVICES_PER_USER);
    assert.ok(!tokens.includes('tok-0') && !tokens.includes('tok-1'));
    assert.ok(tokens.includes(`tok-${MAX_DEVICES_PER_USER + 1}`));
  });

  it('validates the body', async () => {
    const admin = await registerFamilyAdmin();
    const cases = [
      [{ platform: 'android' }, 'token'],
      [{ token: '', platform: 'android' }, 'token'],
      [{ token: '   ', platform: 'android' }, 'token'],
      [{ token: 'has space', platform: 'android' }, 'token'],
      [{ token: 'x'.repeat(4097), platform: 'android' }, 'token'],
      [{ token: 123, platform: 'android' }, 'token'],
      [{ token: 'ok' }, 'platform'],
      [{ token: 'ok', platform: 'web' }, 'platform'],
      [{ token: 'ok', platform: 'android', locale: 'xx' }, 'locale'],
    ];
    for (const [body, field] of cases) assertValidation(await addDevice(admin.auth, body), field);
    assert.equal(await Device.countDocuments({}), 0);
  });

  it('works without a family (e.g. after leaving)', async () => {
    const { member } = await familyOfTwo();
    assertOk(await leave(member.auth));
    assertOk(await addDevice(member.auth, { token: 'solo-token', platform: 'ios', locale: null }));
    assert.equal(await Device.countDocuments({ userId: member.user.id }), 1);
  });
});

describe('DELETE /me/devices/:token', () => {
  it('removes the caller’s own token → null', async () => {
    const admin = await registerFamilyAdmin();
    const token = 'dK3:APA91b-x_y.z~1';
    assertOk(await addDevice(admin.auth, { token, platform: 'android' }));
    const data = assertOk(await request.delete(`${API}/me/devices/${encodeURIComponent(token)}`).set(admin.auth));
    assert.equal(data, null);
    assert.equal(await Device.countDocuments({ token }), 0);
  });

  it('never touches another user’s token and does not reveal it exists', async () => {
    const { admin, member } = await familyOfTwo();
    const other = await registerFamilyAdmin();
    assertOk(await addDevice(member.auth, { token: 'member-token', platform: 'ios' }));
    assertOk(await addDevice(other.auth, { token: 'other-family-token', platform: 'ios' }));
    for (const token of ['member-token', 'other-family-token']) {
      const data = assertOk(await request.delete(`${API}/me/devices/${token}`).set(admin.auth));
      assert.equal(data, null);
    }
    assert.equal(await Device.countDocuments({ token: 'member-token' }), 1);
    assert.equal(await Device.countDocuments({ token: 'other-family-token' }), 1);
  });

  it('is idempotent for unknown tokens', async () => {
    const admin = await registerFamilyAdmin();
    assert.equal(assertOk(await request.delete(`${API}/me/devices/never-registered`).set(admin.auth)), null);
    assert.equal(assertOk(await request.delete(`${API}/me/devices/never-registered`).set(admin.auth)), null);
  });

  it('an invalid token in the path → 400 BAD_REQUEST', async () => {
    const admin = await registerFamilyAdmin();
    assertError(await request.delete(`${API}/me/devices/a%20b`).set(admin.auth), 400, 'BAD_REQUEST');
  });
});

// ---------------------------------------------------------------- GET /me/export

describe('GET /me/export', () => {
  it('exports the caller’s personal data only, decrypted, without secrets', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    const other = await registerFamilyAdmin({ name: 'Other Family' });
    await seedMemberData(other.family.id, other.member.id, other.member.id, { name: 'Other Family' });
    const seeded = await seedMemberData(familyId, member.member.id, admin.member.id);
    assertOk(await patchMe(member.auth, { locationSharing: 'always', phone: '+14155550100' }));
    assertOk(await putLocation(member.auth, { lat: 10, lng: 20 }));
    assertOk(await addDevice(member.auth, { token: 'device-token-secret-ABCDEF', platform: 'android', locale: 'bn' }));

    const res = await request.get(`${API}/me/export`).set(member.auth);
    const data = assertOk(res);
    assert.equal(res.headers['cache-control'], 'no-store');

    assert.equal(data.formatVersion, EXPORT_FORMAT_VERSION);
    assert.match(data.exportedAt, ISO);
    assert.equal(data.user.id, member.user.id);
    assert.equal(data.user.email, member.user.email);
    assert.equal(data.user.role, 'member');
    assert.match(data.user.consentAcceptedAt, ISO);
    assert.equal(data.member.id, member.member.id);
    assert.equal(data.member.phone, '+14155550100');
    assert.equal(data.member.lastLocation.lat, 10);
    assert.equal(data.family.id, familyId);
    assert.equal(data.family.inviteCode, null, 'invite code never exported');
    assert.equal(data.family.memberCount, 2);
    assert.equal(data.currency, 'INR');

    // Tasks: assigned to / created by / completed by the caller — never unrelated ones.
    const titles = data.tasks.map((t) => t.title).sort();
    assert.deepEqual(titles, ['Created for other', 'Mine done', 'Mine pending']);
    const pending = data.tasks.find((t) => t.title === 'Mine pending');
    assert.equal(pending.assigneeId, member.member.id);
    assert.equal(pending.assigneeName, member.member.name);
    assert.equal(pending.createdByName, admin.member.name);

    // Ledger: owned or created by the caller, decimal major units.
    assert.equal(data.ledgerEntries.length, 2);
    assert.deepEqual(data.ledgerEntries.map((e) => e.amount).sort((x, y) => x - y), [1250.5, 5000]);
    assert.ok(data.ledgerEntries.every((e) => !('amountMinor' in e)));

    assert.deepEqual(data.notices.map((n) => n.title), ['My notice']);
    assert.equal(data.notices[0].authorName, member.member.name);

    // SOS: own alerts only, lazy expiry applied, trail included.
    assert.equal(data.sosAlerts.length, 2);
    const active = data.sosAlerts.find((a) => a.id === String(seeded.activeSos._id));
    assert.equal(active.status, 'active');
    assert.equal(active.trail.length, 1);
    assert.equal(data.sosAlerts.find((a) => a.id === String(seeded.expiredSos._id)).status, 'expired');

    // Emergency card decrypted.
    assert.equal(data.emergencyCard.memberId, member.member.id);
    assert.deepEqual(data.emergencyCard.allergies, ['Peanuts']);
    assert.equal(data.emergencyCard.notes, 'Carries an inhaler');
    assert.equal(data.emergencyCard.insurancePolicyNumber, 'P-123');

    assert.equal(data.devices.length, 1);
    assert.deepEqual(
      { platform: data.devices[0].platform, locale: data.devices[0].locale, suffix: data.devices[0].tokenSuffix },
      { platform: 'android', locale: 'bn', suffix: 'ABCDEF' },
    );
    assert.ok(data.sessions.length >= 1);
    assert.ok(data.sessions.some((s) => s.active));

    const raw = JSON.stringify(data);
    for (const secret of [
      'passwordHash',
      'tokenHash',
      'replacedByHash',
      'codeHash',
      'Enc"',
      'enc:v1:',
      'device-token-secret',
      admin.family.inviteCode,
      member.tokens.refreshToken,
      'Other Family',
    ]) {
      assert.ok(!raw.includes(secret), `export must not contain ${secret}`);
    }
  });

  it('an admin export has the same shape (no invite code either)', async () => {
    const admin = await registerFamilyAdmin();
    const data = assertOk(await request.get(`${API}/me/export`).set(admin.auth));
    assert.equal(data.user.role, 'admin');
    assert.equal(data.member.role, 'admin');
    assert.equal(data.family.inviteCode, null);
    assert.equal(data.emergencyCard, null);
    assert.deepEqual([data.tasks, data.ledgerEntries, data.notices, data.sosAlerts], [[], [], [], []]);
  });

  it('works without a family (account data only)', async () => {
    const { member } = await familyOfTwo();
    assertOk(await leave(member.auth));
    const data = assertOk(await request.get(`${API}/me/export`).set(member.auth));
    assert.equal(data.user.id, member.user.id);
    assert.equal(data.user.familyId, null);
    assert.equal(data.member, null);
    assert.equal(data.family, null);
    assert.equal(data.emergencyCard, null);
    assert.deepEqual([data.tasks, data.ledgerEntries, data.notices, data.sosAlerts], [[], [], [], []]);
  });
});

// ---------------------------------------------------------------- DELETE /me

describe('DELETE /me', () => {
  it('the only member: deletes the account and the whole family', async () => {
    const admin = await registerFamilyAdmin();
    const familyId = admin.family.id;
    await seedMemberData(familyId, admin.member.id, admin.member.id);
    await Goal.create({ familyId, title: 'Trip', targetMinor: 100000, createdById: admin.member.id });
    assertOk(await addDevice(admin.auth, { token: 'admin-device', platform: 'android' }));
    const other = await registerFamilyAdmin();
    await seedMemberData(other.family.id, other.member.id, other.member.id);

    assert.equal(assertOk(await deleteMe(admin.auth, { password: admin.password })), null);

    assert.equal(await User.countDocuments({ _id: admin.user.id }), 0);
    assert.equal(await Family.countDocuments({ _id: familyId }), 0);
    for (const Model of [Member, Task, LedgerEntry, Goal, Notice, SosAlert, EmergencyCard]) {
      assert.equal(await Model.countDocuments({ familyId }), 0, `${Model.modelName} of the family deleted`);
    }
    assert.equal(await Device.countDocuments({ userId: admin.user.id }), 0);
    assert.equal(await RefreshToken.countDocuments({ userId: admin.user.id }), 0);
    assert.equal(await Otp.countDocuments({ email: admin.user.email }), 0);

    // The other family is untouched.
    assert.equal(await Family.countDocuments({ _id: other.family.id }), 1);
    assert.equal(await Task.countDocuments({ familyId: other.family.id }), 4);
    assert.equal(await EmergencyCard.countDocuments({ familyId: other.family.id }), 1);

    // The old credentials are dead.
    assertError(await request.get(`${API}/auth/me`).set(admin.auth), 401, 'UNAUTHORIZED');
    assertError(
      await request.post(`${API}/auth/refresh`).send({ refreshToken: admin.tokens.refreshToken }),
      401,
      'INVALID_REFRESH_TOKEN',
    );
    assertError(
      await request.post(`${API}/auth/login`).send({ email: admin.user.email, password: admin.password }),
      401,
      'INVALID_CREDENTIALS',
    );
  });

  it('a member: deletes account, member, card, pending tasks; resolves SOS; keeps family history', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    const seeded = await seedMemberData(familyId, member.member.id, admin.member.id);
    assertOk(await addDevice(member.auth, { token: 'member-device', platform: 'ios' }));
    assertOk(await addDevice(admin.auth, { token: 'admin-device', platform: 'ios' }));

    assertOk(await deleteMe(member.auth, { password: member.password }));

    assert.equal(await User.countDocuments({ _id: member.user.id }), 0);
    assert.equal(await Member.countDocuments({ _id: member.member.id }), 0);
    assert.equal(await EmergencyCard.countDocuments({ memberId: member.member.id }), 0);
    assert.equal(await Device.countDocuments({ token: 'member-device' }), 0);
    assert.equal(await Device.countDocuments({ token: 'admin-device' }), 1);
    assert.equal(await RefreshToken.countDocuments({ userId: member.user.id }), 0);
    assert.equal(await Otp.countDocuments({ email: member.user.email }), 0);

    const remainingTitles = (await Task.find({ familyId }).lean()).map((t) => t.title).sort();
    assert.deepEqual(remainingTitles, ['Created for other', 'Mine done', 'Not mine']);
    assert.equal(await LedgerEntry.countDocuments({ familyId }), 3, 'ledger entries remain');
    assert.equal((await LedgerEntry.findById(seeded.entries[0]._id).lean()).memberName, 'Priya');
    assert.equal(await Notice.countDocuments({ familyId }), 2);

    const sos = await SosAlert.findById(seeded.activeSos._id).lean();
    assert.equal(sos.status, 'resolved');
    assert.ok(sos.resolvedAt);
    assert.equal(String(sos.resolvedById), member.member.id);
    assert.equal(sos.resolution, null);
    assert.equal((await SosAlert.findById(seeded.expiredSos._id).lean()).status, 'expired');
    assert.equal((await SosAlert.findById(seeded.otherSos._id).lean()).status, 'active', 'other member’s SOS untouched');

    // The family carries on.
    assert.equal(await Family.countDocuments({ _id: familyId }), 1);
    const session = assertOk(await request.get(`${API}/auth/me`).set(admin.auth));
    assert.equal(session.family.memberCount, 1);
  });

  it('409 LAST_ADMIN when the last admin has other members; nothing is deleted', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    await saveCard(familyId, admin.member.id);
    assertError(await deleteMe(admin.auth, { password: 'wrong-pass1' }), 401, 'INVALID_CREDENTIALS');
    assertError(await deleteMe(admin.auth, { password: admin.password }), 409, 'LAST_ADMIN');
    assert.equal((await User.findById(admin.user.id).lean()).failedLoginCount, 0, 'right password resets the streak');
    assert.equal(await User.countDocuments({ _id: admin.user.id }), 1);
    assert.equal(await Member.countDocuments({ familyId }), 2);
    assert.equal(await EmergencyCard.countDocuments({ memberId: admin.member.id }), 1);
    assertOk(await request.get(`${API}/auth/me`).set(admin.auth));
    assertOk(await request.get(`${API}/auth/me`).set(member.auth));
  });

  it('409 LAST_ADMIN also when the other members are only managed profiles', async () => {
    const admin = await registerFamilyAdmin();
    await createManaged(admin.family.id);
    assertError(await deleteMe(admin.auth, { password: admin.password }), 409, 'LAST_ADMIN');
  });

  it('409 LAST_ADMIN when the only other admin is a managed profile (cannot sign in)', async () => {
    const { admin } = await familyOfTwo();
    await createManaged(admin.family.id, { role: 'admin', name: 'Grandpa' });
    assertError(await deleteMe(admin.auth, { password: admin.password }), 409, 'LAST_ADMIN');
  });

  it('an admin may leave when another admin with an account exists; ownership moves to that admin', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    await promote(member.member.id);
    assert.equal(String((await Family.findById(familyId).lean()).ownerId), admin.user.id);

    assertOk(await deleteMe(admin.auth, { password: admin.password }));

    const family = await Family.findById(familyId).lean();
    assert.equal(String(family.ownerId), member.user.id);
    const session = assertOk(await request.get(`${API}/auth/me`).set(member.auth));
    assert.equal(session.member.role, 'admin');
    assert.equal(session.family.ownerId, member.user.id);
    assert.equal(session.family.memberCount, 1);
  });

  it('wrong password → 401 INVALID_CREDENTIALS (counts towards the lockout: 5th → 429)', async () => {
    const { member } = await familyOfTwo();
    for (let i = 0; i < 4; i += 1) {
      assertError(await deleteMe(member.auth, { password: 'wrong-pass1' }), 401, 'INVALID_CREDENTIALS');
    }
    const locked = assertError(await deleteMe(member.auth, { password: 'wrong-pass1' }), 429, 'TOO_MANY_REQUESTS');
    assert.ok(locked.details.retryAfterSeconds > 0);
    assertError(await deleteMe(member.auth, { password: member.password }), 429, 'TOO_MANY_REQUESTS');
    assert.equal(await User.countDocuments({ _id: member.user.id }), 1);
    assert.equal(await Member.countDocuments({ _id: member.member.id }), 1);
  });

  it('validates the body', async () => {
    const admin = await registerFamilyAdmin();
    assertValidation(await deleteMe(admin.auth, {}), 'password');
    assertValidation(await deleteMe(admin.auth, { password: '' }), 'password');
    assertValidation(await deleteMe(admin.auth, { password: 12345678 }), 'password');
    assertValidation(await request.delete(`${API}/me`).set(admin.auth), 'password');
    assert.equal(await User.countDocuments({ _id: admin.user.id }), 1);
  });

  it('works for an account without a family', async () => {
    const { member } = await familyOfTwo();
    assertOk(await leave(member.auth));
    assertOk(await addDevice(member.auth, { token: 'solo', platform: 'android' }));
    assertOk(await deleteMe(member.auth, { password: DEFAULT_PASSWORD }));
    assert.equal(await User.countDocuments({ _id: member.user.id }), 0);
    assert.equal(await Device.countDocuments({ token: 'solo' }), 0);
  });
});

// ---------------------------------------------------------------- POST /me/leave-family

describe('POST /me/leave-family', () => {
  it('a member leaves: unlinked with the member cascade, still signed in', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    const seeded = await seedMemberData(familyId, member.member.id, admin.member.id);
    assertOk(await addDevice(member.auth, { token: 'member-device', platform: 'android' }));

    const data = assertOk(await leave(member.auth));
    assert.deepEqual(Object.keys(data), ['user']);
    assert.equal(data.user.id, member.user.id);
    assert.equal(data.user.familyId, null);
    assert.equal(data.user.memberId, null);
    assert.equal(data.user.role, null);

    assert.equal(await Member.countDocuments({ _id: member.member.id }), 0);
    assert.equal(await EmergencyCard.countDocuments({ memberId: member.member.id }), 0);
    assert.equal(await Task.countDocuments({ _id: seeded.tasks[0]._id }), 0, 'pending task deleted');
    assert.equal(await Task.countDocuments({ _id: seeded.tasks[1]._id }), 1, 'done task kept');
    assert.equal(await LedgerEntry.countDocuments({ familyId }), 3);
    assert.equal((await SosAlert.findById(seeded.activeSos._id).lean()).status, 'resolved');
    const user = await User.findById(member.user.id).lean();
    assert.equal(user.familyId, null);
    assert.equal(user.memberId, null);

    // Still signed in (sessions and devices kept), now without a family.
    const session = assertOk(await request.get(`${API}/auth/me`).set(member.auth));
    assert.equal(session.member, null);
    assert.equal(session.family, null);
    assertOk(await request.post(`${API}/auth/refresh`).send({ refreshToken: member.tokens.refreshToken }));
    assert.equal(await Device.countDocuments({ token: 'member-device' }), 1);

    // Leaving again → NO_FAMILY; the family keeps its admin.
    assertError(await leave(member.auth), 403, 'NO_FAMILY');
    const adminSession = assertOk(await request.get(`${API}/auth/me`).set(admin.auth));
    assert.equal(adminSession.family.memberCount, 1);
  });

  it('409 LAST_ADMIN for the last admin while others remain', async () => {
    const { admin, familyId } = await familyOfTwo();
    assertError(await leave(admin.auth), 409, 'LAST_ADMIN');
    assert.equal(await Member.countDocuments({ familyId }), 2);
    assert.equal((await User.findById(admin.user.id).lean()).familyId.toString(), familyId);
  });

  it('the only member leaving deletes the family (user stays signed in)', async () => {
    const admin = await registerFamilyAdmin();
    const familyId = admin.family.id;
    await seedMemberData(familyId, admin.member.id, admin.member.id);

    const data = assertOk(await leave(admin.auth));
    assert.equal(data.user.familyId, null);
    assert.equal(await Family.countDocuments({ _id: familyId }), 0);
    for (const Model of [Member, Task, LedgerEntry, Notice, SosAlert, EmergencyCard]) {
      assert.equal(await Model.countDocuments({ familyId }), 0, `${Model.modelName} deleted`);
    }
    assert.equal(await User.countDocuments({ _id: admin.user.id }), 1);
    const session = assertOk(await request.get(`${API}/auth/me`).set(admin.auth));
    assert.equal(session.family, null);

    // The old invite code no longer works.
    const res = await request.post(`${API}/auth/register`).send({
      name: 'Late',
      email: 'late@example.com',
      password: DEFAULT_PASSWORD,
      consentAccepted: true,
      mode: 'join',
      inviteCode: admin.family.inviteCode,
    });
    assertError(res, 400, 'INVALID_INVITE_CODE');
  });

  it('an admin may leave when another admin exists (ownership transfers)', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    await promote(member.member.id);
    assertOk(await leave(admin.auth));
    assert.equal(String((await Family.findById(familyId).lean()).ownerId), member.user.id);
    assert.equal(await Member.countDocuments({ familyId, role: 'admin' }), 1);
  });

  it('a non-admin never hits LAST_ADMIN', async () => {
    const { admin } = await familyOfTwo();
    const second = await joinFamilyAs(admin.family.inviteCode);
    assertOk(await leave(second.auth));
  });

  it('403 NO_FAMILY without a family', async () => {
    const { member } = await familyOfTwo();
    assertOk(await leave(member.auth));
    assertError(await leave(member.auth), 403, 'NO_FAMILY');
  });

  it('two admins leaving at the same time never leave the family without an admin', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    await promote(member.member.id);
    const third = await joinFamilyAs(admin.family.inviteCode);

    const results = await Promise.all([leave(admin.auth), leave(member.auth)]);
    for (const res of results) assert.ok([200, 409].includes(res.status), JSON.stringify(res.body));

    const remaining = await Member.find({ familyId }).lean();
    assert.ok(remaining.some((m) => String(m._id) === third.member.id));
    assert.ok(remaining.some((m) => m.role === 'admin' && m.userId), 'at least one admin with an account remains');
  });

  it('the last two members leaving at the same time: never a family without an admin', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    await promote(member.member.id);
    const results = await Promise.all([leave(admin.auth), leave(member.auth)]);
    const statuses = results.map((res) => res.status);
    for (const res of results) assert.ok([200, 409].includes(res.status), JSON.stringify(res.body));
    if (statuses.every((s) => s === 200)) {
      // Usual outcome (the guard retries): the second leaver was alone and dissolved the family.
      assert.equal(await Family.countDocuments({ _id: familyId }), 0);
      assert.equal(await Member.countDocuments({ familyId }), 0);
      assert.equal(await User.countDocuments({ familyId }), 0);
    } else {
      // Heavy contention: a 409 the client can retry — whoever stayed is still an admin.
      const remaining = await Member.find({ familyId }).lean();
      assert.ok(remaining.length >= 1);
      assert.ok(remaining.every((m) => m.role === 'admin'), 'no claim is left behind');
    }
  });
});

// ---------------------------------------------------------------- memberCascade (shared with b-family)

describe('memberCascade', () => {
  it('removeMemberCascade (admin removes a member): unlinks the user, ends sessions, cleans up', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    const seeded = await seedMemberData(familyId, member.member.id, admin.member.id);
    assertOk(await addDevice(member.auth, { token: 'removed-device', platform: 'android' }));
    const row = await Member.findById(member.member.id).lean();

    const result = await cascade.removeMemberCascade({ member: row, actorId: admin.member.id });
    assert.deepEqual(
      { ...result },
      {
        memberId: member.member.id,
        userId: member.user.id,
        familyId,
        removed: true,
        tasksDeleted: 1,
        sosResolved: 1,
        sosExpired: 1,
        cardDeleted: true,
        familyDeleted: false,
      },
    );
    const sos = await SosAlert.findById(seeded.activeSos._id).lean();
    assert.equal(String(sos.resolvedById), admin.member.id);
    assert.equal(await RefreshToken.countDocuments({ userId: member.user.id }), 0);
    assert.equal(await Device.countDocuments({ userId: member.user.id }), 0);
    const user = await User.findById(member.user.id).lean();
    assert.deepEqual([user.familyId, user.memberId], [null, null]);

    // Signed out: the refresh token is gone (plain 401, no reuse cascade).
    assertError(
      await request.post(`${API}/auth/refresh`).send({ refreshToken: member.tokens.refreshToken }),
      401,
      'INVALID_REFRESH_TOKEN',
    );
    // Idempotent: running it again is harmless.
    const again = await cascade.removeMemberCascade({ member: row, actorId: admin.member.id });
    assert.equal(again.removed, false);
    assert.equal(again.familyDeleted, false);
  });

  it('removeMemberCascade works for managed profiles (no account)', async () => {
    const admin = await registerFamilyAdmin();
    const kid = await createManaged(admin.family.id);
    await Task.create({ familyId: admin.family.id, title: 'Kid task', assigneeId: kid._id, createdById: admin.member.id });
    await saveCard(admin.family.id, kid._id);
    const result = await cascade.removeMemberCascade({ member: kid, actorId: admin.member.id });
    assert.equal(result.userId, null);
    assert.equal(result.tasksDeleted, 1);
    assert.equal(result.cardDeleted, true);
    assert.equal(await Member.countDocuments({ _id: kid._id }), 0);
  });

  it('assertNotLastAdmin: leaving alone is allowed, demoting the only admin is not', async () => {
    const admin = await registerFamilyAdmin();
    const row = await Member.findById(admin.member.id).lean();
    await cascade.assertNotLastAdmin(row); // leaving alone → family is dissolved instead
    await assert.rejects(cascade.assertNotLastAdmin(row, { leaving: false }), (err) => err.code === 'LAST_ADMIN');
    await cascade.assertNotLastAdmin({ ...row, role: 'member' }, { leaving: false });
  });

  it('deleteFamilyCascade removes only that family', async () => {
    const a = await registerFamilyAdmin();
    const b = await registerFamilyAdmin();
    await seedMemberData(a.family.id, a.member.id, a.member.id);
    await seedMemberData(b.family.id, b.member.id, b.member.id);
    const counts = await cascade.deleteFamilyCascade(a.family.id);
    assert.equal(counts.families, 1);
    assert.equal(counts.members, 1);
    assert.equal(counts.tasks, 4);
    assert.equal(counts.usersUnlinked, 1);
    assert.equal(await Family.countDocuments({}), 1);
    assert.equal(await Task.countDocuments({ familyId: b.family.id }), 4);
    assert.equal(await Member.countDocuments({ familyId: b.family.id }), 1);
  });

  it('a family left without an admin (race) promotes its longest-standing member', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    const third = await joinFamilyAs(admin.family.inviteCode);
    const adminRow = await Member.findById(admin.member.id).lean();
    // Simulate a removal that skipped the LAST_ADMIN check (concurrent requests).
    await cascade.removeMemberCascade({ member: adminRow, actorId: admin.member.id });
    const promoted = await Member.findById(member.member.id).lean();
    assert.equal(promoted.role, 'admin');
    assert.equal((await Member.findById(third.member.id).lean()).role, 'member');
    assert.equal(String((await Family.findById(familyId).lean()).ownerId), member.user.id);
  });
});

// ---------------------------------------------------------------- hardening (b-me-harden)

/** Sends a raw JSON string (keeps `__proto__` / `constructor` as real keys). */
const rawJson = (method, path, auth, json) =>
  request[method](`${API}${path}`).set(auth).set('Content-Type', 'application/json').send(json);

/** Calendar date "today" in `timeZone` shifted by `years` / `days`, as local midnight (UTC instant). */
function localMidnight(timeZone, { years = 0, days = 0 } = {}) {
  const today = zonedParts(new Date(), timeZone);
  const day = today.month === 2 && today.day === 29 ? 28 : today.day;
  return zonedTimeToUtc({ year: today.year + years, month: today.month, day: day + days }, timeZone);
}

const pushesOf = (type) => sentPushes.filter((p) => p.type === type);

describe('hardening: PATCH /me', () => {
  it('rejects query operators and prototype keys in the body (NoSQL / prototype pollution)', async () => {
    const { member } = await familyOfTwo();
    for (const body of [{ name: { $ne: null } }, { phone: { $gt: '' } }, { locationSharing: { $in: ['always'] } }, { dateOfBirth: { $lt: 1 } }]) {
      assertValidation(await patchMe(member.auth, body), Object.keys(body)[0]);
    }
    for (const json of ['{"__proto__":{"role":"admin"}}', '{"constructor":{"prototype":{"role":"admin"}}}', '{"name":"X","__proto__":null}']) {
      const error = assertValidation(await rawJson('patch', '/me', member.auth, json), 'body');
      assert.match(error.details.body, /Unrecognized key/);
    }
    const row = await Member.findById(member.member.id).lean();
    assert.equal(row.role, 'member');
    assert.equal(row.name, member.member.name);
    assert.equal({}.role, undefined, 'Object.prototype untouched');
  });

  it('mass assignment: fields owned by the server or by admins are rejected, nothing is written', async () => {
    const { admin, member } = await familyOfTwo();
    const other = await registerFamilyAdmin();
    const forbidden = [
      { familyId: other.family.id },
      { userId: admin.user.id },
      { memberId: admin.member.id },
      { role: 'admin' },
      { guardianConsent: true },
      { guardianConsentAt: new Date().toISOString() },
      { hasAccount: false },
      { emailVerified: true },
      { lastLocation: { lat: 1, lng: 2 } },
      { savedMinor: 1 },
      { passwordHash: 'x' },
      { id: admin.member.id },
      { _id: admin.member.id },
    ];
    for (const body of forbidden) assertValidation(await patchMe(member.auth, { name: 'Hacker', ...body }), 'body');
    const [row, user] = await Promise.all([Member.findById(member.member.id).lean(), User.findById(member.user.id).lean()]);
    assert.deepEqual(
      [row.name, row.role, String(row.familyId), row.guardianConsent, user.emailVerified],
      [member.member.name, 'member', admin.family.id, false, false],
    );
  });

  it('names: scripts, RTL text and emoji are stored exactly; invisible or control characters are rejected', async () => {
    const admin = await registerFamilyAdmin();
    for (const name of ['محمد عبد الله', 'श्रीनिवास राव', '李小龍', '👨‍👩‍👧 Sharma', 'José Ñúñez', 'علي ‏محمد', 'अ'.repeat(60)]) {
      const data = assertOk(await patchMe(admin.auth, { name }));
      assert.equal(data.user.name, name);
      assert.equal(data.member.name, name);
      assert.equal((await User.findById(admin.user.id).lean()).name, name);
    }
    const bad = ['​', '​‍', '́', 'Amit\nSharma', 'Tab\there', 'a\u0000b', '‮nimda', 'x⁦y⁩', 'अ'.repeat(61)];
    for (const name of bad) assertValidation(await patchMe(admin.auth, { name }), 'name');
    assert.equal((await Member.findById(admin.member.id).lean()).name, 'अ'.repeat(60));
  });

  it('oversized and non-object bodies get a clean error envelope', async () => {
    const admin = await registerFamilyAdmin();
    assertError(await patchMe(admin.auth, { name: 'x'.repeat(200_000) }), 413, 'PAYLOAD_TOO_LARGE');
    assertValidation(await rawJson('patch', '/me', admin.auth, '[1,2]'), 'body');
    assertError(await rawJson('patch', '/me', admin.auth, '"name"'), 400, 'BAD_REQUEST');
    assertError(await rawJson('patch', '/me', admin.auth, '{"name": '), 400, 'BAD_REQUEST');
    assert.equal((await User.findById(admin.user.id).lean()).name, admin.user.name);
  });

  it('dates of birth: invalid, far past/future and non-string values are rejected; leap days work', async () => {
    const admin = await registerFamilyAdmin();
    const invalid = [
      '0000-01-01',
      '+010000-01-01T00:00:00.000Z',
      '2026-13-01',
      '2023-02-29',
      '2010-05-14T25:00:00Z',
      '2010-05-14T10:00:00', // no offset: would depend on the server time zone
      '1900-01-01T00:00:00.000+14:00', // 1899 in UTC
      new Date(Date.now() + 2 * DAY_MS).toISOString(),
      0,
      true,
      ['2010-05-14'],
    ];
    for (const dateOfBirth of invalid) assertValidation(await patchMe(admin.auth, { dateOfBirth }), 'dateOfBirth');
    const data = assertOk(await patchMe(admin.auth, { dateOfBirth: '1988-02-29' }));
    assert.equal(data.member.dateOfBirth, '1988-02-29T00:00:00.000Z');
  });

  it('GAP-05 uses the family time zone at the birthday boundary (IST is ahead of UTC)', async () => {
    const admin = await registerFamilyAdmin({ family: { country: 'IN', timezone: 'Asia/Kolkata' } });
    const tz = 'Asia/Kolkata';
    const minAge = consentAge('IN');
    // Turns 18 today in India → allowed.
    const adultToday = localMidnight(tz, { years: -minAge });
    assertOk(await patchMe(admin.auth, { dateOfBirth: adultToday.toISOString() }));
    // Turns 18 tomorrow in India → still a minor, although that local midnight is "today" in UTC.
    const minorTomorrow = localMidnight(tz, { years: -minAge, days: 1 });
    assertError(await patchMe(admin.auth, { dateOfBirth: minorTomorrow.toISOString() }), 422, 'GUARDIAN_CONSENT_REQUIRED');
    assert.equal((await Member.findById(admin.member.id).lean()).dateOfBirth.toISOString(), adultToday.toISOString());
  });

  it('GAP-05 at the boundary for a family behind UTC (US, consent age 13)', async () => {
    const tz = 'America/Los_Angeles';
    const admin = await registerFamilyAdmin({ family: { country: 'US', currency: 'USD', timezone: tz } });
    const minAge = consentAge('US');
    assertOk(await patchMe(admin.auth, { dateOfBirth: localMidnight(tz, { years: -minAge }).toISOString() }));
    const tooYoung = localMidnight(tz, { years: -minAge, days: 1 }).toISOString();
    assertError(await patchMe(admin.auth, { dateOfBirth: tooYoung }), 422, 'GUARDIAN_CONSENT_REQUIRED');
  });

  it('the response matches the contract objects exactly (no internal fields)', async () => {
    const admin = await registerFamilyAdmin();
    const data = assertOk(await patchMe(admin.auth, { name: 'Amit' }));
    assert.deepEqual(Object.keys(data.user).sort(), ['createdAt', 'email', 'emailVerified', 'familyId', 'id', 'locale', 'memberId', 'name', 'role']);
    assert.deepEqual(
      Object.keys(data.member).sort(),
      [
        'avatarUrl',
        'createdAt',
        'dateOfBirth',
        'designation',
        'email',
        'familyId',
        'gender',
        'guardianConsent',
        'hasAccount',
        'id',
        'lastLocation',
        'locationSharing',
        'name',
        'phone',
        'role',
        'updatedAt',
        'userId',
      ],
    );
    for (const value of [data.user.createdAt, data.member.createdAt, data.member.updatedAt]) assert.match(value, ISO);
  });
});

describe('hardening: PUT /me/location', () => {
  it('numeric edge cases: huge, non-numeric and operator values are rejected; floats are stored as sent', async () => {
    const admin = await registerFamilyAdmin();
    assertOk(await patchMe(admin.auth, { locationSharing: 'always' }));
    const cases = [
      [{ lat: 1e13, lng: 0 }, 'lat'],
      [{ lat: 0, lng: -1e13 }, 'lng'],
      [{ lat: 0, lng: 0, accuracy: 1e13 }, 'accuracy'],
      [{ lat: 'NaN', lng: 0 }, 'lat'],
      [{ lat: [1], lng: 0 }, 'lat'],
      [{ lat: { $gt: 0 }, lng: 0 }, 'lat'],
      [{ lat: 0, lng: 0, accuracy: '5' }, 'accuracy'],
    ];
    for (const [body, field] of cases) assertValidation(await putLocation(admin.auth, body), field);
    assertError(await rawJson('put', '/me/location', admin.auth, '{"lat": NaN, "lng": 0}'), 400, 'BAD_REQUEST');

    const lat = 0.1 + 0.2;
    const data = assertOk(await putLocation(admin.auth, { lat, lng: -0, accuracy: 0, recordedAt: '1970-01-01T00:00:00.000Z', userId: 'x' }));
    const row = await Member.findById(admin.member.id).lean();
    assert.equal(row.lastLocation.lat, lat);
    assert.equal(row.lastLocation.accuracy, 0);
    assert.equal(row.lastLocation.recordedAt.toISOString(), data.recordedAt, 'recordedAt is server time, never the client value');
    assert.notEqual(data.recordedAt, '1970-01-01T00:00:00.000Z');
  });

  it('a membership that ended after authentication → 403 NO_FAMILY, not LOCATION_SHARING_DISABLED', async () => {
    const { member } = await familyOfTwo();
    assertOk(await patchMe(member.auth, { locationSharing: 'always' }));
    const staleAuth = { id: member.user.id, familyId: member.family.id, memberId: member.member.id };
    assertOk(await leave(member.auth));
    await assert.rejects(meService.updateLocation(staleAuth, { lat: 1, lng: 2 }), (err) => err.code === 'NO_FAMILY');
  });
});

describe('hardening: devices', () => {
  it('operator / array tokens are rejected; a userId in the body is ignored', async () => {
    const { admin, member } = await familyOfTwo();
    assertValidation(await addDevice(member.auth, { token: { $ne: null }, platform: 'ios' }), 'token');
    assertValidation(await addDevice(member.auth, { token: ['a'], platform: 'ios' }), 'token');
    assertValidation(await addDevice(member.auth, { token: 'ok', platform: { $in: ['ios'] } }), 'platform');
    assertOk(await addDevice(member.auth, { token: 'mine-token', platform: 'ios', userId: admin.user.id }));
    assert.equal(String((await Device.findOne({ token: 'mine-token' }).lean()).userId), member.user.id);
    assert.equal(await Device.countDocuments({ userId: admin.user.id }), 0);
  });

  it('DELETE with operator-looking or oversized tokens never touches other rows', async () => {
    const { admin, member } = await familyOfTwo();
    assertOk(await addDevice(member.auth, { token: 'victim-token', platform: 'android' }));
    for (const path of ['%24ne', '%7B%22%24ne%22%3Anull%7D', '.*', 'victim-token%00']) {
      const res = await request.delete(`${API}/me/devices/${path}`).set(admin.auth);
      assert.ok([200, 400].includes(res.status), JSON.stringify(res.body));
    }
    assertError(await request.delete(`${API}/me/devices/${'x'.repeat(4097)}`).set(admin.auth), 400, 'BAD_REQUEST');
    assert.equal(await Device.countDocuments({ token: 'victim-token' }), 1);
  });

  it('a registration racing with account deletion leaves no device row (401)', async () => {
    const { member } = await familyOfTwo();
    const staleAuth = { id: member.user.id, familyId: member.family.id, memberId: member.member.id };
    assertOk(await deleteMe(member.auth, { password: member.password }));
    await assert.rejects(
      meService.registerDevice(staleAuth, { token: 'ghost-token', platform: 'ios', locale: null }),
      (err) => err.code === 'UNAUTHORIZED',
    );
    assert.equal(await Device.countDocuments({ token: 'ghost-token' }), 0);
    assert.equal(await Device.countDocuments({ userId: member.user.id }), 0);
  });
});

describe('hardening: GET /me/export', () => {
  it('references to removed members resolve to null names instead of failing', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    const second = await joinFamilyAs(admin.family.inviteCode, { name: 'Ravi' });
    await Task.create({ familyId, title: 'From Ravi', assigneeId: member.member.id, createdById: second.member.id, status: 'done', completedById: second.member.id, completedAt: new Date() });
    await Notice.create({ familyId, title: 'Mine', body: 'x', authorId: member.member.id });
    assertOk(await leave(second.auth));

    const data = assertOk(await request.get(`${API}/me/export`).set(member.auth));
    const task = data.tasks.find((t) => t.title === 'From Ravi');
    assert.equal(task.createdById, second.member.id);
    assert.equal(task.createdByName, null);
    assert.equal(task.assigneeName, member.member.name);
  });

  it('an admin export holds only the admin’s own data (not the family’s)', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    await seedMemberData(familyId, member.member.id, member.member.id);
    const data = assertOk(await request.get(`${API}/me/export`).set(admin.auth));
    assert.deepEqual([data.tasks, data.ledgerEntries, data.notices, data.sosAlerts], [[], [], [], []]);
    assert.equal(data.emergencyCard, null);
    assert.ok(!JSON.stringify(data).includes('Carries an inhaler'));
  });
});

describe('hardening: DELETE /me', () => {
  it('password: operators, arrays and over-long values → 422 with the right message', async () => {
    const admin = await registerFamilyAdmin();
    assertValidation(await deleteMe(admin.auth, { password: { $ne: null } }), 'password');
    assertValidation(await deleteMe(admin.auth, { password: [admin.password] }), 'password');
    const long = assertValidation(await deleteMe(admin.auth, { password: 'x'.repeat(129) }), 'password');
    assert.match(long.details.password, /too long/i);
    assert.equal((await User.findById(admin.user.id).lean()).failedLoginCount, 0, 'invalid bodies never count as a password attempt');
  });

  it('the lockout answer carries Retry-After', async () => {
    const { member } = await familyOfTwo();
    for (let i = 0; i < 4; i += 1) await deleteMe(member.auth, { password: 'wrong-pass1' });
    const res = await deleteMe(member.auth, { password: 'wrong-pass1' });
    const error = assertError(res, 429, 'TOO_MANY_REQUESTS');
    assert.equal(res.headers['retry-after'], String(error.details.retryAfterSeconds));
  });

  it('erasure removes the location points of the caller’s SOS alerts; the family keeps the summary', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    const seeded = await seedMemberData(familyId, member.member.id, admin.member.id);
    const adminSos = await SosAlert.create({
      familyId,
      memberId: admin.member.id,
      locationShared: true,
      lastLocation: { lat: 1, lng: 2, recordedAt: new Date() },
      trail: [{ lat: 1, lng: 2, recordedAt: new Date() }],
    });
    assertOk(await deleteMe(member.auth, { password: member.password }));

    const alerts = await SosAlert.find({ familyId, memberId: member.member.id }).lean();
    assert.equal(alerts.length, 2, 'alert summaries stay in the family history');
    for (const alert of alerts) {
      assert.deepEqual(alert.trail, []);
      assert.equal(alert.lastLocation, null);
    }
    assert.equal((await SosAlert.findById(seeded.activeSos._id).lean()).status, 'resolved');
    const kept = await SosAlert.findById(adminSos._id).lean();
    assert.equal(kept.trail.length, 1, 'other members’ alerts untouched');
  });

  it('leaving (not erasure) keeps the SOS location history', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    const seeded = await seedMemberData(familyId, member.member.id, admin.member.id);
    assertOk(await leave(member.auth));
    assert.equal((await SosAlert.findById(seeded.activeSos._id).lean()).trail.length, 1);
  });
});

describe('hardening: race-safe LAST_ADMIN', () => {
  it('another admin’s in-flight claim blocks leaving; after its release the leave succeeds', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    await promote(member.member.id);
    await joinFamilyAs(admin.family.inviteCode);
    const bRow = await Member.findById(member.member.id).lean();

    const guard = await cascade.claimAdminExit(bRow); // B is "mid-leave": demoted for now
    assert.equal(guard.claimed, true);
    assertError(await leave(admin.auth), 409, 'LAST_ADMIN');
    assert.equal((await Member.findById(admin.member.id).lean()).role, 'admin', 'a failed guard leaves the role as it was');

    await guard.release();
    assert.equal((await Member.findById(member.member.id).lean()).role, 'admin');
    assertOk(await leave(admin.auth));
    assert.equal(String((await Family.findById(familyId).lean()).ownerId), member.user.id);
  });

  it('two admins leaving together never strand a managed profile without an admin', async () => {
    for (let round = 0; round < 4; round += 1) {
      const { admin, member, familyId } = await familyOfTwo();
      await promote(member.member.id);
      const kid = await createManaged(familyId);

      const results = await Promise.all([leave(admin.auth), leave(member.auth)]);
      const statuses = results.map((r) => r.status).sort();
      assert.ok(statuses.every((s) => [200, 409].includes(s)), JSON.stringify(statuses));
      assert.notDeepEqual(statuses, [200, 200], 'both may not leave: the child profile would have no admin');

      const remaining = await Member.find({ familyId }).lean();
      assert.ok(remaining.some((m) => String(m._id) === String(kid._id)));
      assert.ok(remaining.some((m) => m.role === 'admin' && m.userId), `round ${round}: an admin with an account remains`);
      assert.ok(remaining.filter((m) => m.userId).every((m) => m.role === 'admin'), 'no claim is left behind');
      assert.equal(await Family.countDocuments({ _id: familyId }), 1);
    }
  });

  it('removeMemberGuarded: two admins removing each other at the same time keep one admin', async () => {
    for (let round = 0; round < 3; round += 1) {
      const { admin, member, familyId } = await familyOfTwo();
      await promote(member.member.id);
      const third = await joinFamilyAs(admin.family.inviteCode);
      const [aRow, bRow] = await Promise.all([Member.findById(admin.member.id).lean(), Member.findById(member.member.id).lean()]);

      const outcomes = await Promise.allSettled([
        cascade.removeMemberGuarded({ member: bRow, actorId: admin.member.id }),
        cascade.removeMemberGuarded({ member: aRow, actorId: member.member.id }),
      ]);
      for (const o of outcomes) if (o.status === 'rejected') assert.equal(o.reason.code, 'LAST_ADMIN');
      assert.ok(outcomes.some((o) => o.status === 'rejected'), 'both removals cannot succeed');

      const admins = await Member.find({ familyId, role: 'admin', userId: { $ne: null } }).lean();
      assert.equal(admins.length, 1, `round ${round}`);
      assert.equal((await Member.findById(third.member.id).lean()).role, 'member', 'nobody is promoted by the race');
    }
  });

  it('claimAdminExit({ leaving: false }) is an atomic demotion guarded by LAST_ADMIN', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    const aRow = await Member.findById(admin.member.id).lean();
    await assert.rejects(cascade.claimAdminExit(aRow, { leaving: false }), (err) => err.code === 'LAST_ADMIN');
    assert.equal((await Member.findById(admin.member.id).lean()).role, 'admin');

    await promote(member.member.id);
    const bRow = await Member.findById(member.member.id).lean();
    const outcomes = await Promise.allSettled([
      cascade.claimAdminExit(aRow, { leaving: false }),
      cascade.claimAdminExit(bRow, { leaving: false }),
    ]);
    assert.ok(outcomes.filter((o) => o.status === 'fulfilled').length <= 1, 'the two admins cannot demote each other at once');
    assert.equal(await Member.countDocuments({ familyId, role: 'admin' }), 1);
    // Non-admins pass straight through.
    const plain = await cascade.claimAdminExit({ ...aRow, role: 'member' }, { leaving: false });
    assert.equal(plain.claimed, false);
  });
});

describe('hardening: sos_resolved push from the cascade', () => {
  it('leaving with an active SOS tells the rest of the family (in their locale), not the leaver', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    assertOk(await addDevice(admin.auth, { token: 'admin-phone', platform: 'android', locale: 'hi' }));
    assertOk(await addDevice(member.auth, { token: 'member-phone', platform: 'ios' }));
    const alert = await SosAlert.create({ familyId, memberId: member.member.id });
    sentPushes.length = 0;

    assertOk(await leave(member.auth));
    await flushPushes();
    const pushes = pushesOf('sos_resolved');
    assert.equal(pushes.length, 1);
    const [push] = pushes;
    assert.equal(push.id, String(alert._id));
    assert.equal(push.route, `/sos/alert/${alert._id}`);
    assert.equal(push.bodyKey, 'sos.push.resolved.body.closed');
    assert.equal(push.vars.name, member.member.name);
    assert.equal(push.highPriority, true);
    assert.deepEqual(push.memberIds, [admin.member.id]);
    assert.deepEqual(push.messages.map((m) => [m.token, m.locale]), [['admin-phone', 'hi']]);
    assert.ok(push.messages[0].title.includes(member.member.name));
  });

  it('an admin removal names the admin as resolver and skips them and the removed member', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    const third = await joinFamilyAs(admin.family.inviteCode, { name: 'Ravi' });
    await SosAlert.create({ familyId, memberId: member.member.id });
    sentPushes.length = 0;

    const row = await Member.findById(member.member.id).lean();
    const result = await cascade.removeMemberGuarded({ member: row, actorId: admin.member.id });
    assert.equal(result.sosResolved, 1);
    await flushPushes();
    const [push] = pushesOf('sos_resolved');
    assert.equal(push.bodyKey, 'sos.push.resolved.bodyByOther.closed');
    assert.deepEqual(push.vars, { name: member.member.name, resolver: admin.member.name });
    assert.deepEqual(push.memberIds, [third.member.id]);
  });

  it('no push for expired or already resolved alerts, nor when the family is dissolved', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    const now = Date.now();
    await SosAlert.create({ familyId, memberId: member.member.id, startedAt: new Date(now - 3_600_000), expiresAt: new Date(now - 60_000) });
    const resolved = await SosAlert.create({
      familyId,
      memberId: member.member.id,
      status: 'resolved',
      resolution: 'safe',
      resolvedAt: new Date(),
      resolvedById: member.member.id,
    });
    sentPushes.length = 0;
    assertOk(await leave(member.auth));
    assert.equal(pushesOf('sos_resolved').length, 0);
    assert.equal((await SosAlert.findById(resolved._id).lean()).resolution, 'safe', 'an earlier resolution is kept');

    await SosAlert.create({ familyId, memberId: admin.member.id });
    assertOk(await leave(admin.auth)); // only member → family dissolved, nobody to tell
    assert.equal(pushesOf('sos_resolved').length, 0);
    assert.equal(await Family.countDocuments({ _id: familyId }), 0);
  });
});
