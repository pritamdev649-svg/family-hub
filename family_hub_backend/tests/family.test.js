/**
 * Family module: docs/03-API_CONTRACT.md §6 (everything under `/family` except the emergency card).
 *
 * Covers: 401 on every route, NO_FAMILY / FORBIDDEN matrix, POST /family (create, ALREADY_IN_FAMILY,
 * validation, time zones), POST /family/join (normalised codes, linking a pre-added profile,
 * MEMBER_EMAIL_EXISTS, INVALID_INVITE_CODE, age gate, member_joined push), GET / PATCH /family
 * (inviteCode only for admins, validation, GAP-05 on a country change), invite-code rotation,
 * member list order and privacy, add member (consent age, e-mail uniqueness, invitation e-mail in
 * the creator's locale), get / patch member (admin vs self-limited, LAST_ADMIN, account e-mail,
 * GAP-05 on DOB changes, concurrent demotions), delete member (cascade, self-removal, isolation),
 * translations and the envelope shape in every assertion.
 *
 * The last block ("hardening") pins the adversarial review (b-family-harden): injection and shape
 * attacks, races (consent vs date of birth, country changes, account links, concurrent adds),
 * text edge cases, invite-code rotation on removal, verified-address linking, invitation and
 * family-size limits.
 */
import {
  API,
  addManagedMember,
  authHeader,
  flushPushes,
  joinFamilyAs,
  lastMailTo,
  lastOtpFor,
  outbox,
  registerFamilyAdmin,
  resetDb,
  sentPushes,
  setupTestApp,
  teardownTestApp,
  uniqueEmail,
} from './helpers.js';
import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

const { User, Family, Member, Device, RefreshToken, Task, LedgerEntry, SosAlert, EmergencyCard } = await import(
  '../src/models/index.js'
);
const familyService = await import('../src/modules/family/family.service.js');
const { INVITATION_LIMITS, MAX_FAMILY_MEMBERS, resetInvitationLimits } = await import('../src/modules/family/family.rules.js');
const { normalizeFamilyTimeZone } = await import('../src/modules/family/family.schemas.js');
const { INVITE_CODE_REGEX } = await import('../src/lib/constants.js');
const { consentAge } = await import('../src/lib/countries.js');
const { zonedParts, zonedTimeToUtc } = await import('../src/lib/dates.js');
const { hasTranslation, t } = await import('../src/lib/i18n.js');
const { renderTemplate } = await import('../src/services/mailer.js');

let request;

before(async () => {
  ({ request } = await setupTestApp());
});
beforeEach(resetDb);
beforeEach(() => resetInvitationLimits());
after(teardownTestApp);

// ---------------------------------------------------------------- helpers

const FAMILY_URL = `${API}/family`;
const JOIN_URL = `${API}/family/join`;
const INVITE_URL = `${API}/family/invite-code`;
const MEMBERS_URL = `${API}/family/members`;
const memberUrl = (id) => `${MEMBERS_URL}/${id}`;

const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const CLOUD_URL = 'https://res.cloudinary.com/demo/image/upload/v1/familyhub/avatar.jpg';
const OTHER_ID = '64b7f0c2a1b2c3d4e5f60718';

const USER_KEYS = ['createdAt', 'email', 'emailVerified', 'familyId', 'id', 'locale', 'memberId', 'name', 'role'];
const FAMILY_KEYS = ['country', 'createdAt', 'currency', 'id', 'inviteCode', 'memberCount', 'name', 'ownerId', 'timezone'];
const MEMBER_KEYS = [
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
];

const keysOf = (obj) => Object.keys(obj).sort();

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

function assertMemberShape(member) {
  assert.deepEqual(keysOf(member), MEMBER_KEYS);
  assert.match(member.id, /^[a-f0-9]{24}$/);
  assert.match(member.createdAt, ISO);
  assert.match(member.updatedAt, ISO);
  assert.ok(!('_id' in member) && !('__v' in member));
  return member;
}

function assertFamilyShape(family) {
  assert.deepEqual(keysOf(family), FAMILY_KEYS);
  assert.match(family.id, /^[a-f0-9]{24}$/);
  assert.match(family.createdAt, ISO);
  return family;
}

/** Admin + a joined member (with an account) in the same family. */
async function familyOfTwo(adminOverrides = {}) {
  const admin = await registerFamilyAdmin(adminOverrides);
  const member = await joinFamilyAs(admin.family.inviteCode);
  return { admin, member, familyId: admin.family.id };
}

/** A signed-in account without a family (created a family, then left it → family deleted). */
async function userWithoutFamily(overrides = {}) {
  const account = await registerFamilyAdmin(overrides);
  assertOk(await request.post(`${API}/me/leave-family`).set(account.auth));
  return account;
}

/** Makes an existing member an admin (fixture shortcut). */
const promote = (memberId) => Member.updateOne({ _id: memberId }, { $set: { role: 'admin' } });

/** Verifies an account's e-mail address with the OTP sent at registration (`POST /auth/verify-email`). */
async function verifyEmail(account) {
  const otp = lastOtpFor(account.user.email);
  assert.ok(otp, 'verification code sent at registration');
  assertOk(await request.post(`${API}/auth/verify-email`).set(account.auth).send({ otp }));
}

/** Date of birth `years` (+ `extraDays`) ago as an ISO string, e.g. an age of exactly `years`. */
function yearsAgo(years, extraDays = 30) {
  const now = new Date();
  const d = new Date(Date.UTC(now.getUTCFullYear() - years, now.getUTCMonth(), now.getUTCDate()));
  return new Date(d.getTime() - extraDays * 24 * 60 * 60 * 1000).toISOString();
}

// ---------------------------------------------------------------- auth / permission matrix

describe('family routes: authentication and permissions', () => {
  const ROUTES = [
    ['post', FAMILY_URL],
    ['post', JOIN_URL],
    ['get', FAMILY_URL],
    ['patch', FAMILY_URL],
    ['post', INVITE_URL],
    ['get', MEMBERS_URL],
    ['post', MEMBERS_URL],
    ['get', memberUrl(OTHER_ID)],
    ['patch', memberUrl(OTHER_ID)],
    ['delete', memberUrl(OTHER_ID)],
  ];

  it('answers 401 UNAUTHORIZED on every route without a valid token', async () => {
    for (const [method, url] of ROUTES) {
      assertError(await request[method](url).send({}), 401, 'UNAUTHORIZED');
      assertError(await request[method](url).set(authHeader('not-a-jwt')).send({}), 401, 'UNAUTHORIZED');
    }
  });

  it('answers 403 NO_FAMILY on family routes to an account without a family', async () => {
    const loner = await userWithoutFamily();
    for (const [method, url] of ROUTES.slice(2)) {
      assertError(await request[method](url).set(loner.auth).send({}), 403, 'NO_FAMILY');
    }
  });

  it('answers 403 FORBIDDEN on admin-only routes to a member, and changes nothing', async () => {
    const { admin, member } = await familyOfTwo();
    const kid = await addManagedMember(admin.auth);
    const before = await Family.findById(admin.family.id).lean();

    assertError(await request.patch(FAMILY_URL).set(member.auth).send({ name: 'Hacked' }), 403, 'FORBIDDEN');
    assertError(await request.post(INVITE_URL).set(member.auth), 403, 'FORBIDDEN');
    assertError(await request.post(MEMBERS_URL).set(member.auth).send({ name: 'X' }), 403, 'FORBIDDEN');
    assertError(await request.delete(memberUrl(kid.id)).set(member.auth), 403, 'FORBIDDEN');

    const afterwards = await Family.findById(admin.family.id).lean();
    assert.equal(afterwards.name, before.name);
    assert.equal(afterwards.inviteCode, before.inviteCode);
    assert.equal(await Member.countDocuments({ familyId: admin.family.id }), 3);
  });

  it('never lets one family see or change another family (404 NOT_FOUND)', async () => {
    const a = await familyOfTwo();
    const b = await registerFamilyAdmin({ family: { name: 'Other Family' } });
    const target = a.member.member.id;

    assertError(await request.get(memberUrl(target)).set(b.auth), 404, 'NOT_FOUND');
    assertError(await request.patch(memberUrl(target)).set(b.auth).send({ name: 'Mine now' }), 404, 'NOT_FOUND');
    assertError(await request.delete(memberUrl(target)).set(b.auth), 404, 'NOT_FOUND');
    assertError(await request.patch(memberUrl(b.member.id)).set(a.member.auth).send({ name: 'X' }), 404, 'NOT_FOUND');

    const list = assertOk(await request.get(MEMBERS_URL).set(b.auth));
    assert.deepEqual(list.map((m) => m.id), [b.member.id]);
    const stored = await Member.findById(target).lean();
    assert.equal(stored.name, 'Priya Sharma');
  });
});

// ---------------------------------------------------------------- POST /family

describe('POST /family', () => {
  it('creates a family with the caller as its admin (201 { user, family, member })', async () => {
    const loner = await userWithoutFamily({ name: 'Amit Sharma' });
    const res = await request
      .post(FAMILY_URL)
      .set(loner.auth)
      .send({ name: '  Sharma Family ', country: 'in', currency: 'inr', timezone: 'Asia/Kolkata' });
    const data = assertOk(res, 201);
    assert.deepEqual(keysOf(data), ['family', 'member', 'user']);
    assert.deepEqual(keysOf(data.user), USER_KEYS);
    assertFamilyShape(data.family);
    assertMemberShape(data.member);

    assert.equal(data.family.name, 'Sharma Family');
    assert.equal(data.family.country, 'IN');
    assert.equal(data.family.currency, 'INR');
    assert.equal(data.family.timezone, 'Asia/Kolkata');
    assert.equal(data.family.ownerId, loner.user.id);
    assert.equal(data.family.memberCount, 1);
    assert.match(data.family.inviteCode, INVITE_CODE_REGEX);

    assert.equal(data.member.role, 'admin');
    assert.equal(data.member.designation, 'Head of Family');
    assert.equal(data.member.userId, loner.user.id);
    assert.equal(data.member.email, loner.user.email);
    assert.equal(data.member.name, 'Amit Sharma');
    assert.equal(data.member.hasAccount, true);
    assert.equal(data.member.locationSharing, 'never');

    assert.equal(data.user.familyId, data.family.id);
    assert.equal(data.user.memberId, data.member.id);
    assert.equal(data.user.role, 'admin');

    // The same access token now works on family routes (membership is read per request).
    const got = assertOk(await request.get(FAMILY_URL).set(loner.auth));
    assert.equal(got.family.id, data.family.id);
    assert.equal(got.family.inviteCode, data.family.inviteCode);
  });

  it('answers 409 ALREADY_IN_FAMILY to a member of a family and creates nothing', async () => {
    const { admin, member } = await familyOfTwo();
    const body = { name: 'Second', country: 'IN', currency: 'INR', timezone: 'Asia/Kolkata' };
    assertError(await request.post(FAMILY_URL).set(admin.auth).send(body), 409, 'ALREADY_IN_FAMILY');
    assertError(await request.post(FAMILY_URL).set(member.auth).send(body), 409, 'ALREADY_IN_FAMILY');
    assert.equal(await Family.countDocuments({}), 1);
    assert.equal(await Member.countDocuments({}), 2);
  });

  it('validates the body (422 with details per field, strict keys)', async () => {
    const loner = await userWithoutFamily();
    assertValidation(await request.post(FAMILY_URL).set(loner.auth).send({}), 'name', 'country', 'currency', 'timezone');
    assertValidation(
      await request
        .post(FAMILY_URL)
        .set(loner.auth)
        .send({ name: '   ', country: 'XX', currency: 'ABC', timezone: 'Mars/Olympus' }),
      'name',
      'country',
      'currency',
      'timezone',
    );
    const valid = { name: 'Fam', country: 'IN', currency: 'INR', timezone: 'Asia/Kolkata' };
    assertValidation(await request.post(FAMILY_URL).set(loner.auth).send({ ...valid, name: 'x'.repeat(61) }), 'name');
    assertValidation(await request.post(FAMILY_URL).set(loner.auth).send({ ...valid, name: 'Evil‮ylimaf' }), 'name');
    assertValidation(await request.post(FAMILY_URL).set(loner.auth).send({ ...valid, name: 'Line\nBreak' }), 'name');
    assertValidation(await request.post(FAMILY_URL).set(loner.auth).send({ ...valid, country: 123 }), 'country');
    assertValidation(await request.post(FAMILY_URL).set(loner.auth).send({ ...valid, inviteCode: 'AAAAAAAA' }));
    assertValidation(await request.post(FAMILY_URL).set(loner.auth).send({ ...valid, ownerId: OTHER_ID }));
    assert.equal(await Family.countDocuments({}), 0);
  });

  it('accepts time-zone aliases and spellings ICU knows, and rejects offsets and unknown zones', async () => {
    const cases = [
      ['Asia/Kolkata', 'Asia/Kolkata'], // alias of ICU's canonical Asia/Calcutta
      ['Asia/Calcutta', 'Asia/Calcutta'],
      ['utc', 'UTC'],
      ['Etc/UTC', 'UTC'],
      ['america/new_york', 'America/New_York'],
      ['  Europe/Berlin  ', 'Europe/Berlin'],
    ];
    for (const [input, stored] of cases) {
      const loner = await userWithoutFamily();
      const data = assertOk(
        await request.post(FAMILY_URL).set(loner.auth).send({ name: 'Fam', country: 'DE', currency: 'EUR', timezone: input }),
        201,
      );
      assert.equal(data.family.timezone, stored, input);
    }
    const loner = await userWithoutFamily();
    for (const bad of ['+05:30', 'UTC+5', 'Mars/Olympus', '', 'Asia/', 'x'.repeat(65), 42, null]) {
      assertValidation(
        await request.post(FAMILY_URL).set(loner.auth).send({ name: 'Fam', country: 'IN', currency: 'INR', timezone: bad }),
        'timezone',
      );
    }
    assert.equal(normalizeFamilyTimeZone('Asia/Kolkata'), 'Asia/Kolkata');
    assert.equal(normalizeFamilyTimeZone('../../etc/passwd'), null);
  });

  it('lets an account whose membership ended (removed or stale) create a new family', async () => {
    const { admin, member } = await familyOfTwo();
    assertOk(await request.delete(memberUrl(member.member.id)).set(admin.auth));
    const created = assertOk(
      await request.post(FAMILY_URL).set(member.auth).send({ name: 'New Home', country: 'IN', currency: 'INR', timezone: 'Asia/Kolkata' }),
      201,
    );
    assert.equal(created.member.role, 'admin');

    // Stale pointers (family gone, member row gone) count as "no family".
    const stale = await registerFamilyAdmin();
    await User.updateOne({ _id: stale.user.id }, { $set: { familyId: OTHER_ID, memberId: OTHER_ID } });
    await Member.deleteOne({ _id: stale.member.id });
    await Family.deleteOne({ _id: stale.family.id });
    assertOk(
      await request.post(FAMILY_URL).set(stale.auth).send({ name: 'Fresh', country: 'US', currency: 'USD', timezone: 'America/Chicago' }),
      201,
    );
  });
});

// ---------------------------------------------------------------- POST /family/join

describe('POST /family/join', () => {
  it('joins as a member with a code typed in any case, with spaces or dashes; admins get member_joined', async () => {
    const admin = await registerFamilyAdmin();
    const loner = await userWithoutFamily({ name: 'Ravi Kumar' });
    const code = admin.family.inviteCode;
    const typed = ` ${code.slice(0, 4).toLowerCase()}-${code.slice(4).toLowerCase()} `;

    const data = assertOk(await request.post(JOIN_URL).set(loner.auth).send({ inviteCode: typed }));
    assert.deepEqual(keysOf(data), ['family', 'member', 'user']);
    assertFamilyShape(data.family);
    assertMemberShape(data.member);
    assert.equal(data.family.id, admin.family.id);
    assert.equal(data.family.inviteCode, null, 'members never see the invite code');
    assert.equal(data.family.memberCount, 2);
    assert.equal(data.member.role, 'member');
    assert.equal(data.member.name, 'Ravi Kumar');
    assert.equal(data.member.userId, loner.user.id);
    assert.equal(data.user.familyId, admin.family.id);
    assert.equal(data.user.role, 'member');

    await flushPushes();
    const pushes = sentPushes.filter((p) => p.type === 'member_joined');
    assert.equal(pushes.length, 1);
    assert.deepEqual(pushes[0].requestedMemberIds, [admin.member.id]);
    assert.equal(pushes[0].id, data.member.id);
    assert.equal(pushes[0].route, `/members/${data.member.id}`);
    assert.equal(pushes[0].familyId, admin.family.id);
    assert.ok(hasTranslation(pushes[0].titleKey) && hasTranslation(pushes[0].bodyKey));
  });

  it('links the profile an admin pre-added with the same e-mail (keeps name, role, designation, consent)', async () => {
    const admin = await registerFamilyAdmin();
    const loner = await userWithoutFamily({ name: 'Priya S' });
    await verifyEmail(loner);
    const preAdded = assertOk(
      await request.post(MEMBERS_URL).set(admin.auth).send({
        name: 'Priya (Mom)',
        email: loner.user.email.toUpperCase(),
        designation: 'Finance Head',
        role: 'admin',
        dateOfBirth: '1988-03-10T00:00:00.000Z',
      }),
      201,
    );
    assert.equal(preAdded.hasAccount, false);

    const data = assertOk(await request.post(JOIN_URL).set(loner.auth).send({ inviteCode: admin.family.inviteCode }));
    assert.equal(data.member.id, preAdded.id);
    assert.equal(data.member.name, 'Priya (Mom)');
    assert.equal(data.member.designation, 'Finance Head');
    assert.equal(data.member.role, 'admin');
    assert.equal(data.member.hasAccount, true);
    assert.equal(data.member.userId, loner.user.id);
    assert.equal(data.family.inviteCode, admin.family.inviteCode, 'a linked admin sees the invite code');
    assert.equal(data.family.memberCount, 2, 'no duplicate member');
    assert.equal(data.user.role, 'admin');
  });

  it('answers 409 MEMBER_EMAIL_EXISTS when the profile with that e-mail already has an account', async () => {
    const admin = await registerFamilyAdmin();
    const loner = await userWithoutFamily();
    const someoneElse = await userWithoutFamily();
    await Member.create({ familyId: admin.family.id, name: 'Taken', email: loner.user.email, userId: someoneElse.user.id });

    assertError(await request.post(JOIN_URL).set(loner.auth).send({ inviteCode: admin.family.inviteCode }), 409, 'MEMBER_EMAIL_EXISTS');
    const user = await User.findById(loner.user.id).lean();
    assert.equal(user.familyId, null);
  });

  it('answers 409 ALREADY_IN_FAMILY to anyone who already is in a family', async () => {
    const { admin, member } = await familyOfTwo();
    const other = await registerFamilyAdmin();
    assertError(await request.post(JOIN_URL).set(member.auth).send({ inviteCode: other.family.inviteCode }), 409, 'ALREADY_IN_FAMILY');
    assertError(await request.post(JOIN_URL).set(admin.auth).send({ inviteCode: admin.family.inviteCode }), 409, 'ALREADY_IN_FAMILY');
    assert.equal(await Member.countDocuments({ familyId: other.family.id }), 1);
  });

  it('answers 400 INVALID_INVITE_CODE for an unknown code and for a code that was replaced', async () => {
    const admin = await registerFamilyAdmin();
    const loner = await userWithoutFamily();
    assertError(await request.post(JOIN_URL).set(loner.auth).send({ inviteCode: 'ZZZZZZZZ' }), 400, 'INVALID_INVITE_CODE');

    const oldCode = admin.family.inviteCode;
    assertOk(await request.post(INVITE_URL).set(admin.auth));
    assertError(await request.post(JOIN_URL).set(loner.auth).send({ inviteCode: oldCode }), 400, 'INVALID_INVITE_CODE');
    assert.equal(await Member.countDocuments({ familyId: admin.family.id }), 1);
  });

  it('validates the code format (422)', async () => {
    const loner = await userWithoutFamily();
    assertValidation(await request.post(JOIN_URL).set(loner.auth).send({}), 'inviteCode');
    assertValidation(await request.post(JOIN_URL).set(loner.auth).send({ inviteCode: 'ABC' }), 'inviteCode');
    assertValidation(await request.post(JOIN_URL).set(loner.auth).send({ inviteCode: 12345678 }), 'inviteCode');
    assertValidation(await request.post(JOIN_URL).set(loner.auth).send({ inviteCode: { $ne: null } }), 'inviteCode');
    assertValidation(await request.post(JOIN_URL).set(loner.auth).send({ inviteCode: 'ABCDEFGH', role: 'admin' }));
  });

  it('answers 422 GUARDIAN_CONSENT_REQUIRED when linking to a pre-added minor profile without consent', async () => {
    const admin = await registerFamilyAdmin();
    const loner = await userWithoutFamily();
    await verifyEmail(loner);
    const kid = await Member.create({
      familyId: admin.family.id,
      name: 'Kid',
      email: loner.user.email,
      dateOfBirth: yearsAgo(12),
      guardianConsent: false,
    });
    assertError(await request.post(JOIN_URL).set(loner.auth).send({ inviteCode: admin.family.inviteCode }), 422, 'GUARDIAN_CONSENT_REQUIRED');
    assert.equal((await Member.findById(kid._id).lean()).userId, null);

    await Member.updateOne({ _id: kid._id }, { $set: { guardianConsent: true } });
    const data = assertOk(await request.post(JOIN_URL).set(loner.auth).send({ inviteCode: admin.family.inviteCode }));
    assert.equal(data.member.id, String(kid._id));
    assert.equal(data.member.guardianConsent, true);
  });
});

// ---------------------------------------------------------------- GET /family

describe('GET /family', () => {
  it('returns { family } with the invite code for admins only and a computed member count', async () => {
    const { admin, member } = await familyOfTwo();
    await addManagedMember(admin.auth);

    const asAdmin = assertOk(await request.get(FAMILY_URL).set(admin.auth));
    assert.deepEqual(keysOf(asAdmin), ['family']);
    assertFamilyShape(asAdmin.family);
    assert.equal(asAdmin.family.inviteCode, admin.family.inviteCode);
    assert.equal(asAdmin.family.memberCount, 3, 'managed profiles count');
    assert.equal(asAdmin.family.ownerId, admin.user.id);

    const asMember = assertOk(await request.get(FAMILY_URL).set(member.auth));
    assert.equal(asMember.family.inviteCode, null);
    assert.equal(asMember.family.memberCount, 3);
    assert.deepEqual({ ...asMember.family, inviteCode: asAdmin.family.inviteCode }, asAdmin.family);
  });

  it('shows each caller only their own family', async () => {
    const a = await registerFamilyAdmin({ family: { name: 'Family A' } });
    const b = await registerFamilyAdmin({ family: { name: 'Family B', country: 'US', currency: 'USD', timezone: 'America/New_York' } });
    assert.equal(assertOk(await request.get(FAMILY_URL).set(a.auth)).family.name, 'Family A');
    const got = assertOk(await request.get(FAMILY_URL).set(b.auth)).family;
    assert.equal(got.name, 'Family B');
    assert.equal(got.currency, 'USD');
  });
});

// ---------------------------------------------------------------- PATCH /family

describe('PATCH /family', () => {
  it('lets an admin change name, country, currency and time zone', async () => {
    const admin = await registerFamilyAdmin();
    const data = assertOk(
      await request
        .patch(FAMILY_URL)
        .set(admin.auth)
        .send({ name: ' The Sharmas ', country: 'ae', currency: 'aed', timezone: 'Asia/Dubai' }),
    );
    assert.deepEqual(keysOf(data), ['family']);
    assertFamilyShape(data.family);
    assert.equal(data.family.name, 'The Sharmas');
    assert.equal(data.family.country, 'AE');
    assert.equal(data.family.currency, 'AED');
    assert.equal(data.family.timezone, 'Asia/Dubai');
    assert.equal(data.family.inviteCode, admin.family.inviteCode);
    const stored = await Family.findById(admin.family.id).lean();
    assert.equal(stored.country, 'AE');

    // A family may keep a currency that is not its country's (expats).
    const partial = assertOk(await request.patch(FAMILY_URL).set(admin.auth).send({ currency: 'INR' }));
    assert.equal(partial.family.currency, 'INR');
    assert.equal(partial.family.country, 'AE');
  });

  it('returns the family unchanged for an empty body', async () => {
    const admin = await registerFamilyAdmin();
    const before = await Family.findById(admin.family.id).lean();
    const data = assertOk(await request.patch(FAMILY_URL).set(admin.auth).send({}));
    assert.equal(data.family.name, 'Sharma Family');
    const afterwards = await Family.findById(admin.family.id).lean();
    assert.equal(afterwards.updatedAt.getTime(), before.updatedAt.getTime());
  });

  it('validates every field (422 details) and rejects keys it cannot change', async () => {
    const admin = await registerFamilyAdmin();
    assertValidation(
      await request.patch(FAMILY_URL).set(admin.auth).send({ name: '', country: 'XX', currency: 'ABC', timezone: '+05:30' }),
      'name',
      'country',
      'currency',
      'timezone',
    );
    assertValidation(await request.patch(FAMILY_URL).set(admin.auth).send({ name: null }), 'name');
    assertValidation(await request.patch(FAMILY_URL).set(admin.auth).send({ inviteCode: 'AAAAAAAA' }));
    assertValidation(await request.patch(FAMILY_URL).set(admin.auth).send({ ownerId: OTHER_ID }));
    const stored = await Family.findById(admin.family.id).lean();
    assert.equal(stored.name, 'Sharma Family');
    assert.equal(stored.inviteCode, admin.family.inviteCode);
  });

  it('refuses a country change that would leave minors without guardian consent (GAP-05)', async () => {
    const admin = await registerFamilyAdmin({ family: { country: 'US', currency: 'USD', timezone: 'America/New_York' } });
    // 15 is an adult for consent purposes in the US (13) but a minor in India (18).
    const teen = await addManagedMember(admin.auth, { name: 'Teen', dateOfBirth: yearsAgo(15), guardianConsent: false });
    assert.equal(teen.guardianConsent, false);
    await addManagedMember(admin.auth, { name: 'Kid', dateOfBirth: yearsAgo(8), guardianConsent: true });

    const error = assertError(await request.patch(FAMILY_URL).set(admin.auth).send({ country: 'IN' }), 422, 'GUARDIAN_CONSENT_REQUIRED');
    assert.deepEqual(error.details.memberIds, [teen.id]);
    assert.equal(error.details.consentAge, consentAge('IN'));
    assert.equal(typeof error.details.country, 'string');
    assert.equal((await Family.findById(admin.family.id).lean()).country, 'US');

    assertOk(await request.patch(memberUrl(teen.id)).set(admin.auth).send({ guardianConsent: true }));
    const data = assertOk(await request.patch(FAMILY_URL).set(admin.auth).send({ country: 'IN', timezone: 'Asia/Kolkata' }));
    assert.equal(data.family.country, 'IN');
  });
});

// ---------------------------------------------------------------- POST /family/invite-code

describe('POST /family/invite-code', () => {
  it('replaces the code: the new one works, the old one stops working', async () => {
    const admin = await registerFamilyAdmin();
    const oldCode = admin.family.inviteCode;
    const data = assertOk(await request.post(INVITE_URL).set(admin.auth));
    assert.deepEqual(keysOf(data), ['family']);
    assertFamilyShape(data.family);
    assert.notEqual(data.family.inviteCode, oldCode);
    assert.match(data.family.inviteCode, INVITE_CODE_REGEX);
    assert.doesNotMatch(data.family.inviteCode, /[01OI]/);
    assert.equal(assertOk(await request.get(FAMILY_URL).set(admin.auth)).family.inviteCode, data.family.inviteCode);

    const loner = await userWithoutFamily();
    assertError(await request.post(JOIN_URL).set(loner.auth).send({ inviteCode: oldCode }), 400, 'INVALID_INVITE_CODE');
    assertOk(await request.post(JOIN_URL).set(loner.auth).send({ inviteCode: data.family.inviteCode.toLowerCase() }));
  });

  it('regenerates when a new code is already used by another family', async () => {
    const admin = await registerFamilyAdmin();
    const other = await registerFamilyAdmin();
    const codes = [admin.family.inviteCode, other.family.inviteCode, 'QRST2345'];
    const data = await familyService.regenerateInviteCode(
      { id: admin.user.id, familyId: admin.family.id, memberId: admin.member.id, role: 'admin' },
      { generateCode: () => codes.shift() },
    );
    assert.equal(data.family.inviteCode, 'QRST2345');
    assert.equal((await Family.findById(other.family.id).lean()).inviteCode, other.family.inviteCode);

    await assert.rejects(
      familyService.regenerateInviteCode(
        { id: admin.user.id, familyId: admin.family.id, memberId: admin.member.id, role: 'admin' },
        { generateCode: () => other.family.inviteCode },
      ),
      (err) => err.code === 'INTERNAL_ERROR',
    );
  });
});

// ---------------------------------------------------------------- GET /family/members

describe('GET /family/members', () => {
  it('lists admins first, then oldest → youngest, unknown date of birth last', async () => {
    const admin = await registerFamilyAdmin({ dateOfBirth: '1985-02-01T00:00:00.000Z' });
    const member = await joinFamilyAs(admin.family.inviteCode, { dateOfBirth: '1990-06-15T00:00:00.000Z' });
    const secondAdmin = await joinFamilyAs(admin.family.inviteCode, { name: 'Vikram', dateOfBirth: '1995-01-01T00:00:00.000Z' });
    await promote(secondAdmin.member.id);
    const kid = await addManagedMember(admin.auth, { name: 'Kid', dateOfBirth: '2016-08-01T00:00:00.000Z' });
    const elder = await addManagedMember(admin.auth, { name: 'Dadi', dateOfBirth: '1950-04-04T00:00:00.000Z', guardianConsent: false });
    const unknown = await addManagedMember(admin.auth, { name: 'Unknown', dateOfBirth: null, guardianConsent: false });

    const list = assertOk(await request.get(MEMBERS_URL).set(member.auth));
    assert.ok(Array.isArray(list));
    list.forEach(assertMemberShape);
    assert.deepEqual(
      list.map((m) => m.id),
      [admin.member.id, secondAdmin.member.id, elder.id, member.member.id, kid.id, unknown.id],
    );
  });

  it('applies the location privacy rule and never lists another family', async () => {
    const { admin, member } = await familyOfTwo();
    const point = { lat: 28.61, lng: 77.2, accuracy: 12.5, recordedAt: new Date() };
    await Member.updateOne({ _id: member.member.id }, { $set: { locationSharing: 'always', lastLocation: point } });
    await Member.updateOne({ _id: admin.member.id }, { $set: { locationSharing: 'sos_only', lastLocation: point } });
    await registerFamilyAdmin({ family: { name: 'Strangers' } });

    const list = assertOk(await request.get(MEMBERS_URL).set(admin.auth));
    assert.equal(list.length, 2);
    const byId = Object.fromEntries(list.map((m) => [m.id, m]));
    assert.equal(byId[member.member.id].lastLocation.lat, 28.61);
    assert.match(byId[member.member.id].lastLocation.recordedAt, ISO);
    assert.equal(byId[admin.member.id].lastLocation, null);
  });
});

// ---------------------------------------------------------------- POST /family/members

describe('POST /family/members', () => {
  it('adds a managed profile (201 Member) and records who confirmed guardian consent', async () => {
    const admin = await registerFamilyAdmin();
    const res = await request.post(MEMBERS_URL).set(admin.auth).send({
      name: ' Anaya ',
      email: null,
      phone: '+91 98765-43210',
      dateOfBirth: '2016-08-01T00:00:00.000Z',
      gender: 'female',
      designation: 'Junior Explorer',
      role: 'member',
      guardianConsent: true,
    });
    const member = assertMemberShape(assertOk(res, 201));
    assert.equal(member.name, 'Anaya');
    assert.equal(member.phone, '+919876543210');
    assert.equal(member.dateOfBirth, '2016-08-01T00:00:00.000Z');
    assert.equal(member.gender, 'female');
    assert.equal(member.designation, 'Junior Explorer');
    assert.equal(member.role, 'member');
    assert.equal(member.userId, null);
    assert.equal(member.hasAccount, false);
    assert.equal(member.email, null);
    assert.equal(member.guardianConsent, true);
    assert.equal(member.locationSharing, 'never');
    assert.equal(member.lastLocation, null);
    assert.equal(member.familyId, admin.family.id);

    const stored = await Member.findById(member.id).lean();
    assert.equal(String(stored.guardianConsentById), admin.member.id);
    assert.ok(stored.guardianConsentAt instanceof Date);
    assert.equal(outbox.length, 1, 'only the admin verification e-mail, no invitation without e-mail');
    await flushPushes();
    assert.equal(sentPushes.length, 0);
  });

  it('defaults to role member without consent for an adult, and accepts managed admins and a Cloudinary photo', async () => {
    const admin = await registerFamilyAdmin();
    const adult = assertOk(await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'Nana', dateOfBirth: '1948-01-01' }), 201);
    assert.equal(adult.role, 'member');
    assert.equal(adult.guardianConsent, false);
    assert.equal(adult.designation, null);
    const stored = await Member.findById(adult.id).lean();
    assert.equal(stored.guardianConsentAt, null);
    assert.equal(stored.guardianConsentById, null);

    const managedAdmin = assertOk(
      await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'Uncle', role: 'admin', avatarUrl: CLOUD_URL, designation: '  ' }),
      201,
    );
    assert.equal(managedAdmin.role, 'admin');
    assert.equal(managedAdmin.avatarUrl, CLOUD_URL);
    assert.equal(managedAdmin.designation, null);
  });

  it('e-mails an invitation with the invite code in the family creator\'s language', async () => {
    const owner = await registerFamilyAdmin({ locale: 'hi' });
    const coAdmin = await joinFamilyAs(owner.family.inviteCode, { name: 'Carlos', locale: 'es' });
    await promote(coAdmin.member.id);
    const email = uniqueEmail('invitee');

    const member = assertOk(
      await request.post(MEMBERS_URL).set(coAdmin.auth).send({ name: 'Meera', email: `  ${email.toUpperCase()} ` }),
      201,
    );
    assert.equal(member.email, email);
    assert.equal(member.hasAccount, false);

    const mail = lastMailTo(email);
    assert.ok(mail, 'invitation sent');
    assert.equal(mail.template, 'family.invite');
    assert.equal(mail.locale, 'hi');
    assert.equal(mail.vars.inviteCode, owner.family.inviteCode);
    assert.equal(mail.vars.familyName, 'Sharma Family');
    assert.equal(mail.vars.inviterName, 'Carlos');
    assert.ok(mail.text.includes(owner.family.inviteCode));
    assert.ok(mail.text.includes('Meera'));
    assert.ok(mail.subject.length > 0 && !mail.subject.includes('{'));
  });

  it('answers 409 MEMBER_EMAIL_EXISTS for an e-mail already used in the family (any case)', async () => {
    const { admin, member } = await familyOfTwo();
    const email = uniqueEmail('dup');
    assertOk(await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'First', email }), 201);
    assertError(await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'Second', email: email.toUpperCase() }), 409, 'MEMBER_EMAIL_EXISTS');
    assertError(await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'Me', email: admin.user.email }), 409, 'MEMBER_EMAIL_EXISTS');
    assertError(await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'Her', email: member.user.email }), 409, 'MEMBER_EMAIL_EXISTS');
    assert.equal(await Member.countDocuments({ familyId: admin.family.id }), 3);

    // Another family may use the same address.
    const other = await registerFamilyAdmin();
    assertOk(await request.post(MEMBERS_URL).set(other.auth).send({ name: 'Elsewhere', email }), 201);
  });

  it('requires guardian consent below the country consent age (422 GUARDIAN_CONSENT_REQUIRED)', async () => {
    const admin = await registerFamilyAdmin(); // IN → 18
    for (const guardianConsent of [undefined, false, null]) {
      const error = assertError(
        await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'Kid', dateOfBirth: yearsAgo(9), guardianConsent }),
        422,
        'GUARDIAN_CONSENT_REQUIRED',
      );
      assert.equal(error.details.consentAge, 18);
      assert.equal(typeof error.details.guardianConsent, 'string');
    }
    assertError(await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'Teen', dateOfBirth: yearsAgo(17) }), 422, 'GUARDIAN_CONSENT_REQUIRED');
    assert.equal(await Member.countDocuments({ familyId: admin.family.id }), 1);

    assertOk(await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'No DOB' }), 201);
    const us = await registerFamilyAdmin({ family: { country: 'US', currency: 'USD', timezone: 'America/New_York' } });
    assertOk(await request.post(MEMBERS_URL).set(us.auth).send({ name: 'Teen', dateOfBirth: yearsAgo(15) }), 201);
    assertError(await request.post(MEMBERS_URL).set(us.auth).send({ name: 'Kid', dateOfBirth: yearsAgo(12) }), 422, 'GUARDIAN_CONSENT_REQUIRED');
  });

  it('computes the age at the family\'s local birthday boundary', async (t) => {
    const tz = 'Asia/Kolkata';
    const today = zonedParts(new Date(), tz);
    if (today.month === 2 && today.day >= 28) return t.skip('leap-day boundary');
    const admin = await registerFamilyAdmin();
    const eighteenToday = zonedTimeToUtc({ year: today.year - 18, month: today.month, day: today.day }, tz).toISOString();
    const eighteenTomorrow = zonedTimeToUtc({ year: today.year - 18, month: today.month, day: today.day + 1 }, tz).toISOString();
    assertOk(await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'Birthday', dateOfBirth: eighteenToday }), 201);
    assertError(
      await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'Almost', dateOfBirth: eighteenTomorrow }),
      422,
      'GUARDIAN_CONSENT_REQUIRED',
    );
  });

  it('validates the body (422 details, strict keys) and creates nothing', async () => {
    const admin = await registerFamilyAdmin();
    const send = (body) => request.post(MEMBERS_URL).set(admin.auth).send(body);
    assertValidation(await send({}), 'name');
    assertValidation(await send({ name: '   ' }), 'name');
    assertValidation(await send({ name: '​' }), 'name');
    assertValidation(await send({ name: 'A', email: 'not-an-email' }), 'email');
    assertValidation(await send({ name: 'A', phone: '12' }), 'phone');
    assertValidation(await send({ name: 'A', dateOfBirth: '2999-01-01T00:00:00.000Z' }), 'dateOfBirth');
    assertValidation(await send({ name: 'A', dateOfBirth: '1850-01-01' }), 'dateOfBirth');
    assertValidation(await send({ name: 'A', dateOfBirth: '01/02/2010' }), 'dateOfBirth');
    assertValidation(await send({ name: 'A', gender: 'robot' }), 'gender');
    assertValidation(await send({ name: 'A', role: 'owner' }), 'role');
    assertValidation(await send({ name: 'A', guardianConsent: 'yes' }), 'guardianConsent');
    assertValidation(await send({ name: 'A', designation: 'x'.repeat(81) }), 'designation');
    assertValidation(await send({ name: 'A', designation: 'Chief\nOfficer' }), 'designation');
    assertValidation(await send({ name: 'A', avatarUrl: 'https://evil.example.com/a.png' }), 'avatarUrl');
    assertValidation(await send({ name: 'A', userId: admin.user.id }));
    assertValidation(await send({ name: 'A', locationSharing: 'always' }));
    assertValidation(await send({ name: { $gt: '' } }), 'name');
    assert.equal(await Member.countDocuments({ familyId: admin.family.id }), 1);
  });
});

// ---------------------------------------------------------------- GET /family/members/:id

describe('GET /family/members/:id', () => {
  it('returns any member of the caller\'s family; unknown → 404, malformed → 400', async () => {
    const { admin, member } = await familyOfTwo();
    const kid = await addManagedMember(admin.auth);

    const got = assertMemberShape(assertOk(await request.get(memberUrl(kid.id)).set(member.auth)));
    assert.equal(got.name, 'Anaya');
    assert.equal(got.guardianConsent, true);
    const self = assertOk(await request.get(memberUrl(admin.member.id)).set(admin.auth));
    assert.equal(self.role, 'admin');

    assertError(await request.get(memberUrl(OTHER_ID)).set(member.auth), 404, 'NOT_FOUND');
    assertError(await request.get(memberUrl('not-an-id')).set(member.auth), 400, 'BAD_REQUEST');
  });
});

// ---------------------------------------------------------------- PATCH /family/members/:id

describe('PATCH /family/members/:id', () => {
  it('lets an admin change every field of a managed profile and clear optional ones', async () => {
    const admin = await registerFamilyAdmin();
    const kid = await addManagedMember(admin.auth, { guardianConsent: true });
    const email = uniqueEmail('kid');

    const data = assertMemberShape(
      assertOk(
        await request.patch(memberUrl(kid.id)).set(admin.auth).send({
          name: 'Anaya S',
          email,
          phone: '+911234567890',
          avatarUrl: CLOUD_URL,
          dateOfBirth: '2012-02-02T00:00:00.000Z',
          gender: 'other',
          designation: 'Chief Fun Officer',
          role: 'admin',
          guardianConsent: true,
        }),
      ),
    );
    assert.equal(data.name, 'Anaya S');
    assert.equal(data.email, email);
    assert.equal(data.phone, '+911234567890');
    assert.equal(data.avatarUrl, CLOUD_URL);
    assert.equal(data.dateOfBirth, '2012-02-02T00:00:00.000Z');
    assert.equal(data.gender, 'other');
    assert.equal(data.designation, 'Chief Fun Officer');
    assert.equal(data.role, 'admin');

    const cleared = assertOk(
      await request
        .patch(memberUrl(kid.id))
        .set(admin.auth)
        .send({ email: null, phone: null, avatarUrl: '', gender: null, designation: null, dateOfBirth: null }),
    );
    for (const field of ['email', 'phone', 'avatarUrl', 'gender', 'designation', 'dateOfBirth']) assert.equal(cleared[field], null, field);
  });

  it('records and withdraws guardian consent with who confirmed it', async () => {
    const { admin } = await familyOfTwo();
    const adult = await addManagedMember(admin.auth, { name: 'Nana', dateOfBirth: '1950-01-01T00:00:00.000Z', guardianConsent: false });
    assertOk(await request.patch(memberUrl(adult.id)).set(admin.auth).send({ guardianConsent: true }));
    let stored = await Member.findById(adult.id).lean();
    assert.equal(stored.guardianConsent, true);
    assert.equal(String(stored.guardianConsentById), admin.member.id);
    assert.ok(stored.guardianConsentAt instanceof Date);

    assertOk(await request.patch(memberUrl(adult.id)).set(admin.auth).send({ guardianConsent: false }));
    stored = await Member.findById(adult.id).lean();
    assert.equal(stored.guardianConsent, false);
    assert.equal(stored.guardianConsentAt, null);
    assert.equal(stored.guardianConsentById, null);
  });

  it('lets an admin promote a member, who then sees the invite code', async () => {
    const { admin, member } = await familyOfTwo();
    assert.equal(assertOk(await request.get(FAMILY_URL).set(member.auth)).family.inviteCode, null);
    const data = assertOk(await request.patch(memberUrl(member.member.id)).set(admin.auth).send({ role: 'admin' }));
    assert.equal(data.role, 'admin');
    assert.equal(assertOk(await request.get(FAMILY_URL).set(member.auth)).family.inviteCode, admin.family.inviteCode);
    assert.equal(assertOk(await request.get(`${API}/auth/me`).set(member.auth)).user.role, 'admin');
  });

  it('answers 409 LAST_ADMIN when demoting the last admin who can sign in', async () => {
    const { admin, member } = await familyOfTwo();
    assertError(await request.patch(memberUrl(admin.member.id)).set(admin.auth).send({ role: 'member' }), 409, 'LAST_ADMIN');
    // A managed profile with the admin role cannot sign in, so it does not count.
    await addManagedMember(admin.auth, { name: 'Uncle', role: 'admin', dateOfBirth: null, guardianConsent: false });
    assertError(
      await request.patch(memberUrl(admin.member.id)).set(admin.auth).send({ role: 'member', designation: 'Advisor' }),
      409,
      'LAST_ADMIN',
    );
    const stored = await Member.findById(admin.member.id).lean();
    assert.equal(stored.role, 'admin');
    assert.equal(stored.designation, 'Head of Family', 'nothing of the request was written');

    await promote(member.member.id);
    const data = assertOk(await request.patch(memberUrl(admin.member.id)).set(admin.auth).send({ role: 'member', designation: 'Advisor' }));
    assert.equal(data.role, 'member');
    assert.equal(data.designation, 'Advisor');
    assert.equal(assertOk(await request.get(FAMILY_URL).set(admin.auth)).family.inviteCode, null);
    assertError(await request.patch(FAMILY_URL).set(admin.auth).send({ name: 'X' }), 403, 'FORBIDDEN');
  });

  it('lets an admin demote another admin', async () => {
    const { admin, member } = await familyOfTwo();
    await promote(member.member.id);
    const data = assertOk(await request.patch(memberUrl(member.member.id)).set(admin.auth).send({ role: 'member' }));
    assert.equal(data.role, 'member');
    assert.equal(await Member.countDocuments({ familyId: admin.family.id, role: 'admin' }), 1);
  });

  it('never leaves the family without an admin when two admins demote each other at once', async () => {
    const { admin, member } = await familyOfTwo();
    await promote(member.member.id);
    const [a, b] = await Promise.all([
      request.patch(memberUrl(member.member.id)).set(admin.auth).send({ role: 'member' }),
      request.patch(memberUrl(admin.member.id)).set(member.auth).send({ role: 'member' }),
    ]);
    const statuses = [a.status, b.status].sort();
    assert.ok(statuses.every((s) => s === 200 || s === 409), JSON.stringify(statuses));
    assert.ok(statuses.includes(200));
    const admins = await Member.countDocuments({ familyId: admin.family.id, role: 'admin', userId: { $type: 'objectId' } });
    assert.ok(admins >= 1, 'at least one admin with an account remains');
  });

  it('lets a member change their own name, phone, photo, gender and date of birth (and account name)', async () => {
    const { member } = await familyOfTwo();
    const data = assertOk(
      await request.patch(memberUrl(member.member.id)).set(member.auth).send({
        name: 'Priya Verma',
        phone: '+919999999999',
        avatarUrl: CLOUD_URL,
        gender: 'female',
        dateOfBirth: '1991-07-07T00:00:00.000Z',
      }),
    );
    assert.equal(data.name, 'Priya Verma');
    assert.equal(data.phone, '+919999999999');
    assert.equal(data.dateOfBirth, '1991-07-07T00:00:00.000Z');
    const me = assertOk(await request.get(`${API}/auth/me`).set(member.auth));
    assert.equal(me.user.name, 'Priya Verma', 'the account is renamed too');
  });

  it('answers 403 FORBIDDEN to a member editing someone else or a field only admins may change', async () => {
    const { admin, member } = await familyOfTwo();
    const kid = await addManagedMember(admin.auth);
    assertError(await request.patch(memberUrl(kid.id)).set(member.auth).send({ name: 'X' }), 403, 'FORBIDDEN');
    assertError(await request.patch(memberUrl(admin.member.id)).set(member.auth).send({ phone: '+911111111111' }), 403, 'FORBIDDEN');

    for (const body of [{ role: 'admin' }, { designation: 'CEO' }, { email: uniqueEmail() }, { guardianConsent: true }, { name: 'Ok', role: 'member' }]) {
      const error = assertError(await request.patch(memberUrl(member.member.id)).set(member.auth).send(body), 403, 'FORBIDDEN');
      const denied = Object.keys(body).filter((k) => k !== 'name');
      assert.deepEqual(Object.keys(error.details).sort(), denied.sort());
    }
    const stored = await Member.findById(member.member.id).lean();
    assert.equal(stored.role, 'member');
    assert.equal(stored.name, 'Priya Sharma');
    assert.equal(stored.designation, null);
  });

  it('keeps the sign-in e-mail of a member with an account (422), and allows the same address in any case', async () => {
    const { admin, member } = await familyOfTwo();
    assertValidation(await request.patch(memberUrl(member.member.id)).set(admin.auth).send({ email: uniqueEmail() }), 'email');
    assertValidation(await request.patch(memberUrl(member.member.id)).set(admin.auth).send({ email: null }), 'email');
    const same = assertOk(
      await request.patch(memberUrl(member.member.id)).set(admin.auth).send({ email: member.user.email.toUpperCase(), designation: 'CFO' }),
    );
    assert.equal(same.email, member.user.email);
    assert.equal(same.designation, 'CFO');
  });

  it('invites a managed profile that gets a new e-mail; a taken address → 409 MEMBER_EMAIL_EXISTS', async () => {
    const { admin, member } = await familyOfTwo();
    const kid = await addManagedMember(admin.auth);
    const email = uniqueEmail('kid');
    assertOk(await request.patch(memberUrl(kid.id)).set(admin.auth).send({ email }));
    const mail = lastMailTo(email);
    assert.equal(mail?.template, 'family.invite');
    assert.equal(mail.vars.inviteCode, admin.family.inviteCode);

    const sent = outbox.length;
    assertOk(await request.patch(memberUrl(kid.id)).set(admin.auth).send({ email: email.toUpperCase() }));
    assert.equal(outbox.length, sent, 'unchanged address → no second invitation');

    assertError(await request.patch(memberUrl(kid.id)).set(admin.auth).send({ email: member.user.email }), 409, 'MEMBER_EMAIL_EXISTS');
    assert.equal((await Member.findById(kid.id).lean()).email, email);
  });

  it('requires guardian consent when a date of birth change makes a member a minor (GAP-05)', async () => {
    const { admin, member } = await familyOfTwo();
    const adult = await addManagedMember(admin.auth, { name: 'Ravi', dateOfBirth: '1980-01-01T00:00:00.000Z', guardianConsent: false });

    const error = assertError(
      await request.patch(memberUrl(adult.id)).set(admin.auth).send({ dateOfBirth: yearsAgo(10) }),
      422,
      'GUARDIAN_CONSENT_REQUIRED',
    );
    assert.deepEqual(error.details.memberIds, [adult.id]);
    assert.equal((await Member.findById(adult.id).lean()).dateOfBirth.toISOString(), '1980-01-01T00:00:00.000Z');

    const data = assertOk(await request.patch(memberUrl(adult.id)).set(admin.auth).send({ dateOfBirth: yearsAgo(10), guardianConsent: true }));
    assert.equal(data.guardianConsent, true);
    assert.equal(String((await Member.findById(adult.id).lean()).guardianConsentById), admin.member.id);

    // Withdrawing consent of a minor is refused as well.
    assertError(await request.patch(memberUrl(adult.id)).set(admin.auth).send({ guardianConsent: false }), 422, 'GUARDIAN_CONSENT_REQUIRED');
    // A member cannot make themselves a minor without recorded consent.
    assertError(
      await request.patch(memberUrl(member.member.id)).set(member.auth).send({ dateOfBirth: yearsAgo(14) }),
      422,
      'GUARDIAN_CONSENT_REQUIRED',
    );
    // Other edits of a consented minor are fine.
    assertOk(await request.patch(memberUrl(adult.id)).set(admin.auth).send({ name: 'Ravi Jr' }));
  });

  it('validates the body (422, strict keys; name, role and consent cannot be null) and accepts {}', async () => {
    const { admin, member } = await familyOfTwo();
    const id = member.member.id;
    const send = (body) => request.patch(memberUrl(id)).set(admin.auth).send(body);
    assertValidation(await send({ locationSharing: 'always' }));
    assertValidation(await send({ userId: admin.user.id }));
    assertValidation(await send({ familyId: OTHER_ID }));
    assertValidation(await send({ name: null }), 'name');
    assertValidation(await send({ name: '' }), 'name');
    assertValidation(await send({ role: null }), 'role');
    assertValidation(await send({ role: 'owner' }), 'role');
    assertValidation(await send({ guardianConsent: null }), 'guardianConsent');
    assertValidation(await send({ phone: 'call me' }), 'phone');
    assertValidation(await send({ avatarUrl: 'http://res.cloudinary.com/x.png' }), 'avatarUrl');
    assertError(await request.patch(memberUrl('nope')).set(admin.auth).send({ name: 'X' }), 400, 'BAD_REQUEST');

    const before = await Member.findById(id).lean();
    const same = assertOk(await send({}));
    assert.equal(same.name, 'Priya Sharma');
    assert.equal((await Member.findById(id).lean()).updatedAt.getTime(), before.updatedAt.getTime());
  });
});

// ---------------------------------------------------------------- DELETE /family/members/:id

describe('DELETE /family/members/:id', () => {
  it('removes a member with an account and runs the cascade (contract §6)', async () => {
    const { admin, member, familyId } = await familyOfTwo();
    const memberId = member.member.id;
    const now = Date.now();
    await Task.create([
      { familyId, title: 'Pending', assigneeId: memberId, createdById: admin.member.id },
      { familyId, title: 'Done', assigneeId: memberId, createdById: admin.member.id, status: 'done', completedAt: new Date(), completedById: memberId },
    ]);
    await LedgerEntry.create({
      familyId,
      type: 'expense',
      amountMinor: 12_050,
      category: 'groceries',
      date: new Date(),
      memberId,
      memberName: 'Priya Sharma',
      createdById: memberId,
    });
    const sos = await SosAlert.create({ familyId, memberId, startedAt: new Date(now), expiresAt: new Date(now + 15 * 60 * 1000) });
    await new EmergencyCard({ familyId, memberId, bloodGroup: 'B+' }).save();
    await Device.create({ userId: member.user.id, token: 'device-token-1', platform: 'android' });
    assert.ok((await RefreshToken.countDocuments({ userId: member.user.id })) > 0);

    const res = await request.delete(memberUrl(memberId)).set(admin.auth);
    assert.equal(assertOk(res), null);

    assert.equal(await Member.exists({ _id: memberId }), null);
    const user = await User.findById(member.user.id).lean();
    assert.equal(user.familyId, null);
    assert.equal(user.memberId, null);
    assert.equal(await RefreshToken.countDocuments({ userId: member.user.id }), 0, 'signed out everywhere');
    assert.equal(await Device.countDocuments({ userId: member.user.id }), 0);
    assert.deepEqual((await Task.find({ familyId }).lean()).map((task) => task.title), ['Done']);
    assert.equal(await EmergencyCard.countDocuments({ memberId }), 0);
    const resolved = await SosAlert.findById(sos._id).lean();
    assert.equal(resolved.status, 'resolved');
    assert.equal(String(resolved.resolvedById), admin.member.id);
    const entry = await LedgerEntry.findOne({ familyId }).lean();
    assert.equal(entry.memberName, 'Priya Sharma', 'ledger entries stay');

    assertError(await request.get(FAMILY_URL).set(member.auth), 403, 'NO_FAMILY');
    assert.equal(assertOk(await request.get(FAMILY_URL).set(admin.auth)).family.memberCount, 1);
    assertError(await request.delete(memberUrl(memberId)).set(admin.auth), 404, 'NOT_FOUND');

    // The family got a new invite code: the removed person cannot simply join again with the old one,
    // only when an admin shares the new code (then as a new member).
    const { inviteCode } = assertOk(await request.get(FAMILY_URL).set(admin.auth)).family;
    assert.notEqual(inviteCode, admin.family.inviteCode);
    assert.match(inviteCode, INVITE_CODE_REGEX);
    assertError(await request.post(JOIN_URL).set(member.auth).send({ inviteCode: admin.family.inviteCode }), 400, 'INVALID_INVITE_CODE');
    const rejoined = assertOk(await request.post(JOIN_URL).set(member.auth).send({ inviteCode }));
    assert.notEqual(rejoined.member.id, memberId);
    assert.equal(rejoined.member.role, 'member');
  });

  it('removes managed profiles and other admins', async () => {
    const { admin, member } = await familyOfTwo();
    const kid = await addManagedMember(admin.auth);
    assert.equal(assertOk(await request.delete(memberUrl(kid.id)).set(admin.auth)), null);
    await promote(member.member.id);
    assert.equal(assertOk(await request.delete(memberUrl(member.member.id)).set(admin.auth)), null);
    assert.deepEqual((await Member.find({ familyId: admin.family.id }).lean()).map((m) => String(m._id)), [admin.member.id]);
  });

  it('treats an admin removing themselves as leaving the family (LAST_ADMIN, stays signed in)', async () => {
    const { admin, member } = await familyOfTwo();
    assertError(await request.delete(memberUrl(admin.member.id)).set(admin.auth), 409, 'LAST_ADMIN');
    assert.ok(await Member.exists({ _id: admin.member.id }));

    await promote(member.member.id);
    const tokensBefore = await RefreshToken.countDocuments({ userId: admin.user.id });
    assert.equal(assertOk(await request.delete(memberUrl(admin.member.id)).set(admin.auth)), null);
    assert.equal(await RefreshToken.countDocuments({ userId: admin.user.id }), tokensBefore, 'still signed in');
    assert.equal((await User.findById(admin.user.id).lean()).familyId, null);
    const family = await Family.findById(admin.family.id).lean();
    assert.equal(String(family.ownerId), member.user.id, 'ownership moves to the remaining admin');
  });

  it('deletes the whole family when its only member removes themselves', async () => {
    const admin = await registerFamilyAdmin();
    assert.equal(assertOk(await request.delete(memberUrl(admin.member.id)).set(admin.auth)), null);
    assert.equal(await Family.exists({ _id: admin.family.id }), null);
    const loner = await userWithoutFamily();
    assertError(await request.post(JOIN_URL).set(loner.auth).send({ inviteCode: admin.family.inviteCode }), 400, 'INVALID_INVITE_CODE');
  });

  it('answers 404 for unknown ids and 400 for malformed ones', async () => {
    const admin = await registerFamilyAdmin();
    assertError(await request.delete(memberUrl(OTHER_ID)).set(admin.auth), 404, 'NOT_FOUND');
    assertError(await request.delete(memberUrl('123')).set(admin.auth), 400, 'BAD_REQUEST');
  });
});

// ---------------------------------------------------------------- translations

describe('family translations', () => {
  it('has English texts for every key the module uses', () => {
    for (const key of [
      'family.email.invite.subject',
      'family.email.invite.text',
      'family.errors.guardianConsentRequired',
      'family.errors.countryConsentRequired',
      'family.errors.selfEditLimited',
      'family.errors.accountEmailLocked',
      'family.errors.memberLimitReached',
      'family.errors.verifyEmailToLink',
    ]) {
      assert.ok(hasTranslation(key, 'en'), key);
    }
    const mail = renderTemplate({
      locale: 'en',
      template: 'family.invite',
      vars: { name: 'Meera', email: 'meera@example.com', familyName: 'Sharma Family', inviterName: 'Amit', inviteCode: 'K7Q2M9XD' },
    });
    assert.ok(!/\{\w+\}/.test(mail.subject + mail.text), 'every placeholder is filled');
    assert.ok(mail.text.includes('K7Q2M9XD') && mail.text.includes('meera@example.com'));
  });

  it('localizes module errors and falls back to English for languages without a family file', async () => {
    const admin = await registerFamilyAdmin();
    const error = assertError(
      await request.post(MEMBERS_URL).set(admin.auth).set('Accept-Language', 'hi').send({ name: 'Kid', dateOfBirth: yearsAgo(5) }),
      422,
      'GUARDIAN_CONSENT_REQUIRED',
    );
    assert.equal(error.message, t('hi', 'family.errors.guardianConsentRequired', { age: 18 }));
    assert.ok(error.message.includes('18'));
  });
});

// ---------------------------------------------------------------- hardening (adversarial review)

/**
 * Runs `hook` once, right before the first `Model[method]` call of the code under test writes —
 * i.e. between the service's checks and its write — to play a concurrent request deterministically.
 * Works for query methods (`findOneAndUpdate(...).lean()`: the hook runs when the query executes)
 * and for `create` (the hook runs before the document is built, so it gets the smaller id).
 */
async function withConcurrentWrite(Model, method, hook, fn) {
  const hadOwn = Object.hasOwn(Model, method);
  const original = Model[method];
  let fired = false;
  const fire = async () => {
    if (fired) return;
    fired = true;
    await hook();
  };
  Model[method] = function patched(...args) {
    if (method === 'create') return fire().then(() => original.apply(this, args));
    const query = original.apply(this, args);
    const exec = query.exec.bind(query);
    query.exec = async (...execArgs) => {
      await fire();
      return exec(...execArgs);
    };
    return query;
  };
  try {
    return await fn();
  } finally {
    if (hadOwn) Model[method] = original;
    else delete Model[method];
  }
}

describe('family hardening (adversarial review)', () => {
  it('rejects prototype keys and operator objects in every body, and accepts upper-case or padded ids', async () => {
    const { admin, member } = await familyOfTwo();
    const raw = (method, url, json) => request[method](url).set(admin.auth).set('Content-Type', 'application/json').send(json);

    assertValidation(await raw('post', MEMBERS_URL, '{"name":"X","__proto__":{"role":"admin"}}'));
    assertValidation(await raw('patch', memberUrl(member.member.id), '{"__proto__":{"role":"admin"}}'));
    assertValidation(await raw('patch', FAMILY_URL, '{"constructor":{"prototype":{"x":1}}}'));
    assertValidation(await request.post(MEMBERS_URL).set(admin.auth).send([{ name: 'X' }]));
    assertValidation(await request.patch(memberUrl(member.member.id)).set(admin.auth).send({ email: { $ne: null } }), 'email');
    assertValidation(await request.patch(memberUrl(member.member.id)).set(admin.auth).send({ dateOfBirth: { $gt: '' } }), 'dateOfBirth');
    assertValidation(await request.patch(FAMILY_URL).set(admin.auth).send({ country: { $ne: 'IN' } }), 'country');
    assertError(await request.get(memberUrl(encodeURIComponent('{"$ne":null}'))).set(admin.auth), 400, 'BAD_REQUEST');
    assert.equal((await Member.findById(member.member.id).lean()).role, 'member');
    assert.equal(await Member.countDocuments({ familyId: admin.family.id }), 2);

    const upper = assertOk(await request.get(memberUrl(member.member.id.toUpperCase())).set(admin.auth));
    assert.equal(upper.id, member.member.id);
    const padded = assertOk(await request.get(memberUrl(`%20${member.member.id}%20`)).set(admin.auth));
    assert.equal(padded.id, member.member.id);
  });

  it('lets exactly one of concurrent create / join requests of the same account succeed', async () => {
    const other = await registerFamilyAdmin();
    const loner = await userWithoutFamily();
    const body = { name: 'Race Family', country: 'IN', currency: 'INR', timezone: 'Asia/Kolkata' };
    const results = await Promise.all([
      ...Array.from({ length: 3 }, () => request.post(FAMILY_URL).set(loner.auth).send(body)),
      ...Array.from({ length: 3 }, () => request.post(JOIN_URL).set(loner.auth).send({ inviteCode: other.family.inviteCode })),
    ]);
    const ok = results.filter((r) => r.status === 200 || r.status === 201);
    assert.equal(ok.length, 1, JSON.stringify(results.map((r) => r.status)));
    for (const res of results.filter((r) => !ok.includes(r))) assertError(res, 409, 'ALREADY_IN_FAMILY');
    assert.equal(await Member.countDocuments({ userId: loner.user.id }), 1, 'one membership, the others were rolled back');
    const user = await User.findById(loner.user.id).lean();
    const member = await Member.findOne({ userId: loner.user.id }).lean();
    assert.equal(String(user.memberId), String(member._id));
    assert.equal(await Family.countDocuments({ ownerId: loner.user.id }), ok[0].status === 201 ? 1 : 0, 'no orphan families');
  });

  it('keeps e-mails unique under concurrent adds (one 201, the rest 409)', async () => {
    const admin = await registerFamilyAdmin();
    const email = uniqueEmail('race');
    const results = await Promise.all(Array.from({ length: 5 }, (_, i) => request.post(MEMBERS_URL).set(admin.auth).send({ name: `Dup ${i}`, email })));
    assert.equal(results.filter((r) => r.status === 201).length, 1);
    for (const res of results.filter((r) => r.status !== 201)) assertError(res, 409, 'MEMBER_EMAIL_EXISTS');
    assert.equal(await Member.countDocuments({ familyId: admin.family.id, email }), 1);
  });

  it('re-checks guardian consent when the date of birth or consent changed between check and write', async () => {
    const admin = await registerFamilyAdmin(); // IN → 18
    const adult = await addManagedMember(admin.auth, { name: 'Ravi', dateOfBirth: yearsAgo(30), guardianConsent: true });

    // Admin A withdraws consent of an adult while admin B makes the member 10 (B still saw consent).
    const withdraw = await withConcurrentWrite(
      Member,
      'findOneAndUpdate',
      () => Member.updateOne({ _id: adult.id }, { $set: { dateOfBirth: new Date(yearsAgo(10)) } }),
      () => request.patch(memberUrl(adult.id)).set(admin.auth).send({ guardianConsent: false }),
    );
    assert.deepEqual(assertError(withdraw, 422, 'GUARDIAN_CONSENT_REQUIRED').details.memberIds, [adult.id]);
    assert.equal((await Member.findById(adult.id).lean()).guardianConsent, true, 'consent kept for the minor');

    // The other way round: A makes a consented adult 10 while B withdraws the consent (B saw an adult).
    await Member.updateOne({ _id: adult.id }, { $set: { dateOfBirth: new Date(yearsAgo(30)) } });
    const younger = await withConcurrentWrite(
      Member,
      'findOneAndUpdate',
      () => Member.updateOne({ _id: adult.id }, { $set: { guardianConsent: false, guardianConsentAt: null, guardianConsentById: null } }),
      () => request.patch(memberUrl(adult.id)).set(admin.auth).send({ dateOfBirth: yearsAgo(10) }),
    );
    assertError(younger, 422, 'GUARDIAN_CONSENT_REQUIRED');
    const stored = await Member.findById(adult.id).lean();
    assert.equal(stored.guardianConsent, false);
    assert.ok(stored.dateOfBirth < new Date(yearsAgo(18)), 'still an adult');
  });

  it('never leaves a minor without consent when two admins really race (consent vs date of birth)', async () => {
    const { admin, member } = await familyOfTwo();
    await promote(member.member.id);
    for (let round = 0; round < 5; round += 1) {
      const kid = await addManagedMember(admin.auth, { name: `Round ${round}`, dateOfBirth: yearsAgo(30), guardianConsent: true });
      const results = await Promise.all([
        request.patch(memberUrl(kid.id)).set(admin.auth).send({ guardianConsent: false }),
        request.patch(memberUrl(kid.id)).set(member.auth).send({ dateOfBirth: yearsAgo(10) }),
      ]);
      for (const res of results) assert.ok([200, 409, 422].includes(res.status), JSON.stringify(res.body));
      const stored = await Member.findById(kid.id).lean();
      const minor = stored.dateOfBirth > new Date(yearsAgo(18));
      assert.ok(!(minor && !stored.guardianConsent), `round ${round}: a minor without guardian consent`);
    }
  });

  it('keeps the sign-in e-mail when an account links to the profile between check and write', async () => {
    const admin = await registerFamilyAdmin();
    const invited = uniqueEmail('linked');
    const kid = await addManagedMember(admin.auth, { name: 'Meera', email: invited, dateOfBirth: yearsAgo(30), guardianConsent: false });
    const account = await userWithoutFamily({ email: invited });

    const res = await withConcurrentWrite(
      Member,
      'findOneAndUpdate',
      () => Member.updateOne({ _id: kid.id }, { $set: { userId: account.user.id } }),
      () => request.patch(memberUrl(kid.id)).set(admin.auth).send({ email: uniqueEmail('other') }),
    );
    assertValidation(res, 'email');
    assert.equal((await Member.findById(kid.id).lean()).email, invited);
  });

  it('undoes a country change when a minor without consent was added meanwhile (GAP-05 race)', async () => {
    const admin = await registerFamilyAdmin({ family: { country: 'US', currency: 'USD', timezone: 'America/New_York' } });
    let teenId;
    const res = await withConcurrentWrite(
      Family,
      'findOneAndUpdate',
      async () => {
        // Added under US rules (15 ≥ 13) by another admin at the same moment.
        const teen = await Member.create({ familyId: admin.family.id, name: 'Teen', dateOfBirth: new Date(yearsAgo(15)) });
        teenId = String(teen._id);
      },
      () => request.patch(FAMILY_URL).set(admin.auth).send({ country: 'IN', timezone: 'Asia/Kolkata', name: 'Renamed' }),
    );
    const error = assertError(res, 422, 'GUARDIAN_CONSENT_REQUIRED');
    assert.deepEqual(error.details.memberIds, [teenId]);
    const family = await Family.findById(admin.family.id).lean();
    assert.equal(family.country, 'US');
    assert.equal(family.timezone, 'America/New_York');
    assert.equal(family.name, 'Sharma Family', 'the whole change is undone');
  });

  it('removes a member added under the old country when the country changed meanwhile', async () => {
    const admin = await registerFamilyAdmin({ family: { country: 'US', currency: 'USD', timezone: 'America/New_York' } });
    const res = await withConcurrentWrite(
      Member,
      'create',
      () => Family.updateOne({ _id: admin.family.id }, { $set: { country: 'IN', timezone: 'Asia/Kolkata' } }),
      () => request.post(MEMBERS_URL).set(admin.auth).send({ name: 'Teen', dateOfBirth: yearsAgo(15) }),
    );
    assertError(res, 422, 'GUARDIAN_CONSENT_REQUIRED');
    assert.equal(await Member.countDocuments({ familyId: admin.family.id }), 1, 'nothing left behind');
  });

  it('undoes a date-of-birth change when the country changed meanwhile', async () => {
    const admin = await registerFamilyAdmin({ family: { country: 'US', currency: 'USD', timezone: 'America/New_York' } });
    const person = await addManagedMember(admin.auth, { name: 'Sam', dateOfBirth: yearsAgo(30), guardianConsent: false, designation: 'Scout' });
    const res = await withConcurrentWrite(
      Member,
      'findOneAndUpdate',
      () => Family.updateOne({ _id: admin.family.id }, { $set: { country: 'IN', timezone: 'Asia/Kolkata' } }),
      () => request.patch(memberUrl(person.id)).set(admin.auth).send({ dateOfBirth: yearsAgo(15), designation: 'Captain' }),
    );
    assert.deepEqual(assertError(res, 422, 'GUARDIAN_CONSENT_REQUIRED').details.memberIds, [person.id]);
    const stored = await Member.findById(person.id).lean();
    assert.equal(stored.dateOfBirth.toISOString(), person.dateOfBirth);
    assert.equal(stored.designation, 'Scout', 'the whole change is undone');
  });

  it('rejects lone surrogates, stores designations in NFC and treats invisible ones as blank', async () => {
    const admin = await registerFamilyAdmin();
    const raw = (method, url, json) => request[method](url).set(admin.auth).set('Content-Type', 'application/json').send(json);
    assertValidation(await raw('post', MEMBERS_URL, '{"name":"A\\ud800"}'), 'name');
    assertValidation(await raw('post', MEMBERS_URL, '{"name":"B","designation":"\\udc00Chief"}'), 'designation');
    assertValidation(await raw('patch', FAMILY_URL, '{"name":"Sharma \\ud83d"}'), 'name');
    assertValidation(await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'C', designation: 'Chief‮Officer' }), 'designation');
    assert.equal(await Member.countDocuments({ familyId: admin.family.id }), 1);

    const nfc = assertOk(await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'Zoë', designation: 'Café Chef' }), 201);
    assert.equal(nfc.name, 'Zoë');
    assert.equal(nfc.designation, 'Café Chef');
    assert.equal((await Member.findById(nfc.id).lean()).designation, 'Café Chef');

    for (const invisible of ['​​', 'ㅤ', '‎ ⠀']) {
      const member = assertOk(await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'Blank', designation: invisible }), 201);
      assert.equal(member.designation, null, JSON.stringify(invisible));
    }
    // Scripts, emoji and RTL text are kept exactly.
    const rtl = assertOk(await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'عائشة 👩‍👧', designation: 'رئيسة المالية' }), 201);
    assert.equal(rtl.name, 'عائشة 👩‍👧');
    assert.equal(rtl.designation, 'رئيسة المالية');
  });

  it('gives the family a new invite code only when a member with an account is removed', async () => {
    const { admin, member } = await familyOfTwo();
    const codeOf = async () => assertOk(await request.get(FAMILY_URL).set(admin.auth)).family.inviteCode;
    const original = await codeOf();

    const kid = await addManagedMember(admin.auth, { email: uniqueEmail('kid') });
    assertOk(await request.delete(memberUrl(kid.id)).set(admin.auth));
    assert.equal(await codeOf(), original, 'a managed profile never joined: code (and other invitations) kept');

    assertOk(await request.delete(memberUrl(member.member.id)).set(admin.auth));
    const rotated = await codeOf();
    assert.notEqual(rotated, original);
    const login = assertOk(await request.post(`${API}/auth/login`).send({ email: member.user.email, password: member.password }));
    assertError(await request.post(JOIN_URL).set(authHeader(login.tokens)).send({ inviteCode: original }), 400, 'INVALID_INVITE_CODE');

    // An admin leaving on their own (DELETE of themselves) keeps the code.
    const second = await joinFamilyAs(rotated);
    await promote(second.member.id);
    const afterJoin = await codeOf();
    assertOk(await request.delete(memberUrl(admin.member.id)).set(admin.auth));
    assert.equal(assertOk(await request.get(FAMILY_URL).set(second.auth)).family.inviteCode, afterJoin);
  });

  it('links a pre-added profile only to an account with a verified e-mail address', async () => {
    const admin = await registerFamilyAdmin();
    const address = uniqueEmail('grandpa');
    const profile = await addManagedMember(admin.auth, { name: 'Grandpa', email: address, role: 'admin', dateOfBirth: yearsAgo(70), guardianConsent: false });

    // Anyone who knows the code and reads the address in the member list could open an account with it.
    const impostor = await userWithoutFamily({ email: address });
    const error = assertError(await request.post(JOIN_URL).set(impostor.auth).send({ inviteCode: admin.family.inviteCode }), 403, 'FORBIDDEN');
    assert.equal(error.message, t('en', 'family.errors.verifyEmailToLink'));
    assert.equal((await Member.findById(profile.id).lean()).userId, null, 'profile not taken over');
    assert.equal((await User.findById(impostor.user.id).lean()).familyId, null);

    // An unverified account without a pre-added profile may still join as a new member.
    const newcomer = await userWithoutFamily();
    assert.equal(assertOk(await request.post(JOIN_URL).set(newcomer.auth).send({ inviteCode: admin.family.inviteCode })).member.role, 'member');

    // Whoever proves the address owns the profile.
    await verifyEmail(impostor);
    const data = assertOk(await request.post(JOIN_URL).set(impostor.auth).send({ inviteCode: admin.family.inviteCode }));
    assert.equal(data.member.id, profile.id);
    assert.equal(data.member.role, 'admin');
  });

  it('limits invitation e-mails per family (429 before anything is written), also for a parallel burst', async () => {
    const admin = await registerFamilyAdmin();
    const burst = await Promise.all(
      Array.from({ length: INVITATION_LIMITS.perFamily + 5 }, (_, i) =>
        request.post(MEMBERS_URL).set(admin.auth).send({ name: `Guest ${i}`, email: uniqueEmail('guest') }),
      ),
    );
    assert.equal(burst.filter((r) => r.status === 201).length, INVITATION_LIMITS.perFamily);
    for (const res of burst.filter((r) => r.status !== 201)) assertError(res, 429, 'TOO_MANY_REQUESTS');
    assert.equal(outbox.filter((m) => m.template === 'family.invite').length, INVITATION_LIMITS.perFamily);
    const count = await Member.countDocuments({ familyId: admin.family.id });
    assert.equal(count, INVITATION_LIMITS.perFamily + 1);
    const error = assertError(
      await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'One more', email: uniqueEmail('guest') }),
      429,
      'TOO_MANY_REQUESTS',
    );
    assert.ok(error.details.retryAfterSeconds > 0 && error.details.retryAfterSeconds <= 3600);
    assert.equal(await Member.countDocuments({ familyId: admin.family.id }), count);

    const kid = assertOk(await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'No e-mail' }), 201);
    assertError(await request.patch(memberUrl(kid.id)).set(admin.auth).send({ email: uniqueEmail('guest') }), 429, 'TOO_MANY_REQUESTS');
    assert.equal((await Member.findById(kid.id).lean()).email, null);
    assertOk(await request.patch(memberUrl(kid.id)).set(admin.auth).send({ designation: 'Other edits still work' }));

    // Another family has its own budget.
    const other = await registerFamilyAdmin();
    assertOk(await request.post(MEMBERS_URL).set(other.auth).send({ name: 'Guest', email: uniqueEmail('guest') }), 201);
  });

  it('sends at most three invitations a day to one address, across families, without telling the sender', async () => {
    const address = uniqueEmail('target');
    for (let i = 0; i < INVITATION_LIMITS.perRecipient + 2; i += 1) {
      const admin = await registerFamilyAdmin({ family: { name: `Family ${i}` } });
      assertOk(await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'Target', email: address.toUpperCase() }), 201);
    }
    const invitations = outbox.filter((m) => m.template === 'family.invite' && m.to === address);
    assert.equal(invitations.length, INVITATION_LIMITS.perRecipient);
    assert.equal(await Member.countDocuments({ email: address }), INVITATION_LIMITS.perRecipient + 2, 'profiles are still added');
  });

  it(`caps a family at ${MAX_FAMILY_MEMBERS} members (409 CONFLICT), also under concurrent adds`, async () => {
    const admin = await registerFamilyAdmin();
    await Member.insertMany(
      Array.from({ length: MAX_FAMILY_MEMBERS - 1 }, (_, i) => ({ familyId: admin.family.id, name: `Profile ${i}` })),
    );
    const error = assertError(await request.post(MEMBERS_URL).set(admin.auth).send({ name: 'One too many' }), 409, 'CONFLICT');
    assert.equal(error.details.limit, MAX_FAMILY_MEMBERS);
    assert.equal(error.message, t('en', 'family.errors.memberLimitReached', { limit: MAX_FAMILY_MEMBERS }));
    assert.equal(await Member.countDocuments({ familyId: admin.family.id }), MAX_FAMILY_MEMBERS);

    // One place left, taken by a concurrent add between this request's size check and its write:
    // the member written first keeps the place.
    await Member.deleteOne({ familyId: admin.family.id, name: 'Profile 0' });
    const late = await withConcurrentWrite(
      Member,
      'create',
      () => Member.insertMany([{ familyId: admin.family.id, name: 'Concurrent' }]),
      () => request.post(MEMBERS_URL).set(admin.auth).send({ name: 'Late' }),
    );
    assertError(late, 409, 'CONFLICT');
    assert.equal(await Member.countDocuments({ familyId: admin.family.id }), MAX_FAMILY_MEMBERS);
    assert.equal(await Member.exists({ familyId: admin.family.id, name: 'Late' }), null);

    // Real parallel adds for the last place: exactly one wins.
    await Member.deleteOne({ familyId: admin.family.id, name: 'Concurrent' });
    const results = await Promise.all(Array.from({ length: 4 }, (_, i) => request.post(MEMBERS_URL).set(admin.auth).send({ name: `Racer ${i}` })));
    assert.equal(results.filter((r) => r.status === 201).length, 1, JSON.stringify(results.map((r) => r.status)));
    for (const res of results.filter((r) => r.status !== 201)) assertError(res, 409, 'CONFLICT');
    assert.equal(await Member.countDocuments({ familyId: admin.family.id }), MAX_FAMILY_MEMBERS);
  });
});
