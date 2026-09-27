/**
 * Auth module: docs/03-API_CONTRACT.md §4 (`/auth/*`).
 *
 * Covers both register modes (create / join / link to a pre-added member), consent and the
 * self-registration age gate, duplicate e-mails, login lockout (known and unknown e-mails),
 * refresh rotation + reuse detection, logout scoping, OTP expiry / attempts / cooldown,
 * password reset (no enumeration, revokes sessions), change password and GET /auth/me.
 */
import {
  API,
  DEFAULT_PASSWORD,
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
import bcrypt from 'bcryptjs';

const { User, Family, Member, Device, RefreshToken, Otp } = await import('../src/models/index.js');
const { consentAge } = await import('../src/lib/countries.js');
const { hasTranslation, t } = await import('../src/lib/i18n.js');
const { renderTemplate } = await import('../src/services/mailer.js');
const { ApiError } = await import('../src/lib/ApiError.js');
const { createFamilyWithUniqueCode, createFamilyForUser, joinFamilyForUser } = await import('../src/modules/auth/auth.onboarding.js');
const { resetPhantomLockouts, PASSWORD_HASH_ROUNDS, reservePhantomAttempt, failPhantomAttempt } = await import(
  '../src/modules/auth/auth.passwords.js'
);
const { cooldownMsFor } = await import('../src/modules/auth/auth.otp.js');
const { toAsciiDigits } = await import('../src/modules/auth/auth.schemas.js');
const { env } = await import('../src/config/env.js');
const { JWT_AUDIENCE, JWT_ISSUER } = await import('../src/lib/constants.js');
const { default: jwt } = await import('jsonwebtoken');

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

const OBJECT_ID = /^[a-f0-9]{24}$/;
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const INVITE = /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/;

function assertOk(res, status = 200) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.equal(res.body.success, true);
  assert.ok('data' in res.body);
  assert.ok(!('meta' in res.body), 'meta only on paginated lists');
  return res.body.data;
}

function assertError(res, status, code) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.equal(res.body.success, false);
  assert.equal(res.body.error.code, code);
  assert.equal(typeof res.body.error.message, 'string');
  assert.ok(res.body.error.message.length > 0);
  assert.ok(!('stack' in res.body.error));
  return res.body.error;
}

function assertValidation(res, ...fields) {
  const error = assertError(res, 422, 'VALIDATION_ERROR');
  for (const field of fields) {
    assert.ok(error.details && typeof error.details[field] === 'string', `details.${field} in ${JSON.stringify(error.details)}`);
  }
  return error;
}

/** Never leak secrets in any response. */
function assertNoSecrets(body) {
  const json = JSON.stringify(body);
  for (const secret of ['passwordHash', 'codeHash', 'tokenHash', 'failedLoginCount', 'lockUntil', '"_id"', '__v']) {
    assert.ok(!json.includes(secret), `response must not contain ${secret}`);
  }
}

function assertTokens(tokens) {
  assert.equal(typeof tokens.accessToken, 'string');
  assert.equal(tokens.accessToken.split('.').length, 3, 'JWT');
  assert.match(tokens.refreshToken, /^[A-Za-z0-9_-]{64}$/, '48 random bytes, base64url');
  assert.equal(tokens.expiresIn, 900);
}

function createBody(overrides = {}) {
  const { family, ...rest } = overrides;
  return {
    name: 'Amit Sharma',
    email: uniqueEmail('admin'),
    password: DEFAULT_PASSWORD,
    locale: 'en',
    consentAccepted: true,
    dateOfBirth: '1985-02-01T00:00:00.000Z',
    mode: 'create',
    family: { name: 'Sharma Family', country: 'IN', currency: 'INR', timezone: 'Asia/Kolkata', ...family },
    inviteCode: null,
    ...rest,
  };
}

function joinBody(inviteCode, overrides = {}) {
  return {
    name: 'Priya Sharma',
    email: uniqueEmail('member'),
    password: DEFAULT_PASSWORD,
    locale: 'en',
    consentAccepted: true,
    dateOfBirth: '1990-06-15T00:00:00.000Z',
    mode: 'join',
    family: null,
    inviteCode,
    ...overrides,
  };
}

const register = (body, headers = {}) => request.post(`${API}/auth/register`).set(headers).send(body);
const login = (email, password = DEFAULT_PASSWORD) => request.post(`${API}/auth/login`).send({ email, password });
const refresh = (refreshToken) => request.post(`${API}/auth/refresh`).send({ refreshToken });
const me = (auth) => request.get(`${API}/auth/me`).set(auth);

/** ISO date `years` years (and a few days) ago. */
function yearsAgo(years) {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear() - years, now.getUTCMonth(), now.getUTCDate() - 10)).toISOString();
}

/** Admin-created profile without an account (what POST /family/members stores). */
function preAddMember(familyId, fields = {}) {
  return Member.create({ familyId, name: 'Grandpa', role: 'member', designation: 'Wisdom Officer', ...fields });
}

const minutesAgo = (m) => new Date(Date.now() - m * 60 * 1000);

// ---------------------------------------------------------------- register: create

describe('POST /auth/register (create)', () => {
  it('creates the account, the family and its admin member (contract shapes)', async () => {
    const body = createBody();
    const res = await register(body);
    const data = assertOk(res, 201);
    assertNoSecrets(res.body);
    assert.deepEqual(Object.keys(data).sort(), ['family', 'member', 'tokens', 'user']);

    const { user, tokens, family, member } = data;
    assert.deepEqual(Object.keys(user).sort(), ['createdAt', 'email', 'emailVerified', 'familyId', 'id', 'locale', 'memberId', 'name', 'role']);
    assert.match(user.id, OBJECT_ID);
    assert.equal(user.email, body.email);
    assert.equal(user.name, 'Amit Sharma');
    assert.equal(user.emailVerified, false);
    assert.equal(user.locale, 'en');
    assert.equal(user.role, 'admin');
    assert.equal(user.familyId, family.id);
    assert.equal(user.memberId, member.id);
    assert.match(user.createdAt, ISO);
    assertTokens(tokens);

    assert.equal(family.name, 'Sharma Family');
    assert.match(family.inviteCode, INVITE, 'admins see the invite code');
    assert.equal(family.country, 'IN');
    assert.equal(family.currency, 'INR');
    assert.equal(family.timezone, 'Asia/Kolkata');
    assert.equal(family.ownerId, user.id);
    assert.equal(family.memberCount, 1);

    assert.equal(member.familyId, family.id);
    assert.equal(member.userId, user.id);
    assert.equal(member.role, 'admin');
    assert.equal(member.designation, 'Head of Family');
    assert.equal(member.hasAccount, true);
    assert.equal(member.email, body.email);
    assert.equal(member.dateOfBirth, '1985-02-01T00:00:00.000Z');
    assert.equal(member.locationSharing, 'never', 'privacy by default');
    assert.equal(member.lastLocation, null);

    // The access token works right away.
    assertOk(await me(authHeader(tokens)));
  });

  it('normalises the e-mail, hashes the password (bcrypt) and records consent', async () => {
    const res = await register(createBody({ email: '  Amit.Sharma@Example.COM ', name: '  Amit  ' }));
    const { user } = assertOk(res, 201);
    assert.equal(user.email, 'amit.sharma@example.com');
    assert.equal(user.name, 'Amit');

    const doc = await User.findById(user.id).lean();
    assert.ok(doc.passwordHash.startsWith('$2'));
    assert.equal(bcrypt.getRounds(doc.passwordHash), PASSWORD_HASH_ROUNDS);
    assert.equal(PASSWORD_HASH_ROUNDS, 10, 'cost 10 in tests (12 otherwise)');
    assert.ok(await bcrypt.compare(DEFAULT_PASSWORD, doc.passwordHash));
    assert.ok(doc.consentAcceptedAt instanceof Date);
    assert.ok(Math.abs(doc.consentAcceptedAt.getTime() - Date.now()) < 60_000);
  });

  it('e-mails a 6-digit verification code in the user locale, stored only as a hash', async () => {
    const body = createBody({ locale: 'hi' });
    assertOk(await register(body), 201);
    const mail = lastMailTo(body.email);
    assert.ok(mail, 'verification e-mail sent');
    assert.equal(mail.template, 'auth.verifyEmail');
    assert.equal(mail.locale, 'hi');
    const code = lastOtpFor(body.email);
    assert.match(code, /^\d{6}$/);
    assert.ok(mail.text.includes(code));

    const otp = await Otp.findOne({ email: body.email, purpose: 'verify_email' }).lean();
    assert.ok(otp);
    assert.notEqual(otp.codeHash, code);
    assert.ok(!JSON.stringify(otp).includes(`"${code}"`), 'plain code never stored');
    assert.equal(otp.attempts, 0);
    const ttl = otp.expiresAt.getTime() - Date.now();
    assert.ok(ttl > 9 * 60_000 && ttl <= 10 * 60_000, `expires in 10 min (got ${ttl} ms)`);
  });

  it('uses Accept-Language when the body has no locale', async () => {
    const body = createBody();
    delete body.locale;
    const { user } = assertOk(await register(body, { 'Accept-Language': 'ta-IN,ta;q=0.9' }), 201);
    assert.equal(user.locale, 'ta');
  });

  it('allows a missing date of birth', async () => {
    const { member } = assertOk(await register(createBody({ dateOfBirth: null })), 201);
    assert.equal(member.dateOfBirth, null);
  });

  it('rejects a duplicate e-mail (case-insensitive) with 409 EMAIL_TAKEN and creates nothing', async () => {
    const first = createBody({ email: uniqueEmail('dup') });
    assertOk(await register(first), 201);
    const res = await register(createBody({ email: first.email.toUpperCase(), family: { name: 'Other' } }));
    assertError(res, 409, 'EMAIL_TAKEN');
    assert.equal(await User.countDocuments({ email: first.email }), 1);
    assert.equal(await Family.countDocuments({}), 1);
  });

  it('gives every family a unique invite code', async () => {
    const codes = new Set();
    for (let i = 0; i < 3; i += 1) {
      const { family } = assertOk(await register(createBody()), 201);
      codes.add(family.inviteCode);
    }
    assert.equal(codes.size, 3);
  });

  describe('validation (422 VALIDATION_ERROR with details)', () => {
    const cases = [
      ['consentAccepted false', { consentAccepted: false }, 'consentAccepted'],
      ['consentAccepted missing', { consentAccepted: undefined }, 'consentAccepted'],
      ['password too short', { password: 'abc123' }, 'password'],
      ['password without digit', { password: 'onlyletters' }, 'password'],
      ['password without letter', { password: '12345678' }, 'password'],
      ['password over 72 bytes', { password: `a1${'é'.repeat(40)}` }, 'password'],
      ['invalid email', { email: 'not-an-email' }, 'email'],
      ['blank name', { name: '   ' }, 'name'],
      ['name over 60 chars', { name: 'x'.repeat(61) }, 'name'],
      ['unknown mode', { mode: 'other' }, 'mode'],
      ['create without family', { family: null }, 'family'],
      ['family name over 60 chars', { family: { name: 'f'.repeat(61) } }, 'family.name'],
      ['unsupported country', { family: { country: 'XX' } }, 'family.country'],
      ['unsupported currency', { family: { currency: 'ABC' } }, 'family.currency'],
      ['invalid time zone', { family: { timezone: 'Mars/Base' } }, 'family.timezone'],
      ['unsupported locale', { locale: 'xx' }, 'locale'],
      ['invalid date of birth', { dateOfBirth: 'yesterday' }, 'dateOfBirth'],
      ['future date of birth', { dateOfBirth: new Date(Date.now() + 5 * 86_400_000).toISOString() }, 'dateOfBirth'],
    ];
    for (const [label, overrides, field] of cases) {
      it(label, async () => {
        const body = createBody(overrides);
        for (const [k, v] of Object.entries(overrides)) if (v === undefined) delete body[k];
        if (overrides.family === null) body.family = null;
        const res = await register(body);
        assertValidation(res, field);
        assert.equal(await User.countDocuments({}), 0, 'nothing created');
        assert.equal(outbox.length, 0, 'no e-mail');
      });
    }

    it('join without invite code / with a malformed one', async () => {
      assertValidation(await register(joinBody(null)), 'inviteCode');
      assertValidation(await register(joinBody('abc')), 'inviteCode');
      assert.equal(await User.countDocuments({}), 0);
    });

    it('ignores the field of the other mode (inviteCode on create, family on join)', async () => {
      const admin = assertOk(await register(createBody({ inviteCode: 'not a code!' })), 201);
      assert.equal(admin.member.role, 'admin');
      const joined = assertOk(await register(joinBody(admin.family.inviteCode, { family: { name: '' } })), 201);
      assert.equal(joined.family.id, admin.family.id);
      assert.equal(await Family.countDocuments({}), 1);
    });

    it('reports several fields at once', async () => {
      const res = await register(createBody({ email: 'nope', password: 'x', name: '' }));
      assertValidation(res, 'email', 'password', 'name');
    });
  });

  it('blocks self-registration below the country consent age (GUARDIAN_CONSENT_REQUIRED)', async () => {
    const age = consentAge('IN') - 2;
    const res = await register(createBody({ dateOfBirth: yearsAgo(age) }));
    const error = assertError(res, 422, 'GUARDIAN_CONSENT_REQUIRED');
    assert.equal(error.details.consentAge, consentAge('IN'));
    assert.ok(error.message.includes(String(consentAge('IN'))), error.message);
    assert.equal(await User.countDocuments({}), 0);
    assert.equal(await Family.countDocuments({}), 0);

    // Same age is fine where the consent age is lower (US: 13).
    assert.ok(consentAge('US') <= age);
    assertOk(
      await register(createBody({ dateOfBirth: yearsAgo(age), family: { country: 'US', currency: 'USD', timezone: 'America/New_York' } })),
      201,
    );
  });
});

describe('createFamilyWithUniqueCode', () => {
  it('regenerates the invite code on a duplicate key', async () => {
    const owner = await User.create({ email: uniqueEmail('owner'), passwordHash: 'x', name: 'Owner' });
    const base = { name: 'Fam', country: 'IN', currency: 'INR', timezone: 'Asia/Kolkata', ownerId: owner._id };
    await Family.create({ ...base, inviteCode: 'ABCDEFGH' });
    const codes = ['ABCDEFGH', 'ABCDEFGH', 'ZXCVBNMK'];
    const family = await createFamilyWithUniqueCode(base, { generateCode: () => codes.shift() });
    assert.equal(family.inviteCode, 'ZXCVBNMK');
    assert.equal(codes.length, 0);
  });

  it('gives up after maxAttempts with an internal error', async () => {
    const owner = await User.create({ email: uniqueEmail('owner'), passwordHash: 'x', name: 'Owner' });
    const base = { name: 'Fam', country: 'IN', currency: 'INR', timezone: 'Asia/Kolkata', ownerId: owner._id };
    await Family.create({ ...base, inviteCode: 'ABCDEFGH' });
    await assert.rejects(
      createFamilyWithUniqueCode(base, { generateCode: () => 'ABCDEFGH', maxAttempts: 3 }),
      (err) => err instanceof ApiError && err.code === 'INTERNAL_ERROR',
    );
    assert.equal(await Family.countDocuments({}), 1);
  });
});

// ---------------------------------------------------------------- register: join / link

describe('POST /auth/register (join)', () => {
  it('joins with an invite code as a member and notifies the admins', async () => {
    const admin = await registerFamilyAdmin();
    sentPushes.length = 0;
    const input = `${admin.family.inviteCode.slice(0, 4).toLowerCase()}-${admin.family.inviteCode.slice(4)}`;
    const res = await register(joinBody(input));
    const { user, tokens, family, member } = assertOk(res, 201);
    assertNoSecrets(res.body);
    assertTokens(tokens);

    assert.equal(user.role, 'member');
    assert.equal(user.familyId, admin.family.id);
    assert.equal(user.memberId, member.id);
    assert.equal(member.role, 'member');
    assert.equal(member.userId, user.id);
    assert.equal(member.hasAccount, true);
    assert.equal(member.name, 'Priya Sharma');
    assert.equal(family.id, admin.family.id);
    assert.equal(family.inviteCode, null, 'members never see the invite code');
    assert.equal(family.memberCount, 2);

    assert.equal(sentPushes.length, 1);
    const push = sentPushes[0];
    assert.equal(push.type, 'member_joined');
    assert.equal(push.id, member.id);
    assert.equal(push.route, `/members/${member.id}`);
    assert.equal(push.titleKey, 'auth.push.memberJoined.title');
    assert.equal(push.bodyKey, 'auth.push.memberJoined.body');
    assert.deepEqual(push.vars, { name: 'Priya Sharma', familyName: 'Sharma Family' });
    await flushPushes();
    assert.deepEqual(push.memberIds, [admin.member.id], 'only admins, never the new member');
  });

  it('rejects an unknown invite code with 400 INVALID_INVITE_CODE and creates no account', async () => {
    await registerFamilyAdmin();
    const body = joinBody('ZZZZZZZZ');
    assertError(await register(body), 400, 'INVALID_INVITE_CODE');
    assert.equal(await User.countDocuments({ email: body.email }), 0);
    assert.equal(outbox.filter((m) => m.to === body.email).length, 0);
  });

  it('links to a member an admin pre-added with the same e-mail and no account', async () => {
    const admin = await registerFamilyAdmin();
    const pre = await preAddMember(admin.family.id, { email: 'dada.link@example.com', role: 'admin', dateOfBirth: null });
    sentPushes.length = 0;

    const res = await register(joinBody(admin.family.inviteCode, { email: 'Dada.Link@Example.com', name: 'Ramesh', dateOfBirth: '1950-01-01T00:00:00.000Z' }));
    const { user, member, family } = assertOk(res, 201);
    assert.equal(member.id, String(pre._id), 'the existing profile is reused');
    assert.equal(member.userId, user.id);
    assert.equal(member.hasAccount, true);
    assert.equal(member.name, 'Grandpa', 'admin-given profile data is kept');
    assert.equal(member.designation, 'Wisdom Officer');
    assert.equal(member.role, 'admin', 'pre-assigned role is kept');
    assert.equal(member.dateOfBirth, '1950-01-01T00:00:00.000Z', 'missing DOB filled in');
    assert.equal(user.role, 'admin');
    assert.equal(user.name, 'Ramesh');
    assert.match(family.inviteCode, INVITE, 'linked admin sees the code');
    assert.equal(family.memberCount, 2);
    assert.equal(await Member.countDocuments({ familyId: admin.family.id }), 2, 'no duplicate member');

    const dbUser = await User.findById(user.id).lean();
    assert.equal(String(dbUser.memberId), String(pre._id));
    assert.equal(sentPushes.length, 1);
    await flushPushes();
    assert.deepEqual(sentPushes[0].memberIds, [admin.member.id]);
  });

  it('keeps an existing DOB of the pre-added member', async () => {
    const admin = await registerFamilyAdmin();
    await preAddMember(admin.family.id, { email: 'keep.dob@example.com', dateOfBirth: new Date('1960-03-03T00:00:00.000Z') });
    const { member } = assertOk(await register(joinBody(admin.family.inviteCode, { email: 'keep.dob@example.com' })), 201);
    assert.equal(member.dateOfBirth, '1960-03-03T00:00:00.000Z');
  });

  it('409 MEMBER_EMAIL_EXISTS when the member with that e-mail already has an account', async () => {
    const admin = await registerFamilyAdmin();
    const other = await User.create({ email: uniqueEmail('other'), passwordHash: 'x', name: 'Other' });
    await preAddMember(admin.family.id, { email: 'taken.profile@example.com', userId: other._id });
    const res = await register(joinBody(admin.family.inviteCode, { email: 'taken.profile@example.com' }));
    assertError(res, 409, 'MEMBER_EMAIL_EXISTS');
    assert.equal(await User.countDocuments({ email: 'taken.profile@example.com' }), 0);
  });

  it('never links to a pre-added member of another family', async () => {
    const a = await registerFamilyAdmin();
    const b = await registerFamilyAdmin({ family: { name: 'Other Family' } });
    const foreign = await preAddMember(b.family.id, { email: 'cross.family@example.com' });
    const { member } = assertOk(await register(joinBody(a.family.inviteCode, { email: 'cross.family@example.com' })), 201);
    assert.notEqual(member.id, String(foreign._id));
    assert.equal(member.familyId, a.family.id);
    const untouched = await Member.findById(foreign._id).lean();
    assert.equal(untouched.userId, null);
  });

  it('age gate: a minor needs a pre-added profile with guardian consent', async () => {
    const admin = await registerFamilyAdmin();
    const minorDob = yearsAgo(consentAge('IN') - 4);

    // Self-registration of a minor → 422, no account.
    const res = await register(joinBody(admin.family.inviteCode, { email: 'kid.self@example.com', dateOfBirth: minorDob }));
    assertError(res, 422, 'GUARDIAN_CONSENT_REQUIRED');
    assert.equal(await User.countDocuments({ email: 'kid.self@example.com' }), 0);

    // Pre-added without consent (DOB on the profile) → still 422.
    await preAddMember(admin.family.id, { email: 'kid.noconsent@example.com', dateOfBirth: new Date(minorDob) });
    assertError(
      await register(joinBody(admin.family.inviteCode, { email: 'kid.noconsent@example.com', dateOfBirth: null })),
      422,
      'GUARDIAN_CONSENT_REQUIRED',
    );

    // Pre-added by the admin with guardian consent → linked.
    const pre = await preAddMember(admin.family.id, {
      email: 'kid.consent@example.com',
      dateOfBirth: new Date(minorDob),
      guardianConsent: true,
      guardianConsentAt: new Date(),
    });
    const { member } = assertOk(await register(joinBody(admin.family.inviteCode, { email: 'kid.consent@example.com', dateOfBirth: minorDob })), 201);
    assert.equal(member.id, String(pre._id));
    assert.equal(member.guardianConsent, true);
  });
});

// ---------------------------------------------------------------- login

describe('POST /auth/login', () => {
  it('returns { user, tokens } and records the login', async () => {
    const admin = await registerFamilyAdmin();
    const res = await login(`  ${admin.user.email.toUpperCase()} `);
    const data = assertOk(res);
    assertNoSecrets(res.body);
    assert.deepEqual(Object.keys(data).sort(), ['tokens', 'user']);
    assert.equal(data.user.id, admin.user.id);
    assert.equal(data.user.role, 'admin');
    assert.equal(data.user.familyId, admin.family.id);
    assert.equal(data.user.memberId, admin.member.id);
    assertTokens(data.tokens);
    const doc = await User.findById(admin.user.id).lean();
    assert.ok(doc.lastLoginAt instanceof Date);
    assertOk(await me(authHeader(data.tokens)));
  });

  it('unverified users can log in', async () => {
    const admin = await registerFamilyAdmin();
    const { user } = assertOk(await login(admin.user.email));
    assert.equal(user.emailVerified, false);
  });

  it('wrong password and unknown e-mail give the same 401 INVALID_CREDENTIALS', async () => {
    const admin = await registerFamilyAdmin();
    const wrong = assertError(await login(admin.user.email, 'wrong-pass1'), 401, 'INVALID_CREDENTIALS');
    const unknown = assertError(await login(uniqueEmail('ghost')), 401, 'INVALID_CREDENTIALS');
    assert.equal(wrong.message, unknown.message);
    assert.equal(wrong.details, undefined);
    assert.equal(unknown.details, undefined);
  });

  it('validates the body', async () => {
    assertValidation(await request.post(`${API}/auth/login`).send({ email: 'x@example.com' }), 'password');
    assertValidation(await request.post(`${API}/auth/login`).send({ email: 'nope', password: 'secret123' }), 'email');
    assertValidation(await request.post(`${API}/auth/login`).send({}), 'email', 'password');
  });

  it('locks the account after 5 failures in 15 min (429 + retryAfterSeconds)', async () => {
    const admin = await registerFamilyAdmin();
    for (let i = 1; i <= 4; i += 1) assertError(await login(admin.user.email, `bad-pass${i}`), 401, 'INVALID_CREDENTIALS');
    const fifth = await login(admin.user.email, 'bad-pass5');
    const error = assertError(fifth, 429, 'TOO_MANY_REQUESTS');
    assert.ok(error.details.retryAfterSeconds > 890 && error.details.retryAfterSeconds <= 900, String(error.details.retryAfterSeconds));
    assert.equal(fifth.headers['retry-after'], String(error.details.retryAfterSeconds));

    // Even the right password is refused while locked.
    const locked = assertError(await login(admin.user.email), 429, 'TOO_MANY_REQUESTS');
    assert.ok(locked.details.retryAfterSeconds <= error.details.retryAfterSeconds);

    // After the lock ends the right password works and the counters are cleared.
    await User.updateOne({ _id: admin.user.id }, { $set: { lockUntil: minutesAgo(1) } });
    assertOk(await login(admin.user.email));
    const doc = await User.findById(admin.user.id).lean();
    assert.equal(doc.failedLoginCount, 0);
    assert.equal(doc.lockUntil, null);
    assert.equal(doc.lastFailedLoginAt, null);
  });

  it('failures older than 15 min do not count', async () => {
    const admin = await registerFamilyAdmin();
    for (let i = 0; i < 4; i += 1) assertError(await login(admin.user.email, 'bad-pass0'), 401, 'INVALID_CREDENTIALS');
    await User.updateOne({ _id: admin.user.id }, { $set: { lastFailedLoginAt: minutesAgo(16) } });
    assertError(await login(admin.user.email, 'bad-pass0'), 401, 'INVALID_CREDENTIALS');
    const doc = await User.findById(admin.user.id).lean();
    assert.equal(doc.failedLoginCount, 1, 'a new window started');
  });

  it('a successful login resets the failure counter', async () => {
    const admin = await registerFamilyAdmin();
    for (let i = 0; i < 3; i += 1) await login(admin.user.email, 'bad-pass0');
    assertOk(await login(admin.user.email));
    for (let i = 0; i < 4; i += 1) assertError(await login(admin.user.email, 'bad-pass0'), 401, 'INVALID_CREDENTIALS');
  });

  it('unknown e-mails are "locked" the same way (no enumeration through the lockout)', async () => {
    const email = uniqueEmail('ghost');
    for (let i = 0; i < 4; i += 1) assertError(await login(email, 'bad-pass0'), 401, 'INVALID_CREDENTIALS');
    const error = assertError(await login(email, 'bad-pass0'), 429, 'TOO_MANY_REQUESTS');
    assert.ok(error.details.retryAfterSeconds > 890);
    assertError(await login(email, 'bad-pass0'), 429, 'TOO_MANY_REQUESTS');
  });

  it('a user removed from the family logs in with familyId null', async () => {
    const admin = await registerFamilyAdmin();
    const joined = await joinFamilyAs(admin.family.inviteCode);
    await User.updateOne({ _id: joined.user.id }, { $set: { familyId: null, memberId: null } });
    const { user } = assertOk(await login(joined.user.email));
    assert.equal(user.familyId, null);
    assert.equal(user.memberId, null);
    assert.equal(user.role, null);
  });

  it('a stale membership (member row gone) is reported as no family', async () => {
    const admin = await registerFamilyAdmin();
    const joined = await joinFamilyAs(admin.family.inviteCode);
    await Member.deleteOne({ _id: joined.member.id });
    const { user } = assertOk(await login(joined.user.email));
    assert.equal(user.familyId, null);
    assert.equal(user.memberId, null);
    assert.equal(user.role, null);
  });
});

// ---------------------------------------------------------------- refresh

describe('POST /auth/refresh', () => {
  it('rotates the refresh token (old one stops working)', async () => {
    const admin = await registerFamilyAdmin();
    const { tokens } = assertOk(await refresh(admin.tokens.refreshToken));
    assertTokens(tokens);
    assert.notEqual(tokens.refreshToken, admin.tokens.refreshToken);
    assertOk(await me(authHeader(tokens)));
    const again = assertOk(await refresh(tokens.refreshToken));
    assertTokens(again.tokens);
  });

  it('reusing a rotated token revokes every session of the user', async () => {
    const admin = await registerFamilyAdmin();
    const other = assertOk(await login(admin.user.email)).tokens;
    const rotated = assertOk(await refresh(admin.tokens.refreshToken)).tokens;
    assertError(await refresh(admin.tokens.refreshToken), 401, 'INVALID_REFRESH_TOKEN');
    assertError(await refresh(rotated.refreshToken), 401, 'INVALID_REFRESH_TOKEN');
    assertError(await refresh(other.refreshToken), 401, 'INVALID_REFRESH_TOKEN');
  });

  it('unknown / missing / malformed tokens', async () => {
    assertError(await refresh('x'.repeat(64)), 401, 'INVALID_REFRESH_TOKEN');
    assertValidation(await request.post(`${API}/auth/refresh`).send({}), 'refreshToken');
    assertValidation(await request.post(`${API}/auth/refresh`).send({ refreshToken: 12345 }), 'refreshToken');
    assertValidation(await request.post(`${API}/auth/refresh`).send({ refreshToken: '   ' }), 'refreshToken');
  });

  it('an expired refresh token is rejected', async () => {
    const admin = await registerFamilyAdmin();
    await RefreshToken.updateMany({ userId: admin.user.id }, { $set: { expiresAt: minutesAgo(1) } });
    assertError(await refresh(admin.tokens.refreshToken), 401, 'INVALID_REFRESH_TOKEN');
  });
});

// ---------------------------------------------------------------- logout

describe('POST /auth/logout', () => {
  it('revokes the refresh token and removes the given push device', async () => {
    const admin = await registerFamilyAdmin();
    await Device.create({ userId: admin.user.id, token: 'fcm-token-a', platform: 'android' });
    await Device.create({ userId: admin.user.id, token: 'fcm-token-b', platform: 'ios' });

    const res = await request
      .post(`${API}/auth/logout`)
      .set(admin.auth)
      .send({ refreshToken: admin.tokens.refreshToken, deviceToken: 'fcm-token-a' });
    assert.equal(assertOk(res), null);
    assertError(await refresh(admin.tokens.refreshToken), 401, 'INVALID_REFRESH_TOKEN');
    assert.equal(await Device.countDocuments({ token: 'fcm-token-a' }), 0);
    assert.equal(await Device.countDocuments({ token: 'fcm-token-b' }), 1, 'other devices stay');
  });

  it('is idempotent and works without a device token', async () => {
    const admin = await registerFamilyAdmin();
    const body = { refreshToken: admin.tokens.refreshToken };
    assertOk(await request.post(`${API}/auth/logout`).set(admin.auth).send(body));
    assertOk(await request.post(`${API}/auth/logout`).set(admin.auth).send({ ...body, deviceToken: null }));
  });

  it("never revokes another user's token or device", async () => {
    const a = await registerFamilyAdmin();
    const b = await registerFamilyAdmin({ family: { name: 'Other Family' } });
    await Device.create({ userId: a.user.id, token: 'fcm-token-of-a', platform: 'android' });
    assertOk(
      await request.post(`${API}/auth/logout`).set(b.auth).send({ refreshToken: a.tokens.refreshToken, deviceToken: 'fcm-token-of-a' }),
    );
    assertOk(await refresh(a.tokens.refreshToken));
    assert.equal(await Device.countDocuments({ token: 'fcm-token-of-a' }), 1);
  });

  it('requires authentication and a refresh token', async () => {
    const admin = await registerFamilyAdmin();
    assertError(await request.post(`${API}/auth/logout`).send({ refreshToken: admin.tokens.refreshToken }), 401, 'UNAUTHORIZED');
    assertValidation(await request.post(`${API}/auth/logout`).set(admin.auth).send({}), 'refreshToken');
  });
});

// ---------------------------------------------------------------- verify e-mail / resend

describe('POST /auth/verify-email', () => {
  const verify = (auth, otp) => request.post(`${API}/auth/verify-email`).set(auth).send({ otp });

  it('verifies with the e-mailed code (spaces ignored) and consumes it', async () => {
    const admin = await registerFamilyAdmin();
    const code = lastOtpFor(admin.user.email);
    const res = await verify(admin.auth, `${code.slice(0, 3)} ${code.slice(3)}`);
    const { user } = assertOk(res);
    assertNoSecrets(res.body);
    assert.equal(user.emailVerified, true);
    assert.equal(user.role, 'admin');
    assert.equal(user.familyId, admin.family.id);
    assert.equal((await User.findById(admin.user.id).lean()).emailVerified, true);
    assert.equal(await Otp.countDocuments({ email: admin.user.email, purpose: 'verify_email' }), 0);
    assert.equal(assertOk(await me(admin.auth)).user.emailVerified, true);
  });

  it('is idempotent once verified', async () => {
    const admin = await registerFamilyAdmin();
    assertOk(await verify(admin.auth, lastOtpFor(admin.user.email)));
    const { user } = assertOk(await verify(admin.auth, '000000'));
    assert.equal(user.emailVerified, true);
  });

  it('wrong code → 400 INVALID_OTP; after 5 attempts even the right code → OTP_EXPIRED', async () => {
    const admin = await registerFamilyAdmin();
    const code = lastOtpFor(admin.user.email);
    const wrong = code === '111111' ? '222222' : '111111';
    for (let i = 0; i < 5; i += 1) assertError(await verify(admin.auth, wrong), 400, 'INVALID_OTP');
    assertError(await verify(admin.auth, code), 400, 'OTP_EXPIRED');
    assert.equal((await User.findById(admin.user.id).lean()).emailVerified, false);
  });

  it('an expired code → 400 OTP_EXPIRED; no code at all → OTP_EXPIRED', async () => {
    const admin = await registerFamilyAdmin();
    const code = lastOtpFor(admin.user.email);
    await Otp.updateOne({ email: admin.user.email, purpose: 'verify_email' }, { $set: { expiresAt: minutesAgo(1) } });
    assertError(await verify(admin.auth, code), 400, 'OTP_EXPIRED');
    await Otp.deleteMany({});
    assertError(await verify(admin.auth, code), 400, 'OTP_EXPIRED');
  });

  it('validates the code format and requires authentication', async () => {
    const admin = await registerFamilyAdmin();
    assertValidation(await verify(admin.auth, '12345'), 'otp');
    assertValidation(await verify(admin.auth, 'abcdef'), 'otp');
    assertValidation(await request.post(`${API}/auth/verify-email`).set(admin.auth).send({}), 'otp');
    assertError(await request.post(`${API}/auth/verify-email`).send({ otp: '123456' }), 401, 'UNAUTHORIZED');
  });

  it('works for a user without a family', async () => {
    const admin = await registerFamilyAdmin();
    await User.updateOne({ _id: admin.user.id }, { $set: { familyId: null, memberId: null } });
    const { user } = assertOk(await verify(admin.auth, lastOtpFor(admin.user.email)));
    assert.equal(user.emailVerified, true);
    assert.equal(user.familyId, null);
  });
});

describe('POST /auth/resend-verification', () => {
  const resend = (auth) => request.post(`${API}/auth/resend-verification`).set(auth).send();

  it('enforces the 60 s cooldown with 429 + retryAfterSeconds', async () => {
    const admin = await registerFamilyAdmin();
    const res = await resend(admin.auth);
    const error = assertError(res, 429, 'TOO_MANY_REQUESTS');
    assert.ok(error.details.retryAfterSeconds >= 1 && error.details.retryAfterSeconds <= 60);
    assert.equal(res.headers['retry-after'], String(error.details.retryAfterSeconds));
    assert.equal(outbox.filter((m) => m.to === admin.user.email).length, 1, 'no second e-mail');
  });

  it('after the cooldown sends a new code; the old one stops working', async () => {
    const admin = await registerFamilyAdmin();
    const oldCode = lastOtpFor(admin.user.email);
    // 3 wrong guesses on the current code → the cooldown is 3 × 3 min (see the hardening tests).
    await Otp.updateOne(
      { email: admin.user.email, purpose: 'verify_email' },
      { $set: { lastSentAt: new Date(Date.now() - 9 * 60_000 - 1000), attempts: 3 } },
    );
    assert.deepEqual(assertOk(await resend(admin.auth)), { sent: true, retryAfterSeconds: 60 });
    const newCode = lastOtpFor(admin.user.email);
    assert.equal(outbox.filter((m) => m.to === admin.user.email).length, 2);
    const row = await Otp.findOne({ email: admin.user.email, purpose: 'verify_email' }).lean();
    assert.equal(row.attempts, 0, 'attempts reset');

    if (oldCode !== newCode) {
      assertError(await request.post(`${API}/auth/verify-email`).set(admin.auth).send({ otp: oldCode }), 400, 'INVALID_OTP');
    }
    const { user } = assertOk(await request.post(`${API}/auth/verify-email`).set(admin.auth).send({ otp: newCode }));
    assert.equal(user.emailVerified, true);
  });

  it('a code row without lastSentAt never blocks a resend', async () => {
    const admin = await registerFamilyAdmin();
    await Otp.collection.updateOne({ email: admin.user.email, purpose: 'verify_email' }, { $set: { lastSentAt: null } });
    assert.deepEqual(assertOk(await resend(admin.auth)), { sent: true, retryAfterSeconds: 60 });
  });

  it('sends nothing when already verified', async () => {
    const admin = await registerFamilyAdmin();
    await User.updateOne({ _id: admin.user.id }, { $set: { emailVerified: true } });
    outbox.length = 0;
    assert.deepEqual(assertOk(await resend(admin.auth)), { sent: false, retryAfterSeconds: 0 });
    assert.equal(outbox.length, 0);
  });

  it('requires authentication', async () => {
    assertError(await request.post(`${API}/auth/resend-verification`).send(), 401, 'UNAUTHORIZED');
  });
});

// ---------------------------------------------------------------- forgot / reset password

describe('POST /auth/forgot-password', () => {
  const forgot = (email) => request.post(`${API}/auth/forgot-password`).send({ email });

  it('sends a reset code in the user locale', async () => {
    const admin = await registerFamilyAdmin({ locale: 'hi' });
    outbox.length = 0;
    assert.deepEqual(assertOk(await forgot(admin.user.email.toUpperCase())), { sent: true });
    const mail = lastMailTo(admin.user.email);
    assert.equal(mail.template, 'auth.resetPassword');
    assert.equal(mail.locale, 'hi');
    assert.match(lastOtpFor(admin.user.email), /^\d{6}$/);
    const row = await Otp.findOne({ email: admin.user.email, purpose: 'reset_password' }).lean();
    assert.equal(String(row.userId), admin.user.id);
  });

  it('answers the same for an unknown e-mail and sends nothing', async () => {
    const email = uniqueEmail('ghost');
    assert.deepEqual(assertOk(await forgot(email)), { sent: true });
    assert.equal(outbox.length, 0);
    const decoy = await Otp.findOne({ email, purpose: 'reset_password' }).lean();
    assert.ok(decoy, 'decoy row keeps reset-password behaviour identical');
    assert.equal(decoy.userId, null);
  });

  it('inside the cooldown answers { sent: true } without sending again', async () => {
    const admin = await registerFamilyAdmin();
    outbox.length = 0;
    assertOk(await forgot(admin.user.email));
    assert.deepEqual(assertOk(await forgot(admin.user.email)), { sent: true });
    assert.equal(outbox.length, 1);
  });

  it('validates the e-mail', async () => {
    assertValidation(await forgot('not-an-email'), 'email');
    assertValidation(await request.post(`${API}/auth/forgot-password`).send({}), 'email');
  });
});

describe('POST /auth/reset-password', () => {
  const reset = (body) => request.post(`${API}/auth/reset-password`).send(body);
  const NEW_PASSWORD = 'brandNew42';

  async function requestReset(email) {
    assertOk(await request.post(`${API}/auth/forgot-password`).send({ email }));
    return lastOtpFor(email);
  }

  it('sets the new password and ends every session', async () => {
    const admin = await registerFamilyAdmin();
    const second = assertOk(await login(admin.user.email)).tokens;
    const code = await requestReset(admin.user.email);

    assert.deepEqual(assertOk(await reset({ email: admin.user.email, otp: code, newPassword: NEW_PASSWORD })), { reset: true });
    assertError(await refresh(admin.tokens.refreshToken), 401, 'INVALID_REFRESH_TOKEN');
    assertError(await refresh(second.refreshToken), 401, 'INVALID_REFRESH_TOKEN');
    assertError(await login(admin.user.email), 401, 'INVALID_CREDENTIALS');

    const fresh = assertOk(await login(admin.user.email, NEW_PASSWORD)).tokens;
    // A stale device presenting its old token must not kill the new session.
    assertError(await refresh(second.refreshToken), 401, 'INVALID_REFRESH_TOKEN');
    assertOk(await refresh(fresh.refreshToken));
  });

  it('unlocks the account, marks the e-mail verified and is single use', async () => {
    const admin = await registerFamilyAdmin();
    await User.updateOne({ _id: admin.user.id }, { $set: { lockUntil: new Date(Date.now() + 600_000), failedLoginCount: 0 } });
    const code = await requestReset(admin.user.email);
    assertOk(await reset({ email: admin.user.email, otp: code, newPassword: NEW_PASSWORD }));
    const doc = await User.findById(admin.user.id).lean();
    assert.equal(doc.lockUntil, null);
    assert.equal(doc.emailVerified, true);
    assertOk(await login(admin.user.email, NEW_PASSWORD));
    assertError(await reset({ email: admin.user.email, otp: code, newPassword: 'another42' }), 400, 'OTP_EXPIRED');
  });

  it('wrong code → INVALID_OTP, and the same answers for known and unknown e-mails', async () => {
    const admin = await registerFamilyAdmin();
    const ghost = uniqueEmail('ghost');
    const body = (email) => ({ email, otp: '000000', newPassword: NEW_PASSWORD });

    // No code requested: identical answers.
    assertError(await reset(body(admin.user.email)), 400, 'OTP_EXPIRED');
    assertError(await reset(body(ghost)), 400, 'OTP_EXPIRED');

    // Code requested: 5 × INVALID_OTP, then OTP_EXPIRED — for both.
    const real = await requestReset(admin.user.email);
    await request.post(`${API}/auth/forgot-password`).send({ email: ghost });
    const wrong = real === '000000' ? '111111' : '000000';
    for (const email of [admin.user.email, ghost]) {
      for (let i = 0; i < 5; i += 1) assertError(await reset({ ...body(email), otp: wrong }), 400, 'INVALID_OTP');
      assertError(await reset({ ...body(email), otp: wrong }), 400, 'OTP_EXPIRED');
    }
    assertError(await reset({ ...body(admin.user.email), otp: real }), 400, 'OTP_EXPIRED');
    assertOk(await login(admin.user.email), 200);
  });

  it('an expired code → OTP_EXPIRED', async () => {
    const admin = await registerFamilyAdmin();
    const code = await requestReset(admin.user.email);
    await Otp.updateOne({ email: admin.user.email, purpose: 'reset_password' }, { $set: { expiresAt: minutesAgo(1) } });
    assertError(await reset({ email: admin.user.email, otp: code, newPassword: NEW_PASSWORD }), 400, 'OTP_EXPIRED');
  });

  it('a code issued before the account existed (decoy) never resets it', async () => {
    const email = uniqueEmail('late');
    assertOk(await request.post(`${API}/auth/forgot-password`).send({ email }));
    await registerFamilyAdmin({ email });
    // Force-match the decoy row to prove the userId check (the real code is never sent).
    const { sha256 } = await import('../src/lib/crypto.js');
    const { env } = await import('../src/config/env.js');
    await Otp.updateOne(
      { email, purpose: 'reset_password' },
      { $set: { codeHash: sha256(`otp:v1:reset_password:${email}:123456:${env.JWT_ACCESS_SECRET}`) } },
    );
    assertError(await reset({ email, otp: '123456', newPassword: NEW_PASSWORD }), 400, 'INVALID_OTP');
    assertOk(await login(email));
  });

  it('validates the body', async () => {
    assertValidation(await reset({ email: 'x@example.com', otp: '123456', newPassword: 'short' }), 'newPassword');
    assertValidation(await reset({ email: 'x@example.com', otp: '12', newPassword: NEW_PASSWORD }), 'otp');
    assertValidation(await reset({ otp: '123456', newPassword: NEW_PASSWORD }), 'email');
  });
});

// ---------------------------------------------------------------- change password

describe('POST /auth/change-password', () => {
  const change = (auth, body) => request.post(`${API}/auth/change-password`).set(auth).send(body);

  it('changes the password, ends other sessions and returns fresh tokens', async () => {
    const admin = await registerFamilyAdmin();
    const other = assertOk(await login(admin.user.email)).tokens;
    const data = assertOk(await change(admin.auth, { currentPassword: DEFAULT_PASSWORD, newPassword: 'changed99' }));
    assert.equal(data.changed, true);
    assertTokens(data.tokens);

    assertError(await refresh(admin.tokens.refreshToken), 401, 'INVALID_REFRESH_TOKEN');
    assertError(await refresh(other.refreshToken), 401, 'INVALID_REFRESH_TOKEN');
    assertOk(await refresh(data.tokens.refreshToken), 200);
    assertOk(await me(authHeader(data.tokens)));
    assertError(await login(admin.user.email), 401, 'INVALID_CREDENTIALS');
    assertOk(await login(admin.user.email, 'changed99'));
  });

  it('wrong current password → 401 INVALID_CREDENTIALS and counts towards the lockout', async () => {
    const admin = await registerFamilyAdmin();
    const body = { currentPassword: 'wrong-pass1', newPassword: 'changed99' };
    for (let i = 0; i < 4; i += 1) assertError(await change(admin.auth, body), 401, 'INVALID_CREDENTIALS');
    assertError(await change(admin.auth, body), 429, 'TOO_MANY_REQUESTS');
    assertError(await change(admin.auth, { ...body, currentPassword: DEFAULT_PASSWORD }), 429, 'TOO_MANY_REQUESTS');
    assertOk(await refresh(admin.tokens.refreshToken), 200);
  });

  it('validates the new password', async () => {
    const admin = await registerFamilyAdmin();
    assertValidation(await change(admin.auth, { currentPassword: DEFAULT_PASSWORD, newPassword: DEFAULT_PASSWORD }), 'newPassword');
    assertValidation(await change(admin.auth, { currentPassword: DEFAULT_PASSWORD, newPassword: 'short' }), 'newPassword');
    assertValidation(await change(admin.auth, { newPassword: 'changed99' }), 'currentPassword');
  });

  it('requires authentication', async () => {
    assertError(
      await request.post(`${API}/auth/change-password`).send({ currentPassword: DEFAULT_PASSWORD, newPassword: 'changed99' }),
      401,
      'UNAUTHORIZED',
    );
  });
});

// ---------------------------------------------------------------- me

describe('GET /auth/me', () => {
  it('admin: user, member and family (with invite code)', async () => {
    const admin = await registerFamilyAdmin();
    await joinFamilyAs(admin.family.inviteCode);
    const res = await me(admin.auth);
    const data = assertOk(res);
    assertNoSecrets(res.body);
    assert.deepEqual(Object.keys(data).sort(), ['family', 'member', 'user']);
    assert.equal(data.user.id, admin.user.id);
    assert.equal(data.user.role, 'admin');
    assert.equal(data.member.id, admin.member.id);
    assert.equal(data.family.id, admin.family.id);
    assert.equal(data.family.inviteCode, admin.family.inviteCode);
    assert.equal(data.family.memberCount, 2);
  });

  it('member: no invite code', async () => {
    const admin = await registerFamilyAdmin();
    const joined = await joinFamilyAs(admin.family.inviteCode);
    const data = assertOk(await me(joined.auth));
    assert.equal(data.user.role, 'member');
    assert.equal(data.member.role, 'member');
    assert.equal(data.family.inviteCode, null);
  });

  it('families are isolated', async () => {
    const a = await registerFamilyAdmin();
    await joinFamilyAs(a.family.inviteCode);
    const b = await registerFamilyAdmin({ family: { name: 'Other Family' } });
    const data = assertOk(await me(b.auth));
    assert.equal(data.family.id, b.family.id);
    assert.equal(data.family.memberCount, 1);
    assert.notEqual(data.family.inviteCode, a.family.inviteCode);
  });

  it('user without a family: member and family are null', async () => {
    const admin = await registerFamilyAdmin();
    await User.updateOne({ _id: admin.user.id }, { $set: { familyId: null, memberId: null } });
    const data = assertOk(await me(admin.auth));
    assert.equal(data.member, null);
    assert.equal(data.family, null);
    assert.equal(data.user.familyId, null);
    assert.equal(data.user.memberId, null);
    assert.equal(data.user.role, null);
  });

  it('401 without / with a bad token', async () => {
    assertError(await request.get(`${API}/auth/me`), 401, 'UNAUTHORIZED');
    assertError(await request.get(`${API}/auth/me`).set({ Authorization: 'Bearer nope' }), 401, 'UNAUTHORIZED');
  });
});

// ---------------------------------------------------------------- i18n

describe('auth translations (en)', () => {
  it('has every key the module uses', () => {
    for (const key of [
      'auth.email.verifyEmail.subject',
      'auth.email.verifyEmail.text',
      'auth.email.resetPassword.subject',
      'auth.email.resetPassword.text',
      'auth.email.passwordChanged.subject',
      'auth.email.passwordChanged.text',
      'auth.push.memberJoined.title',
      'auth.push.memberJoined.body',
      'auth.errors.guardianConsentRequired',
    ]) {
      assert.ok(hasTranslation(key, 'en'), key);
    }
  });

  it('renders the e-mails with code, validity and greeting', () => {
    for (const template of ['auth.verifyEmail', 'auth.resetPassword']) {
      const mail = renderTemplate({ locale: 'en', template, vars: { name: 'Amit', code: '482913', minutes: 10 } });
      assert.ok(mail.text.includes('482913'), template);
      assert.ok(mail.text.includes('10 minutes'), template);
      assert.ok(mail.text.includes('Amit'), template);
      assert.ok(!mail.subject.includes('{'), 'no unfilled placeholders');
      assert.ok(!mail.text.includes('{'), 'no unfilled placeholders');
    }
    assert.equal(t('en', 'auth.push.memberJoined.body', { name: 'Priya', familyName: 'Sharma Family' }), 'Priya joined Sharma Family.');
    const changed = renderTemplate({ locale: 'en', template: 'auth.passwordChanged', vars: { name: 'Amit' } });
    assert.ok(changed.text.includes('Amit'));
    assert.ok(changed.text.includes('Forgot password'));
    assert.ok(!changed.subject.includes('{') && !changed.text.includes('{'), 'no unfilled placeholders');
  });
});

// ================================================================ hardening (b-auth-harden)
//
// Every test below reproduces an attack or edge case found in the adversarial review
// (docs/progress/b-auth.md "Hardening review"). Each one failed — or documents a guarantee
// that had no test — before the fix.

const statusCounts = (responses) =>
  responses.reduce((acc, r) => ({ ...acc, [r.status]: (acc[r.status] ?? 0) + 1 }), {});

describe('hardening: lockout cannot be bypassed with parallel requests', () => {
  it('12 parallel wrong logins → only 5 passwords are tested (4 × 401, then 429)', async () => {
    const admin = await registerFamilyAdmin();
    const res = await Promise.all(Array.from({ length: 12 }, (_, i) => login(admin.user.email, `wrong-pass${i}`)));
    assert.deepEqual(statusCounts(res), { 401: 4, 429: 8 });
    for (const r of res.filter((x) => x.status === 429)) assert.ok(r.body.error.details.retryAfterSeconds >= 1);
    // The account is locked now: even the right password waits.
    assertError(await login(admin.user.email), 429, 'TOO_MANY_REQUESTS');
    const doc = await User.findById(admin.user.id).lean();
    assert.ok(doc.lockUntil > new Date());
  });

  it('the right password inside a parallel burst of guesses cannot slip past the limit', async () => {
    const admin = await registerFamilyAdmin();
    for (let i = 0; i < 4; i += 1) assertError(await login(admin.user.email, 'bad-pass0'), 401, 'INVALID_CREDENTIALS');
    // One attempt left in the window: of these 6 parallel requests exactly one password is tested.
    const res = await Promise.all([
      ...Array.from({ length: 5 }, () => login(admin.user.email, 'bad-pass1')),
      login(admin.user.email),
    ]);
    const counts = statusCounts(res);
    assert.equal(counts[401], undefined, 'the only check left either succeeds or locks — never another 401');
    assert.ok((counts[200] ?? 0) <= 1);
    assert.equal((counts[200] ?? 0) + (counts[429] ?? 0), 6);
    const doc = await User.findById(admin.user.id).lean();
    if (counts[200]) assert.equal(doc.lockUntil, null, 'the right password won the last slot');
    else assert.ok(doc.lockUntil > new Date(), 'a wrong guess took the last slot and locked the account');
  });

  it('change-password guesses are bounded the same way', async () => {
    const admin = await registerFamilyAdmin();
    const res = await Promise.all(
      Array.from({ length: 10 }, (_, i) =>
        request.post(`${API}/auth/change-password`).set(admin.auth).send({ currentPassword: `guess${i}abc`, newPassword: 'another123' }),
      ),
    );
    assert.deepEqual(statusCounts(res), { 401: 4, 429: 6 });
    // Same counter as login: the stolen-access-token guesser locked the account.
    assertError(await login(admin.user.email), 429, 'TOO_MANY_REQUESTS');
  });

  it('unknown e-mails answer exactly like known ones under a parallel burst', async () => {
    const admin = await registerFamilyAdmin();
    const ghost = uniqueEmail('ghost');
    const known = await Promise.all(Array.from({ length: 9 }, () => login(admin.user.email, 'wrong-pass1')));
    const unknown = await Promise.all(Array.from({ length: 9 }, () => login(ghost, 'wrong-pass1')));
    assert.deepEqual(statusCounts(unknown), statusCounts(known));
    assertError(await login(ghost, 'wrong-pass1'), 429, 'TOO_MANY_REQUESTS');
  });

  it('a slow in-flight check can no longer erase the lock of an unknown e-mail', () => {
    const email = uniqueEmail('ghost');
    const attempts = Array.from({ length: 5 }, () => reservePhantomAttempt(email));
    assert.deepEqual(attempts, [1, 2, 3, 4, 5]);
    assert.throws(() => reservePhantomAttempt(email), { code: 'TOO_MANY_REQUESTS' }, 'all attempts of the window in use');
    assert.throws(() => failPhantomAttempt(email, 5), { code: 'TOO_MANY_REQUESTS' }, 'the 5th failure locks');
    // Attempts 1–4 finishing after the lock only answer 401 — the lock stays.
    for (const n of [1, 2, 3, 4]) assert.throws(() => failPhantomAttempt(email, n), { code: 'INVALID_CREDENTIALS' });
    assert.throws(() => reservePhantomAttempt(email), (err) => err.code === 'TOO_MANY_REQUESTS' && err.details.retryAfterSeconds > 890);
  });

  it('a correct password clears the window; the lock ends after 15 min', async () => {
    const admin = await registerFamilyAdmin();
    for (let i = 0; i < 4; i += 1) await login(admin.user.email, 'bad-pass0');
    assertOk(await login(admin.user.email));
    let doc = await User.findById(admin.user.id).lean();
    assert.equal(doc.failedLoginCount, 0);
    assert.equal(doc.lastFailedLoginAt, null);
    for (let i = 0; i < 5; i += 1) await login(admin.user.email, 'bad-pass0');
    await User.updateOne({ _id: admin.user.id }, { $set: { lockUntil: minutesAgo(0.1) } });
    assertOk(await login(admin.user.email));
    doc = await User.findById(admin.user.id).lean();
    assert.equal(doc.lockUntil, null);
  });
});

describe('hardening: one-time code brute force', () => {
  const forgot = (email) => request.post(`${API}/auth/forgot-password`).send({ email });
  const reset = (email, otp) => request.post(`${API}/auth/reset-password`).send({ email, otp, newPassword: 'newpass123' });
  const resend = (auth) => request.post(`${API}/auth/resend-verification`).set(auth).send();
  const wrongCodeFor = (code) => (code === '000000' ? '111111' : '000000');

  it('the resend cooldown grows by 3 min per wrong guess (max 5 guesses per 15 min)', () => {
    assert.equal(cooldownMsFor({ attempts: 0 }), 60_000);
    assert.equal(cooldownMsFor({ attempts: 1 }), 3 * 60_000);
    assert.equal(cooldownMsFor({ attempts: 5 }), 15 * 60_000);
    assert.equal(cooldownMsFor(null), 60_000);
  });

  it('forgot-password: 4 wrong guesses + a new code after 61 s is no longer possible', async () => {
    const admin = await registerFamilyAdmin();
    const email = admin.user.email;
    assertOk(await forgot(email));
    const code = lastOtpFor(email);
    for (let i = 0; i < 4; i += 1) assertError(await reset(email, wrongCodeFor(code)), 400, 'INVALID_OTP');
    await Otp.updateOne({ email, purpose: 'reset_password' }, { $set: { lastSentAt: new Date(Date.now() - 61_000) } });
    outbox.length = 0;
    assert.deepEqual(assertOk(await forgot(email)), { sent: true }, 'still no enumeration');
    assert.equal(outbox.length, 0, 'no new code: 4 wrong guesses → 12 min cooldown');
    const row = await Otp.findOne({ email, purpose: 'reset_password' }).lean();
    assert.equal(row.attempts, 4, 'the guess counter was not reset');

    await Otp.updateOne({ email, purpose: 'reset_password' }, { $set: { lastSentAt: minutesAgo(12.1) } });
    assertOk(await forgot(email));
    assert.equal(outbox.length, 1, 'after the longer cooldown a new code is sent');
    assert.equal((await Otp.findOne({ email, purpose: 'reset_password' }).lean()).attempts, 0);
  });

  it('decoy codes of unknown e-mails follow the same rule (no enumeration)', async () => {
    const ghost = uniqueEmail('ghost');
    assertOk(await forgot(ghost));
    for (let i = 0; i < 2; i += 1) assertError(await reset(ghost, '123456'), 400, 'INVALID_OTP');
    await Otp.updateOne({ email: ghost }, { $set: { lastSentAt: new Date(Date.now() - 61_000) } });
    assertOk(await forgot(ghost));
    assert.equal((await Otp.findOne({ email: ghost }).lean()).attempts, 2, 'still inside the 6 min cooldown');
  });

  it('resend-verification answers 429 with the longer wait after wrong guesses', async () => {
    const admin = await registerFamilyAdmin();
    const code = lastOtpFor(admin.user.email);
    for (let i = 0; i < 2; i += 1) {
      assertError(await request.post(`${API}/auth/verify-email`).set(admin.auth).send({ otp: wrongCodeFor(code) }), 400, 'INVALID_OTP');
    }
    await Otp.updateOne({ email: admin.user.email, purpose: 'verify_email' }, { $set: { lastSentAt: new Date(Date.now() - 61_000) } });
    const error = assertError(await resend(admin.auth), 429, 'TOO_MANY_REQUESTS');
    assert.ok(error.details.retryAfterSeconds > 290 && error.details.retryAfterSeconds <= 300, String(error.details.retryAfterSeconds));
  });

  it('two parallel resends after the cooldown send exactly one code', async () => {
    const admin = await registerFamilyAdmin();
    await Otp.updateOne({ email: admin.user.email, purpose: 'verify_email' }, { $set: { lastSentAt: new Date(Date.now() - 61_000) } });
    outbox.length = 0;
    const res = await Promise.all([resend(admin.auth), resend(admin.auth), resend(admin.auth)]);
    assert.deepEqual(statusCounts(res), { 200: 1, 429: 2 });
    assert.equal(outbox.length, 1);
    const { user } = assertOk(await request.post(`${API}/auth/verify-email`).set(admin.auth).send({ otp: lastOtpFor(admin.user.email) }));
    assert.equal(user.emailVerified, true);
  });

  it("another user's code never verifies my e-mail", async () => {
    const a = await registerFamilyAdmin();
    const b = await registerFamilyAdmin({ family: { name: 'B Family' } });
    const codeA = lastOtpFor(a.user.email);
    const codeB = lastOtpFor(b.user.email);
    if (codeA === codeB) return; // 1 in a million
    assertError(await request.post(`${API}/auth/verify-email`).set(b.auth).send({ otp: codeA }), 400, 'INVALID_OTP');
    assert.equal((await User.findById(b.user.id).lean()).emailVerified, false);
  });
});

describe('hardening: sessions', () => {
  it('replaying a logged-out refresh token does not sign the user out on other devices', async () => {
    const admin = await registerFamilyAdmin();
    const phone2 = assertOk(await login(admin.user.email)).tokens;
    assertOk(await request.post(`${API}/auth/logout`).set(admin.auth).send({ refreshToken: admin.tokens.refreshToken }));
    assertError(await refresh(admin.tokens.refreshToken), 401, 'INVALID_REFRESH_TOKEN');
    assertOk(await refresh(phone2.refreshToken), 200);
  });

  it('logout with an already rotated token also ends the token it was rotated into', async () => {
    const admin = await registerFamilyAdmin();
    const phone2 = assertOk(await login(admin.user.email)).tokens;
    // The app refreshed but never received the answer, then logs out with the old token.
    const lost = assertOk(await refresh(admin.tokens.refreshToken)).tokens;
    const lost2 = assertOk(await refresh(lost.refreshToken)).tokens;
    assertOk(await request.post(`${API}/auth/logout`).set(admin.auth).send({ refreshToken: admin.tokens.refreshToken }));
    assertError(await refresh(lost2.refreshToken), 401, 'INVALID_REFRESH_TOKEN');
    assertOk(await refresh(phone2.refreshToken), 200);
    assert.equal(await RefreshToken.countDocuments({ userId: admin.user.id, revokedAt: null }), 1, 'only phone 2');
  });

  it('logout never walks into another user\'s tokens', async () => {
    const a = await registerFamilyAdmin();
    const b = await registerFamilyAdmin({ family: { name: 'B Family' } });
    const rotated = assertOk(await refresh(a.tokens.refreshToken)).tokens;
    assertOk(await request.post(`${API}/auth/logout`).set(b.auth).send({ refreshToken: a.tokens.refreshToken }));
    assertOk(await refresh(rotated.refreshToken), 200);
  });

  it('a very long rotation chain behind a logged-out token ends every session', async () => {
    const admin = await registerFamilyAdmin();
    const phone2 = assertOk(await login(admin.user.email)).tokens;
    let current = admin.tokens.refreshToken;
    for (let i = 0; i < 52; i += 1) current = assertOk(await refresh(current)).tokens.refreshToken;
    assertOk(await request.post(`${API}/auth/logout`).set(admin.auth).send({ refreshToken: admin.tokens.refreshToken }));
    assertError(await refresh(current), 401, 'INVALID_REFRESH_TOKEN');
    assertError(await refresh(phone2.refreshToken), 401, 'INVALID_REFRESH_TOKEN');
    assert.equal(await RefreshToken.countDocuments({ userId: admin.user.id }), 0);
  });

  it('a refresh that loses the race against a session wipe hands out no usable token', async () => {
    const admin = await registerFamilyAdmin();
    // Simulate the wipe landing between rotation and the post-check: the old row is "gone".
    const original = RefreshToken.exists;
    RefreshToken.exists = async () => null;
    let res;
    try {
      res = await refresh(admin.tokens.refreshToken);
    } finally {
      RefreshToken.exists = original;
    }
    assertError(res, 401, 'INVALID_REFRESH_TOKEN');
    assert.equal(await RefreshToken.countDocuments({ userId: admin.user.id, revokedAt: null }), 0, 'the new token was deleted');
  });

  it('an attacker refreshing a stolen token in a loop does not survive a password reset', async () => {
    const admin = await registerFamilyAdmin();
    const email = admin.user.email;
    await request.post(`${API}/auth/forgot-password`).send({ email });
    const code = lastOtpFor(email);
    let token = admin.tokens.refreshToken;
    let stop = false;
    const loop = (async () => {
      while (!stop) {
        const r = await refresh(token);
        if (r.status !== 200) return;
        token = r.body.data.tokens.refreshToken;
      }
    })();
    await new Promise((r) => setTimeout(r, 40));
    assertOk(await request.post(`${API}/auth/reset-password`).send({ email, otp: code, newPassword: 'fresh1234' }));
    await new Promise((r) => setTimeout(r, 60));
    stop = true;
    await loop;
    assertError(await refresh(token), 401, 'INVALID_REFRESH_TOKEN');
    assert.equal(await RefreshToken.countDocuments({ userId: admin.user.id, revokedAt: null }), 0);
  });

  it('reset and change password e-mail a "password changed" notice in the user locale', async () => {
    const admin = await registerFamilyAdmin({ locale: 'hi' });
    outbox.length = 0;
    assertOk(
      await request.post(`${API}/auth/change-password`).set(admin.auth).send({ currentPassword: DEFAULT_PASSWORD, newPassword: 'changed123' }),
    );
    let mail = lastMailTo(admin.user.email);
    assert.equal(mail.template, 'auth.passwordChanged');
    assert.equal(mail.locale, 'hi');
    assert.ok(!/\b\d{6}\b/.test(mail.text), 'no code in the notice');

    await request.post(`${API}/auth/forgot-password`).send({ email: admin.user.email });
    assertOk(
      await request
        .post(`${API}/auth/reset-password`)
        .send({ email: admin.user.email, otp: lastOtpFor(admin.user.email), newPassword: 'resetted123' }),
    );
    mail = lastMailTo(admin.user.email);
    assert.equal(mail.template, 'auth.passwordChanged');
    assert.equal(outbox.filter((m) => m.template === 'auth.passwordChanged').length, 2);
  });

  it('wrong current password sends no notice', async () => {
    const admin = await registerFamilyAdmin();
    outbox.length = 0;
    await request.post(`${API}/auth/change-password`).set(admin.auth).send({ currentPassword: 'wrong-pass1', newPassword: 'changed123' });
    assert.equal(outbox.length, 0);
  });
});

describe('hardening: access tokens', () => {
  const sign = (payload, secret = env.JWT_ACCESS_SECRET, opts = {}) =>
    jwt.sign(payload, secret, { algorithm: 'HS256', expiresIn: 60, issuer: JWT_ISSUER, audience: JWT_AUDIENCE, ...opts });

  it('forged, foreign, "none"-signed or dangling tokens are 401', async () => {
    const admin = await registerFamilyAdmin();
    const forged = [
      sign({}, 'not-the-secret', { subject: admin.user.id }),
      sign({}, env.JWT_ACCESS_SECRET, { subject: 'not-an-object-id' }),
      sign({ sub: { $ne: null } }),
      sign({}, env.JWT_ACCESS_SECRET, { subject: admin.user.id, issuer: 'someone-else' }),
      sign({}, env.JWT_ACCESS_SECRET, { subject: admin.user.id, audience: 'other-app' }),
      jwt.sign({ sub: admin.user.id }, '', { algorithm: 'none' }),
      sign({}, env.JWT_ACCESS_SECRET, { subject: '0123456789abcdef01234567' }),
    ];
    for (const token of forged) assertError(await me(authHeader(token)), 401, 'UNAUTHORIZED');
    const expired = sign({}, env.JWT_ACCESS_SECRET, { subject: admin.user.id, expiresIn: -10 });
    assertError(await me(authHeader(expired)), 401, 'TOKEN_EXPIRED');
  });
});

describe('hardening: input abuse', () => {
  it('NoSQL operators in any auth body are rejected before touching the database', async () => {
    const admin = await registerFamilyAdmin();
    const op = { $ne: null };
    assertValidation(await request.post(`${API}/auth/login`).send({ email: op, password: op }), 'email', 'password');
    assertValidation(await request.post(`${API}/auth/login`).send({ email: admin.user.email, password: { $gt: '' } }), 'password');
    assertValidation(await request.post(`${API}/auth/forgot-password`).send({ email: { $regex: '.*' } }), 'email');
    assertValidation(await request.post(`${API}/auth/reset-password`).send({ email: admin.user.email, otp: op, newPassword: 'x1234567' }), 'otp');
    assertValidation(await request.post(`${API}/auth/refresh`).send({ refreshToken: op }), 'refreshToken');
    assertValidation(await request.post(`${API}/auth/verify-email`).set(admin.auth).send({ otp: { $exists: true } }), 'otp');
    assertValidation(await register(joinBody({ $ne: null })), 'inviteCode');
    assertValidation(await request.post(`${API}/auth/logout`).set(admin.auth).send({ refreshToken: 'x', deviceToken: op }), 'deviceToken');
    const doc = await User.findById(admin.user.id).lean();
    assert.equal(doc.failedLoginCount, 0, 'nothing was even counted');
  });

  it('extra fields cannot assign role, family, verification or consent (mass assignment)', async () => {
    const admin = await registerFamilyAdmin();
    const other = await registerFamilyAdmin({ family: { name: 'Other' } });
    const extras = {
      role: 'admin',
      emailVerified: true,
      familyId: other.family.id,
      memberId: other.member.id,
      designation: 'CEO',
      guardianConsent: true,
      userId: other.user.id,
      passwordHash: '$2a$10$abcdefghijklmnopqrstuv',
    };
    const { user, member, family } = assertOk(await register(joinBody(admin.family.inviteCode, extras)), 201);
    assert.equal(member.role, 'member');
    assert.equal(user.role, 'member');
    assert.equal(user.emailVerified, false);
    assert.equal(family.id, admin.family.id);
    assert.equal(member.designation, null);
    assert.equal(member.guardianConsent, false);
    assert.equal(family.inviteCode, null, 'members never see the code');
    const doc = await User.findById(user.id).lean();
    assert.ok(await bcrypt.compare(DEFAULT_PASSWORD, doc.passwordHash));

    // `__proto__` / `constructor` keys sent as raw JSON (an object literal would not send them).
    const raw = JSON.stringify(joinBody(admin.family.inviteCode)).replace(
      /^\{/,
      '{"__proto__":{"role":"admin","emailVerified":true},"constructor":{"prototype":{"role":"admin"}},',
    );
    const polluted = assertOk(await request.post(`${API}/auth/register`).set('Content-Type', 'application/json').send(raw), 201);
    assert.equal(polluted.member.role, 'member');
    assert.equal(polluted.user.emailVerified, false);
    assert.equal({}.role, undefined, 'no prototype pollution');
    assert.equal({}.emailVerified, undefined, 'no prototype pollution');

    const created = assertOk(
      await register(createBody({ ...extras, family: { name: 'Mine', country: 'IN', currency: 'INR', timezone: 'Asia/Kolkata', ownerId: other.user.id, inviteCode: 'AAAAAAAA' } })),
      201,
    );
    assert.equal(created.family.ownerId, created.user.id);
    assert.notEqual(created.family.inviteCode, 'AAAAAAAA');
    assert.equal(created.user.emailVerified, false);
  });

  it('oversized bodies and strings are refused', async () => {
    const big = await request.post(`${API}/auth/login`).send({ email: 'a@example.com', password: 'x'.repeat(200_000) });
    assertError(big, 413, 'PAYLOAD_TOO_LARGE');
    assertValidation(await login('a@example.com', 'x'.repeat(129)), 'password');
    assertValidation(await refresh('x'.repeat(513)), 'refreshToken');
    assertValidation(await register(createBody({ name: 'a'.repeat(61) })), 'name');
    assertValidation(await register(createBody({ family: { name: 'f'.repeat(61) } })), 'family.name');
    assertValidation(await register(createBody({ email: `${'a'.repeat(300)}@example.com` })), 'email');
    // 72 UTF-8 bytes is the bcrypt limit: 19 × "😀" (4 bytes each) + "a1" is 78 bytes.
    assertValidation(await register(createBody({ password: `${'😀'.repeat(19)}a1` })), 'password');
    assertValidation(await request.post(`${API}/auth/verify-email`).send({ otp: '1'.repeat(100) }).set((await registerFamilyAdmin()).auth), 'otp');
  });

  it('wrong JSON types are 422, malformed JSON is 400', async () => {
    assertValidation(await register(createBody({ consentAccepted: 'true' })), 'consentAccepted');
    assertValidation(await register(createBody({ consentAccepted: 1 })), 'consentAccepted');
    assertValidation(await register(createBody({ dateOfBirth: 1e13 })), 'dateOfBirth');
    assertValidation(await register(createBody({ name: 12345 })), 'name');
    assertValidation(await register({ ...createBody(), family: ['IN'] }), 'family');
    assertValidation(await register({ ...createBody(), family: 'Sharma Family' }), 'family');
    assertValidation(await register(createBody({ mode: ['create'] })), 'mode');
    const malformed = await request.post(`${API}/auth/login`).set('Content-Type', 'application/json').send('{"email": "a@b.c",');
    assertError(malformed, 400, 'BAD_REQUEST');
  });
});

describe('hardening: names and unicode', () => {
  it('rejects control characters, bidi overrides and blank-looking names', async () => {
    const bad = ['Mom‮gnp.exe', 'Line1\nLine2', 'Nul\u0000byte', 'Tab\there', '​​', 'ㅤ', '⁦Isolate⁩', '...'];
    for (const name of bad) {
      assertValidation(await register(createBody({ name })), 'name');
      assertValidation(await register(createBody({ family: { name } })), 'family.name');
    }
    assert.equal(await User.countDocuments(), 0);
  });

  it('accepts names in every script, with emoji / ZWJ sequences, stored in NFC', async () => {
    const names = ['محمد علي', 'अमित शर्मा', 'অমিত', 'ਅਮਿਤ', 'அமித்', 'అమిత్', 'ಅಮಿತ್', 'അമിത്', 'José Müller', "O'Brien-Smith", '李小龙', 'Ana 👩‍👩‍👧', '🦁'];
    for (const name of names) {
      const { user, member } = assertOk(await register(createBody({ name, family: { name: `${name} family`.slice(0, 60) } })), 201);
      assert.equal(user.name, name.normalize('NFC'));
      assert.equal(member.name, name.normalize('NFC'));
    }
    const decomposed = 'José';
    const { user } = assertOk(await register(createBody({ name: decomposed })), 201);
    assert.equal(user.name, 'José', 'NFC');
  });

  it('passwords are Unicode-normalised (composed vs decomposed, full-width digits)', async () => {
    const admin = await registerFamilyAdmin({ password: 'cafépass1' });
    assertOk(await login(admin.user.email, 'cafépass1'), 200);
    assertOk(await login(admin.user.email, 'cafépass1'), 200);

    // Full-width digits from a CJK IME count as digits and match the ASCII form.
    const other = await registerFamilyAdmin({ password: 'ｐａｓｓｗｏｒｄ１２' });
    assertOk(await login(other.user.email, 'password12'), 200);
    assertError(await login(other.user.email, 'password13'), 401, 'INVALID_CREDENTIALS');
  });

  it('change-password treats a differently-encoded same password as unchanged', async () => {
    const admin = await registerFamilyAdmin({ password: 'cafépass1' });
    const res = await request
      .post(`${API}/auth/change-password`)
      .set(admin.auth)
      .send({ currentPassword: 'cafépass1', newPassword: 'cafépass1' });
    assertValidation(res, 'newPassword');
  });

  it('one-time codes typed with native digits (Arabic-Indic, Persian, Devanagari, full-width) work', async () => {
    assert.equal(toAsciiDigits('٤٨٢٩١٣'), '482913');
    assert.equal(toAsciiDigits('۴۸۲۹۱۳'), '482913');
    assert.equal(toAsciiDigits('४८२९१३'), '482913');
    assert.equal(toAsciiDigits('৪৮২৯১৩'), '482913');
    assert.equal(toAsciiDigits('４８２９１３'), '482913');
    assert.equal(toAsciiDigits('48-29 13'), '48-29 13');

    const admin = await registerFamilyAdmin({ locale: 'ar' });
    const code = lastOtpFor(admin.user.email);
    const arabic = [...code].map((d) => String.fromCharCode(0x0660 + Number(d))).join('');
    const { user } = assertOk(await request.post(`${API}/auth/verify-email`).set(admin.auth).send({ otp: arabic }));
    assert.equal(user.emailVerified, true);
    // Invite codes typed on the same keyboards (native digits, full-width letters, lower case).
    const devanagari = admin.family.inviteCode
      .toLowerCase()
      .replace(/[0-9]/g, (d) => String.fromCharCode(0x0966 + Number(d)));
    const joined = assertOk(await register(joinBody(`${devanagari.slice(0, 4)}-${devanagari.slice(4)}`)), 201);
    assert.equal(joined.family.id, admin.family.id);
    const fullWidth = [...admin.family.inviteCode].map((c) => String.fromCharCode(c.charCodeAt(0) + 0xfee0)).join('');
    assert.equal(assertOk(await register(joinBody(fullWidth)), 201).family.id, admin.family.id);
    // Thai digits are not a supported script → plain validation error, never a crash.
    assertValidation(await request.post(`${API}/auth/verify-email`).set(admin.auth).send({ otp: '๑๒๓๔๕๖' }), 'otp');
  });
});

describe('hardening: dates of birth and the consent age', () => {
  /** YYYY-MM-DD of "today" in a time zone. */
  function todayIn(timeZone) {
    return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
  }

  it('the birthday boundary is evaluated in the family time zone (local midnight sent as UTC)', async (t) => {
    const [y, m, d] = todayIn('Asia/Kolkata').split('-').map(Number);
    if (m === 2 && d === 29) return t.skip('leap day');
    const age = consentAge('IN');
    const pad = (n) => String(n).padStart(2, '0');
    const localMidnight = (yy, mm, dd) => {
      const date = new Date(Date.UTC(yy, mm - 1, dd));
      return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}T00:00:00.000+05:30`;
    };
    // Turns `age` today (local) → allowed; turns `age` tomorrow → still a minor.
    assertOk(await register(createBody({ dateOfBirth: new Date(localMidnight(y - age, m, d)).toISOString() })), 201);
    assertError(
      await register(createBody({ dateOfBirth: new Date(localMidnight(y - age, m, d + 1)).toISOString() })),
      422,
      'GUARDIAN_CONSENT_REQUIRED',
    );
  });

  it('invalid, impossible, far-past and future dates are rejected', async () => {
    for (const dateOfBirth of ['2010-02-30', '2010-13-01', 'yesterday', '1899-12-31T00:00:00.000Z', '9999-01-01', '2010-05-14T00:00:00', '']) {
      const res = await register(createBody({ dateOfBirth }));
      if (dateOfBirth === '') assertOk(res, 201); // blank = not given
      else assertValidation(res, 'dateOfBirth');
    }
    const tomorrow = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString();
    assertValidation(await register(createBody({ dateOfBirth: tomorrow })), 'dateOfBirth');
  });
});

describe('hardening: register races and ordering', () => {
  it('an e-mail that already has an account is 409 EMAIL_TAKEN, whatever the family says', async () => {
    const admin = await registerFamilyAdmin();
    const res = await register(joinBody(admin.family.inviteCode, { email: admin.user.email }));
    assertError(res, 409, 'EMAIL_TAKEN');
    const unknownCode = await register(joinBody('ZZZZZZZZ', { email: admin.user.email }));
    assertError(unknownCode, 409, 'EMAIL_TAKEN');
  });

  it('two parallel registrations with one e-mail create exactly one account', async () => {
    const body = createBody();
    const res = await Promise.all([register(body), register({ ...body, family: { ...body.family, name: 'Twin' } })]);
    assert.deepEqual(statusCounts(res), { 201: 1, 409: 1 });
    assert.equal(res.find((r) => r.status === 409).body.error.code, 'EMAIL_TAKEN');
    assert.equal(await User.countDocuments({ email: body.email }), 1);
    assert.equal(await Family.countDocuments(), 1, 'the loser left no family behind');
    assert.equal(await Member.countDocuments(), 1);
  });

  it('two people racing to claim the same pre-added profile: one wins, nothing dangles', async () => {
    const admin = await registerFamilyAdmin();
    const pre = await preAddMember(admin.family.id, { email: 'race.profile@example.com' });
    const res = await Promise.all([
      register(joinBody(admin.family.inviteCode, { email: 'race.profile@example.com' })),
      register(joinBody(admin.family.inviteCode, { email: 'race.profile@example.com', name: 'Impostor' })),
    ]);
    assert.equal(res.filter((r) => r.status === 201).length, 1);
    assert.equal(res.find((r) => r.status !== 201).status, 409);
    assert.equal(await User.countDocuments({ email: 'race.profile@example.com' }), 1);
    const linked = await Member.findById(pre._id).lean();
    const winner = await User.findOne({ email: 'race.profile@example.com' }).lean();
    assert.equal(String(linked.userId), String(winner._id));
    assert.equal(await Member.countDocuments({ familyId: admin.family.id }), 2);
  });

  it('a pre-added profile removed while linking → joins as a new member instead of a false 409', async () => {
    const admin = await registerFamilyAdmin();
    const pre = await preAddMember(admin.family.id, { email: 'vanishing@example.com' });
    const user = await User.create({ email: 'vanishing@example.com', passwordHash: 'x', name: 'Vani' });
    const original = Member.findOneAndUpdate;
    Member.findOneAndUpdate = async function patched(...args) {
      Member.findOneAndUpdate = original;
      await Member.deleteOne({ _id: pre._id }); // the admin deletes the profile right now
      return original.apply(this, args);
    };
    let result;
    try {
      result = await joinFamilyForUser(user.toObject(), admin.family.inviteCode);
    } finally {
      Member.findOneAndUpdate = original;
    }
    assert.equal(result.linked, false);
    assert.notEqual(String(result.member._id), String(pre._id));
    assert.equal(result.member.role, 'member');
    assert.equal(String(result.user.memberId), String(result.member._id));
  });

  it('a stale membership (member row gone) does not block creating or joining a family', async () => {
    const admin = await registerFamilyAdmin();
    const joined = await joinFamilyAs(admin.family.inviteCode);
    await Member.deleteOne({ _id: joined.member.id }); // user.familyId / memberId are now stale
    const stale = await User.findById(joined.user.id).lean();
    assert.ok(stale.familyId);

    const created = await createFamilyForUser(stale, { name: 'Fresh Start', country: 'DE', currency: 'EUR', timezone: 'Europe/Berlin' });
    assert.equal(String(created.user.familyId), String(created.family._id));
    assert.equal(created.member.role, 'admin');

    // A real membership still blocks.
    const current = await User.findById(joined.user.id).lean();
    await assert.rejects(joinFamilyForUser(current, admin.family.inviteCode), { code: 'ALREADY_IN_FAMILY' });
    await assert.rejects(
      createFamilyForUser(current, { name: 'Second', country: 'DE', currency: 'EUR', timezone: 'Europe/Berlin' }),
      { code: 'ALREADY_IN_FAMILY' },
    );
    assert.equal(await Family.countDocuments({ name: 'Second' }), 0);
  });

  it('member_joined goes only to this family\'s admins, in each device\'s language', async () => {
    const admin = await registerFamilyAdmin({ locale: 'hi' });
    const coAdmin = await joinFamilyAs(admin.family.inviteCode, { locale: 'ar' });
    await Member.updateOne({ _id: coAdmin.member.id }, { $set: { role: 'admin' } });
    const plainMember = await joinFamilyAs(admin.family.inviteCode);
    const foreign = await registerFamilyAdmin({ family: { name: 'Foreign' } });
    await Device.create([
      { userId: admin.user.id, token: 'tok-admin', platform: 'android', locale: 'hi' },
      { userId: coAdmin.user.id, token: 'tok-coadmin', platform: 'ios' },
      { userId: plainMember.user.id, token: 'tok-member', platform: 'android' },
      { userId: foreign.user.id, token: 'tok-foreign', platform: 'android' },
    ]);
    sentPushes.length = 0;
    const newcomer = await joinFamilyAs(admin.family.inviteCode, { name: 'Newbie' });
    await flushPushes();
    assert.equal(sentPushes.length, 1);
    const push = sentPushes[0];
    assert.equal(push.type, 'member_joined');
    assert.equal(push.route, `/members/${newcomer.member.id}`);
    assert.deepEqual([...push.memberIds].sort(), [admin.member.id, coAdmin.member.id].sort());
    const tokens = push.messages.map((m) => m.token).sort();
    assert.deepEqual(tokens, ['tok-admin', 'tok-coadmin']);
    assert.equal(push.messages.find((m) => m.token === 'tok-admin').locale, 'hi');
    assert.equal(push.messages.find((m) => m.token === 'tok-coadmin').locale, 'ar', 'falls back to the user locale');
    assert.ok(push.messages.every((m) => m.body.includes('Newbie')));
  });
});
