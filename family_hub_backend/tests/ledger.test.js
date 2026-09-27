/**
 * Ledger & savings goals: docs/03-API_CONTRACT.md §8 (`/ledger/entries`, `/ledger/summary`, `/goals`).
 *
 * Covers happy paths, the envelope and exact object shapes, minor-unit storage and rounding,
 * visibility (admin vs member vs other family), the permission matrix, 422 `details` for every body /
 * query rule, business dates in the family time zone (normalisation, month boundaries, "≤ today + 1
 * day"), goal-linked entry locks, summaries (family vs personal scope, `byCategory`), goal CRUD and
 * status transitions (achieved / reopened / archived / restored), contributions (atomic `$inc`,
 * exactly one `goal_achieved` push under concurrency, archived → 409), goal deletion detaching entries
 * and entry deletion decrementing the goal (never below 0).
 *
 * The `hardening:` suites at the end are the adversarial review (b-ledger-harden): UTF-16 text limits and
 * normalisation, operator injection, mass assignment, numeric / pagination / month bounds, target-date
 * window, the `goal_achieved` push throttle, recipients and locale, races and compensation, dangling
 * goal / member references and the family time-zone rebase.
 *
 * Managed profiles are inserted with the Member model so these tests do not depend on the family module.
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
import { after, afterEach, before, beforeEach, describe, it, mock } from 'node:test';

const { Device, Family, Goal, LedgerEntry, Member, User } = await import('../src/models/index.js');
const { GOAL_ACHIEVED_NOTIFY_COOLDOWN_MS } = await import('../src/modules/ledger/goals.balance.js');
const { currentMonth, zonedParts, zonedTimeToUtc } = await import('../src/lib/dates.js');
const { getMonthSummary, rebaseBusinessDates } = await import('../src/modules/ledger/ledger.service.js');
const { listActiveGoals } = await import('../src/modules/ledger/goals.service.js');
const { serializeEntry, serializeGoal } = await import('../src/modules/ledger/ledger.serializer.js');
const { hasTranslation, t } = await import('../src/lib/i18n.js');

let request;

before(async () => {
  ({ request } = await setupTestApp());
});
beforeEach(resetDb);
after(teardownTestApp);

// ---------------------------------------------------------------- helpers

const IST = 'Asia/Kolkata';
const OBJECT_ID = /^[a-f0-9]{24}$/;
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const UNKNOWN_ID = 'aaaaaaaaaaaaaaaaaaaaaaaa';

const ENTRY_KEYS = [
  'amount',
  'category',
  'createdAt',
  'createdById',
  'date',
  'goalId',
  'id',
  'memberId',
  'memberName',
  'note',
  'type',
].sort();

const GOAL_KEYS = [
  'createdAt',
  'createdById',
  'description',
  'id',
  'progress',
  'savedAmount',
  'status',
  'targetAmount',
  'targetDate',
  'title',
  'updatedAt',
].sort();

const SUMMARY_KEYS = ['byCategory', 'currency', 'expense', 'income', 'month', 'net', 'scope'].sort();

const ENTRIES = `${API}/ledger/entries`;
const SUMMARY = `${API}/ledger/summary`;
const GOALS = `${API}/goals`;
const entryUrl = (id) => `${ENTRIES}/${id}`;
const goalUrl = (id) => `${GOALS}/${id}`;
const contributionsUrl = (id) => `${GOALS}/${id}/contributions`;

function assertOk(res, status = 200) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.equal(res.body.success, true);
  assert.ok('data' in res.body);
  return res.body.data;
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
  }
  return error;
}

/** Family-local midnight (UTC Date) of `today + offsetDays` in `timeZone`. */
function localMidnight(offsetDays = 0, timeZone = IST, now = new Date()) {
  const p = zonedParts(now, timeZone);
  return zonedTimeToUtc({ year: p.year, month: p.month, day: p.day + offsetDays }, timeZone);
}

/** `YYYY-MM-DD` of `today + offsetDays` in `timeZone`. */
function localDay(offsetDays = 0, timeZone = IST) {
  const p = zonedParts(localMidnight(offsetDays, timeZone), timeZone);
  return `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`;
}

/** Admin + joined member of one family, plus an admin of another family. */
async function setupFamilies(familyOverrides = {}) {
  const admin = await registerFamilyAdmin({ family: familyOverrides });
  const member = await joinFamilyAs(admin.family.inviteCode, { name: 'Priya Sharma' });
  const outsider = await registerFamilyAdmin({ name: 'Other Admin', family: { name: 'Other Family' } });
  return { admin, member, outsider };
}

/** A managed profile (no account) inserted directly (the family module is not required). */
async function managedMember(familyId, overrides = {}) {
  const doc = await Member.create({
    familyId,
    name: 'Anaya',
    role: 'member',
    dateOfBirth: new Date('2016-08-01T00:00:00.000Z'),
    guardianConsent: true,
    ...overrides,
  });
  return { id: String(doc._id), name: doc.name };
}

const entryBody = (overrides = {}) => ({
  type: 'expense',
  amount: 100,
  category: 'groceries',
  note: 'Veggies',
  date: localMidnight(0).toISOString(),
  ...overrides,
});

async function createEntry(auth, overrides = {}) {
  return assertOk(await request.post(ENTRIES).set(auth).send(entryBody(overrides)), 201);
}

async function createGoal(auth, overrides = {}) {
  return assertOk(
    await request.post(GOALS).set(auth).send({ title: 'Goa vacation', targetAmount: 600, ...overrides }),
    201,
  );
}

async function contribute(auth, goalId, body = {}) {
  return assertOk(await request.post(contributionsUrl(goalId)).set(auth).send({ amount: 100, ...body }), 201);
}

async function listEntries(auth, query = {}) {
  const res = await request.get(ENTRIES).set(auth).query(query);
  assertOk(res);
  return res.body;
}

async function goalPushes() {
  await flushPushes();
  return sentPushes.filter((p) => p.type === 'goal_achieved');
}

// ---------------------------------------------------------------- auth & envelope

describe('auth & envelope', () => {
  it('requires a token (401) and a family (403 NO_FAMILY) on every ledger and goal route', async () => {
    const admin = await registerFamilyAdmin();
    const routes = [
      ['get', ENTRIES],
      ['post', ENTRIES],
      ['patch', entryUrl(UNKNOWN_ID)],
      ['delete', entryUrl(UNKNOWN_ID)],
      ['get', SUMMARY],
      ['get', GOALS],
      ['post', GOALS],
      ['patch', goalUrl(UNKNOWN_ID)],
      ['delete', goalUrl(UNKNOWN_ID)],
      ['post', contributionsUrl(UNKNOWN_ID)],
    ];
    for (const [method, url] of routes) assertError(await request[method](url).send({}), 401, 'UNAUTHORIZED');

    await User.updateOne({ _id: admin.user.id }, { $set: { familyId: null, memberId: null } });
    for (const [method, url] of routes) assertError(await request[method](url).set(admin.auth).send({}), 403, 'NO_FAMILY');
  });

  it('returns the exact LedgerEntry shape with money in major units and minor units stored', async () => {
    const { admin } = await setupFamilies();
    const res = await request.post(ENTRIES).set(admin.auth).send(entryBody({ amount: 1250.5 }));
    const entry = assertOk(res, 201);
    assert.ok(!('meta' in res.body));
    assert.deepEqual(Object.keys(entry).sort(), ENTRY_KEYS);
    assert.match(entry.id, OBJECT_ID);
    assert.equal(entry.type, 'expense');
    assert.equal(entry.amount, 1250.5);
    assert.equal(entry.category, 'groceries');
    assert.equal(entry.note, 'Veggies');
    assert.match(entry.date, ISO);
    assert.equal(entry.memberId, admin.member.id);
    assert.equal(entry.memberName, admin.member.name);
    assert.equal(entry.createdById, admin.member.id);
    assert.equal(entry.goalId, null);
    assert.match(entry.createdAt, ISO);
    assert.equal(res.headers['cache-control'], 'private, no-store');

    const raw = await LedgerEntry.findById(entry.id).lean();
    assert.equal(raw.amountMinor, 125050);
    assert.equal(raw.memberName, admin.member.name);
    assert.ok(!JSON.stringify(entry).includes('amountMinor'));
    assert.ok(!('_id' in entry) && !('__v' in entry));
  });

  it('paginated list has `meta` and uses the contract envelope', async () => {
    const { admin } = await setupFamilies();
    for (let i = 0; i < 3; i += 1) await createEntry(admin.auth, { amount: 10 + i });
    const body = await listEntries(admin.auth, { page: 1, limit: 2 });
    assert.equal(body.success, true);
    assert.equal(body.data.length, 2);
    assert.deepEqual(body.meta, { page: 1, limit: 2, total: 3, hasMore: true });
    const page2 = await listEntries(admin.auth, { page: 2, limit: 2 });
    assert.equal(page2.data.length, 1);
    assert.deepEqual(page2.meta, { page: 2, limit: 2, total: 3, hasMore: false });
  });
});

// ---------------------------------------------------------------- create

describe('POST /ledger/entries', () => {
  it('lets a member record their own income and expense (memberId defaults to self)', async () => {
    const { member } = await setupFamilies();
    const income = await createEntry(member.auth, { type: 'income', category: 'allowance', amount: 500, note: null });
    assert.equal(income.memberId, member.member.id);
    assert.equal(income.memberName, 'Priya Sharma');
    assert.equal(income.createdById, member.member.id);
    assert.equal(income.note, null);
    const own = await createEntry(member.auth, { memberId: member.member.id });
    assert.equal(own.memberId, member.member.id);
  });

  it('member recording for someone else → 403; admin may record for any member of the family', async () => {
    const { admin, member } = await setupFamilies();
    const res = await request.post(ENTRIES).set(member.auth).send(entryBody({ memberId: admin.member.id }));
    assertError(res, 403, 'FORBIDDEN');
    // Not even an unknown id reveals anything to a member.
    assertError(await request.post(ENTRIES).set(member.auth).send(entryBody({ memberId: UNKNOWN_ID })), 403, 'FORBIDDEN');

    const kid = await managedMember(admin.family.id);
    const forKid = await createEntry(admin.auth, { memberId: kid.id, type: 'income', category: 'gift' });
    assert.equal(forKid.memberId, kid.id);
    assert.equal(forKid.memberName, 'Anaya');
    assert.equal(forKid.createdById, admin.member.id);
    const forMember = await createEntry(admin.auth, { memberId: member.member.id });
    assert.equal(forMember.memberName, 'Priya Sharma');
  });

  it('admin: memberId of another family or unknown → 422 details.memberId (never 404)', async () => {
    const { admin, outsider } = await setupFamilies();
    assertValidation(await request.post(ENTRIES).set(admin.auth).send(entryBody({ memberId: outsider.member.id })), 'memberId');
    assertValidation(await request.post(ENTRIES).set(admin.auth).send(entryBody({ memberId: UNKNOWN_ID })), 'memberId');
    assertValidation(await request.post(ENTRIES).set(admin.auth).send(entryBody({ memberId: 'not-an-id' })), 'memberId');
    assert.equal(await LedgerEntry.countDocuments(), 0);
  });

  it('reports every missing required field', async () => {
    const { admin } = await setupFamilies();
    const error = assertValidation(await request.post(ENTRIES).set(admin.auth).send({}), 'type', 'amount', 'category', 'date');
    assert.equal(error.details.amount, 'Amount is required');
  });

  it('rejects a category that does not belong to the type (both directions)', async () => {
    const { admin } = await setupFamilies();
    const e1 = assertValidation(
      await request.post(ENTRIES).set(admin.auth).send(entryBody({ type: 'income', category: 'groceries' })),
      'category',
    );
    assert.match(e1.details.category, /not valid for income/);
    assertValidation(await request.post(ENTRIES).set(admin.auth).send(entryBody({ type: 'expense', category: 'salary' })), 'category');
    assertValidation(await request.post(ENTRIES).set(admin.auth).send(entryBody({ category: 'lottery' })), 'category');
    assertValidation(await request.post(ENTRIES).set(admin.auth).send(entryBody({ type: 'transfer' })), 'type');
    // Every contract category is accepted for its own type.
    for (const category of ['salary', 'business', 'allowance', 'gift', 'interest', 'other_income']) {
      await createEntry(admin.auth, { type: 'income', category });
    }
    for (const category of ['utilities', 'rent', 'education', 'health', 'transport', 'dining', 'shopping', 'entertainment', 'household_help', 'savings', 'other_expense']) {
      await createEntry(admin.auth, { category });
    }
  });

  it('validates amounts: > 0, ≤ 1e12, ≥ 0.01, numbers only; rounds to 2 decimals', async () => {
    const { admin } = await setupFamilies();
    for (const amount of [0, -5, 1e12 + 1, 0.001, '100', null, true, Number.NaN]) {
      assertValidation(await request.post(ENTRIES).set(admin.auth).send(entryBody({ amount })), 'amount');
    }
    assert.equal((await createEntry(admin.auth, { amount: 1e12 })).amount, 1e12);
    assert.equal((await createEntry(admin.auth, { amount: 0.01 })).amount, 0.01);
    assert.equal((await createEntry(admin.auth, { amount: 1.005 })).amount, 1.01);
    assert.equal((await createEntry(admin.auth, { amount: 0.1 + 0.2 })).amount, 0.3);
    const raw = await LedgerEntry.find().sort({ createdAt: 1 }).lean();
    assert.deepEqual(raw.map((e) => e.amountMinor), [1e14, 1, 101, 30]);
  });

  it('validates note length (≤ 200) and trims / blanks to null', async () => {
    const { admin } = await setupFamilies();
    assertValidation(await request.post(ENTRIES).set(admin.auth).send(entryBody({ note: 'x'.repeat(201) })), 'note');
    assertValidation(await request.post(ENTRIES).set(admin.auth).send(entryBody({ note: 42 })), 'note');
    assert.equal((await createEntry(admin.auth, { note: 'x'.repeat(200) })).note.length, 200);
    assert.equal((await createEntry(admin.auth, { note: '  Milk  ' })).note, 'Milk');
    assert.equal((await createEntry(admin.auth, { note: '   ' })).note, null);
  });

  it('dates: tomorrow is the latest allowed day (family time zone), malformed / too old dates → 422', async () => {
    const { admin } = await setupFamilies();
    const tomorrow = await createEntry(admin.auth, { date: localMidnight(1).toISOString() });
    assert.equal(tomorrow.date, localMidnight(1).toISOString());
    assert.equal((await createEntry(admin.auth, { date: localDay(1) })).date, localMidnight(1).toISOString());

    const future = assertValidation(
      await request.post(ENTRIES).set(admin.auth).send(entryBody({ date: localMidnight(2).toISOString() })),
      'date',
    );
    assert.match(future.message, /tomorrow/i);
    assertValidation(await request.post(ENTRIES).set(admin.auth).send(entryBody({ date: localDay(2) })), 'date');
    for (const date of ['yesterday', '2025-02-31', '2025-13-01', '26/09/2025', '2025-09-26T10:15:00', '1999-06-01', '1999-12-31', 12345]) {
      assertValidation(await request.post(ENTRIES).set(admin.auth).send(entryBody({ date })), 'date');
    }
    assert.equal((await createEntry(admin.auth, { date: '2000-01-01' })).date, '1999-12-31T18:30:00.000Z');
  });

  it('stores business dates as family-local midnight (date-only and phones in other zones)', async () => {
    const { admin } = await setupFamilies();
    // Date-only → midnight in Asia/Kolkata.
    assert.equal((await createEntry(admin.auth, { date: '2025-04-01' })).date, '2025-03-31T18:30:00.000Z');
    // A phone in London sends its local midnight (01:00 offset in summer) → nearest IST midnight.
    assert.equal((await createEntry(admin.auth, { date: '2025-04-01T00:00:00+01:00' })).date, '2025-03-31T18:30:00.000Z');
    // A phone in New York (UTC-4) sends its local midnight → same calendar day in IST.
    assert.equal((await createEntry(admin.auth, { date: '2025-04-01T04:00:00.000Z' })).date, '2025-03-31T18:30:00.000Z');
    // The app in the family zone sends exactly IST midnight → unchanged.
    assert.equal((await createEntry(admin.auth, { date: '2025-03-31T18:30:00.000Z' })).date, '2025-03-31T18:30:00.000Z');
  });

  it('strips read-only keys (goalId, createdById, familyId, amountMinor)', async () => {
    const { admin, outsider } = await setupFamilies();
    const goal = await createGoal(admin.auth);
    const entry = await createEntry(admin.auth, {
      goalId: goal.id,
      createdById: UNKNOWN_ID,
      familyId: outsider.family.id,
      amountMinor: 1,
    });
    assert.equal(entry.goalId, null);
    assert.equal(entry.createdById, admin.member.id);
    assert.equal(entry.amount, 100);
    const raw = await LedgerEntry.findById(entry.id).lean();
    assert.equal(String(raw.familyId), admin.family.id);
    assert.equal((await Goal.findById(goal.id).lean()).savedMinor, 0);
  });

  it('malformed JSON → 400 BAD_REQUEST', async () => {
    const { admin } = await setupFamilies();
    const res = await request.post(ENTRIES).set(admin.auth).set('Content-Type', 'application/json').send('{"type":');
    assertError(res, 400, 'BAD_REQUEST');
  });
});

// ---------------------------------------------------------------- list

describe('GET /ledger/entries', () => {
  it('admin sees every entry; a member sees entries they own or created; other families see nothing', async () => {
    const { admin, member, outsider } = await setupFamilies();
    const adminOwn = await createEntry(admin.auth, { note: 'admin own' });
    const forMember = await createEntry(admin.auth, { memberId: member.member.id, note: 'for member' });
    const memberOwn = await createEntry(member.auth, { note: 'member own' });
    await createEntry(outsider.auth, { note: 'other family' });

    const all = (await listEntries(admin.auth)).data.map((e) => e.id).sort();
    assert.deepEqual(all, [adminOwn.id, forMember.id, memberOwn.id].sort());

    const mine = (await listEntries(member.auth)).data.map((e) => e.id).sort();
    assert.deepEqual(mine, [forMember.id, memberOwn.id].sort());

    // Reassigned by an admin: the member still sees what they created.
    await request.patch(entryUrl(memberOwn.id)).set(admin.auth).send({ memberId: admin.member.id }).expect(200);
    const after = (await listEntries(member.auth)).data.map((e) => e.id).sort();
    assert.deepEqual(after, [forMember.id, memberOwn.id].sort());

    const theirs = (await listEntries(outsider.auth)).data;
    assert.equal(theirs.length, 1);
    assert.equal(theirs[0].note, 'other family');
  });

  it('sorts by date desc, then newest first', async () => {
    const { admin } = await setupFamilies();
    const old = await createEntry(admin.auth, { date: '2025-01-10', note: 'old' });
    const sameDayFirst = await createEntry(admin.auth, { date: '2025-02-10', note: 'first' });
    const sameDaySecond = await createEntry(admin.auth, { date: '2025-02-10', note: 'second' });
    const newest = await createEntry(admin.auth, { date: '2025-03-10', note: 'newest' });
    const ids = (await listEntries(admin.auth)).data.map((e) => e.id);
    assert.deepEqual(ids, [newest.id, sameDaySecond.id, sameDayFirst.id, old.id]);
  });

  it('filters by month in the family time zone, type, memberId and goalId', async () => {
    const { admin, member } = await setupFamilies();
    const march31 = await createEntry(admin.auth, { date: '2025-03-31' });
    const april1 = await createEntry(admin.auth, { date: '2025-04-01', type: 'income', category: 'salary' });
    const april30 = await createEntry(admin.auth, { date: '2025-04-30', memberId: member.member.id });
    await createEntry(admin.auth, { date: '2025-05-01' });
    const goal = await createGoal(admin.auth);
    const { entry: contribution } = await contribute(member.auth, goal.id, { date: '2025-04-15' });

    const april = (await listEntries(admin.auth, { month: '2025-04' })).data.map((e) => e.id).sort();
    assert.deepEqual(april, [april1.id, april30.id, contribution.id].sort());
    assert.deepEqual((await listEntries(admin.auth, { month: '2025-03' })).data.map((e) => e.id), [march31.id]);

    const incomes = (await listEntries(admin.auth, { type: 'income' })).data;
    assert.deepEqual(incomes.map((e) => e.id), [april1.id]);
    const byMember = (await listEntries(admin.auth, { memberId: member.member.id })).data.map((e) => e.id).sort();
    assert.deepEqual(byMember, [april30.id, contribution.id].sort());
    const byGoal = (await listEntries(member.auth, { goalId: goal.id })).data;
    assert.deepEqual(byGoal.map((e) => e.id), [contribution.id]);
    const combined = await listEntries(admin.auth, { month: '2025-04', type: 'expense', memberId: member.member.id });
    assert.equal(combined.meta.total, 2);
    // Blank filters count as "not given" (the app may send empty strings).
    assert.equal((await listEntries(admin.auth, { month: '', type: '', memberId: '', goalId: '' })).meta.total, 5);
  });

  it('the month filter follows the family time zone (New York family)', async () => {
    const admin = await registerFamilyAdmin({ family: { country: 'US', currency: 'USD', timezone: 'America/New_York' } });
    // A phone in India sends its local midnight of 1 Oct → 1 Oct in New York, not 30 Sep.
    const entry = await createEntry(admin.auth, { date: '2025-09-30T18:30:00.000Z' });
    assert.equal(entry.date, '2025-10-01T04:00:00.000Z');
    assert.equal((await listEntries(admin.auth, { month: '2025-10' })).meta.total, 1);
    assert.equal((await listEntries(admin.auth, { month: '2025-09' })).meta.total, 0);
  });

  it('rejects malformed filters and pagination (422 details)', async () => {
    const { admin } = await setupFamilies();
    const bad = [
      [{ month: '2025-13' }, 'month'],
      [{ month: '2025-1' }, 'month'],
      [{ type: 'transfer' }, 'type'],
      [{ memberId: 'xyz' }, 'memberId'],
      [{ goalId: '123' }, 'goalId'],
      [{ page: 0 }, 'page'],
      [{ limit: 101 }, 'limit'],
      [{ limit: 'ten' }, 'limit'],
    ];
    for (const [query, path] of bad) assertValidation(await request.get(ENTRIES).set(admin.auth).query(query), path);
  });

  it('shows the current member name, falling back to the stored snapshot after removal', async () => {
    const { admin } = await setupFamilies();
    const kid = await managedMember(admin.family.id, { name: 'Anaya' });
    const entry = await createEntry(admin.auth, { memberId: kid.id });
    await Member.updateOne({ _id: kid.id }, { $set: { name: 'Anaya S.' } });
    assert.equal((await listEntries(admin.auth)).data[0].memberName, 'Anaya S.');
    await Member.deleteOne({ _id: kid.id });
    const listed = (await listEntries(admin.auth)).data[0];
    assert.equal(listed.id, entry.id);
    assert.equal(listed.memberName, 'Anaya');
    assert.equal(listed.memberId, kid.id);
  });
});

// ---------------------------------------------------------------- update

describe('PATCH /ledger/entries/:id', () => {
  it('creator member and admin can edit; only sent keys change', async () => {
    const { admin, member } = await setupFamilies();
    const entry = await createEntry(member.auth, { note: 'Milk', amount: 40 });
    const edited = assertOk(await request.patch(entryUrl(entry.id)).set(member.auth).send({ note: 'Milk & bread' }));
    assert.equal(edited.note, 'Milk & bread');
    assert.equal(edited.amount, 40);
    assert.equal(edited.date, entry.date);

    const byAdmin = assertOk(await request.patch(entryUrl(entry.id)).set(admin.auth).send({ amount: 55.25, note: null }));
    assert.equal(byAdmin.amount, 55.25);
    assert.equal(byAdmin.note, null);
    assert.equal((await LedgerEntry.findById(entry.id).lean()).amountMinor, 5525);

    const unchanged = assertOk(await request.patch(entryUrl(entry.id)).set(member.auth).send({}));
    assert.deepEqual(unchanged, byAdmin);
  });

  it('permission matrix: visible-but-not-creator → 403, invisible → 404, other family → 404, bad id → 400', async () => {
    const { admin, member, outsider } = await setupFamilies();
    const forMember = await createEntry(admin.auth, { memberId: member.member.id });
    const adminOwn = await createEntry(admin.auth);
    const memberOwn = await createEntry(member.auth);

    assertError(await request.patch(entryUrl(forMember.id)).set(member.auth).send({ note: 'x' }), 403, 'FORBIDDEN');
    assertError(await request.delete(entryUrl(forMember.id)).set(member.auth), 403, 'FORBIDDEN');
    assertError(await request.patch(entryUrl(adminOwn.id)).set(member.auth).send({ note: 'x' }), 404, 'NOT_FOUND');
    assertError(await request.delete(entryUrl(adminOwn.id)).set(member.auth), 404, 'NOT_FOUND');
    assertError(await request.patch(entryUrl(memberOwn.id)).set(outsider.auth).send({ note: 'x' }), 404, 'NOT_FOUND');
    assertError(await request.delete(entryUrl(memberOwn.id)).set(outsider.auth), 404, 'NOT_FOUND');
    assertError(await request.patch(entryUrl(UNKNOWN_ID)).set(admin.auth).send({ note: 'x' }), 404, 'NOT_FOUND');
    assertError(await request.patch(entryUrl('nope')).set(admin.auth).send({ note: 'x' }), 400, 'BAD_REQUEST');
    assertError(await request.delete(entryUrl('nope')).set(admin.auth), 400, 'BAD_REQUEST');
    // Nothing changed.
    assert.equal((await LedgerEntry.findById(memberOwn.id).lean()).note, 'Veggies');
  });

  it('type / category pairs are validated against the stored values', async () => {
    const { admin } = await setupFamilies();
    const entry = await createEntry(admin.auth, { category: 'groceries' });
    assertValidation(await request.patch(entryUrl(entry.id)).set(admin.auth).send({ type: 'income' }), 'category');
    assertValidation(await request.patch(entryUrl(entry.id)).set(admin.auth).send({ category: 'salary' }), 'category');
    assertValidation(
      await request.patch(entryUrl(entry.id)).set(admin.auth).send({ type: 'income', category: 'rent' }),
      'category',
    );
    const income = assertOk(await request.patch(entryUrl(entry.id)).set(admin.auth).send({ type: 'income', category: 'salary' }));
    assert.equal(income.type, 'income');
    assert.equal(income.category, 'salary');
    const recategorised = assertOk(await request.patch(entryUrl(entry.id)).set(admin.auth).send({ category: 'gift' }));
    assert.equal(recategorised.category, 'gift');
  });

  it('validates PATCH values (422 details) and never accepts null for required fields', async () => {
    const { admin } = await setupFamilies();
    const entry = await createEntry(admin.auth);
    const cases = [
      [{ amount: 0 }, 'amount'],
      [{ amount: null }, 'amount'],
      [{ type: null }, 'type'],
      [{ category: null }, 'category'],
      [{ date: null }, 'date'],
      [{ date: localMidnight(3).toISOString() }, 'date'],
      [{ note: 'x'.repeat(201) }, 'note'],
      [{ memberId: null }, 'memberId'],
      [{ memberId: 'abc' }, 'memberId'],
    ];
    for (const [body, path] of cases) assertValidation(await request.patch(entryUrl(entry.id)).set(admin.auth).send(body), path);
  });

  it('changes the date (normalised) and the owner (admin any member; member only to self)', async () => {
    const { admin, member, outsider } = await setupFamilies();
    const entry = await createEntry(member.auth);
    const redated = assertOk(await request.patch(entryUrl(entry.id)).set(member.auth).send({ date: '2025-06-15' }));
    assert.equal(redated.date, '2025-06-14T18:30:00.000Z');

    assertError(
      await request.patch(entryUrl(entry.id)).set(member.auth).send({ memberId: admin.member.id }),
      403,
      'FORBIDDEN',
    );
    assertValidation(await request.patch(entryUrl(entry.id)).set(admin.auth).send({ memberId: outsider.member.id }), 'memberId');
    const moved = assertOk(await request.patch(entryUrl(entry.id)).set(admin.auth).send({ memberId: admin.member.id }));
    assert.equal(moved.memberId, admin.member.id);
    assert.equal(moved.memberName, admin.member.name);
    assert.equal((await LedgerEntry.findById(entry.id).lean()).memberName, admin.member.name);
    // The creator may take it back to themselves.
    const back = assertOk(await request.patch(entryUrl(entry.id)).set(member.auth).send({ memberId: member.member.id }));
    assert.equal(back.memberId, member.member.id);
  });

  it('goal-linked entries: amount / type / category locked, note / date editable', async () => {
    const { admin, member } = await setupFamilies();
    const goal = await createGoal(admin.auth);
    const { entry } = await contribute(member.auth, goal.id, { amount: 150 });

    const locked = assertValidation(await request.patch(entryUrl(entry.id)).set(member.auth).send({ amount: 200 }), 'amount');
    assert.match(locked.message, /cannot be changed/i);
    assertValidation(await request.patch(entryUrl(entry.id)).set(admin.auth).send({ type: 'income', category: 'gift' }), 'type');
    assertValidation(await request.patch(entryUrl(entry.id)).set(admin.auth).send({ category: 'groceries' }), 'category');

    const same = assertOk(await request.patch(entryUrl(entry.id)).set(member.auth).send({ amount: 150, note: 'June savings', date: '2025-06-01' }));
    assert.equal(same.amount, 150);
    assert.equal(same.note, 'June savings');
    assert.equal(same.date, '2025-05-31T18:30:00.000Z');
    assert.equal(same.goalId, goal.id);
    assert.equal((await Goal.findById(goal.id).lean()).savedMinor, 15000);
  });
});

// ---------------------------------------------------------------- delete

describe('DELETE /ledger/entries/:id', () => {
  it('creator and admin can delete (data: null)', async () => {
    const { admin, member } = await setupFamilies();
    const a = await createEntry(member.auth);
    const b = await createEntry(member.auth);
    const res = await request.delete(entryUrl(a.id)).set(member.auth);
    assert.equal(assertOk(res), null);
    assert.equal(assertOk(await request.delete(entryUrl(b.id)).set(admin.auth)), null);
    assert.equal(await LedgerEntry.countDocuments(), 0);
    assertError(await request.delete(entryUrl(a.id)).set(member.auth), 404, 'NOT_FOUND');
  });

  it('deleting a contribution decrements the goal and reopens an achieved goal', async () => {
    const { admin, member } = await setupFamilies();
    const goal = await createGoal(admin.auth, { targetAmount: 300 });
    const first = await contribute(member.auth, goal.id, { amount: 200 });
    const second = await contribute(admin.auth, goal.id, { amount: 100 });
    assert.equal(second.goal.status, 'achieved');
    assert.ok((await Goal.findById(goal.id).lean()).achievedAt);

    const { achievedAt } = await Goal.findById(goal.id).lean();
    assertOk(await request.delete(entryUrl(first.entry.id)).set(member.auth));
    const stored = await Goal.findById(goal.id).lean();
    assert.equal(stored.savedMinor, 10000);
    assert.equal(stored.status, 'active');
    // Kept: when the target was last reached (the goal_achieved push cooldown, goals.balance.js).
    assert.deepEqual(stored.achievedAt, achievedAt);
    const [listed] = assertOk(await request.get(GOALS).set(member.auth));
    assert.equal(listed.savedAmount, 100);
    assert.equal(listed.progress, 0.3333);
  });

  it('never takes the saved amount below 0 and keeps archived goals archived', async () => {
    const { admin } = await setupFamilies();
    const goal = await createGoal(admin.auth);
    const { entry } = await contribute(admin.auth, goal.id, { amount: 100 });
    await Goal.updateOne({ _id: goal.id }, { $set: { savedMinor: 5000, status: 'archived' } });
    assertOk(await request.delete(entryUrl(entry.id)).set(admin.auth));
    const stored = await Goal.findById(goal.id).lean();
    assert.equal(stored.savedMinor, 0);
    assert.equal(stored.status, 'archived');
  });

  it('parallel deletes of the same contribution subtract only once', async () => {
    const { admin } = await setupFamilies();
    const goal = await createGoal(admin.auth);
    await contribute(admin.auth, goal.id, { amount: 100 });
    const { entry } = await contribute(admin.auth, goal.id, { amount: 50 });
    const results = await Promise.all([1, 2, 3].map(() => request.delete(entryUrl(entry.id)).set(admin.auth)));
    assert.deepEqual(results.map((r) => r.status).sort(), [200, 404, 404]);
    assert.equal((await Goal.findById(goal.id).lean()).savedMinor, 10000);
  });

  it('deleting an entry whose goal is gone just deletes the entry', async () => {
    const { admin } = await setupFamilies();
    const goal = await createGoal(admin.auth);
    const { entry } = await contribute(admin.auth, goal.id);
    await Goal.deleteOne({ _id: goal.id }); // dangling link (e.g. legacy data)
    assert.equal(assertOk(await request.delete(entryUrl(entry.id)).set(admin.auth)), null);
    assert.equal(await LedgerEntry.countDocuments(), 0);
  });
});

// ---------------------------------------------------------------- summary

describe('GET /ledger/summary', () => {
  it('admin gets the family scope with totals, net and byCategory (amount desc)', async () => {
    const { admin, member } = await setupFamilies();
    await createEntry(admin.auth, { date: '2025-04-01', type: 'income', category: 'salary', amount: 1000 });
    await createEntry(admin.auth, { date: '2025-04-02', amount: 120.5, category: 'groceries' });
    await createEntry(member.auth, { date: '2025-04-03', amount: 79.5, category: 'groceries' });
    await createEntry(member.auth, { date: '2025-04-04', amount: 300, category: 'rent' });
    await createEntry(member.auth, { date: '2025-04-05', type: 'income', category: 'allowance', amount: 50 });
    await createEntry(admin.auth, { date: '2025-05-01', amount: 999 }); // next month

    const res = await request.get(SUMMARY).set(admin.auth).query({ month: '2025-04' });
    const summary = assertOk(res);
    assert.ok(!('meta' in res.body));
    assert.deepEqual(Object.keys(summary).sort(), SUMMARY_KEYS);
    assert.deepEqual(summary, {
      month: '2025-04',
      currency: 'INR',
      scope: 'family',
      income: 1050,
      expense: 500,
      net: 550,
      byCategory: [
        { type: 'income', category: 'salary', amount: 1000 },
        { type: 'expense', category: 'rent', amount: 300 },
        { type: 'expense', category: 'groceries', amount: 200 },
        { type: 'income', category: 'allowance', amount: 50 },
      ],
    });
  });

  it('member gets the personal scope (entries whose memberId is theirs)', async () => {
    const { admin, member } = await setupFamilies();
    await createEntry(admin.auth, { date: '2025-04-02', amount: 700 });
    await createEntry(admin.auth, { date: '2025-04-02', amount: 25, memberId: member.member.id, category: 'dining' });
    const own = await createEntry(member.auth, { date: '2025-04-03', amount: 80, category: 'transport' });
    // Created by the member but owned by the admin → not in the member's personal totals.
    await request.patch(entryUrl(own.id)).set(admin.auth).send({ memberId: admin.member.id }).expect(200);
    await createEntry(member.auth, { date: '2025-04-04', type: 'income', category: 'allowance', amount: 10 });

    const summary = assertOk(await request.get(SUMMARY).set(member.auth).query({ month: '2025-04' }));
    assert.equal(summary.scope, 'personal');
    assert.equal(summary.income, 10);
    assert.equal(summary.expense, 25);
    assert.equal(summary.net, -15);
    assert.deepEqual(summary.byCategory, [
      { type: 'expense', category: 'dining', amount: 25 },
      { type: 'income', category: 'allowance', amount: 10 },
    ]);
  });

  it('defaults to the current month in the family time zone; empty months are all zero', async () => {
    const { admin } = await setupFamilies();
    await createEntry(admin.auth, { amount: 42 }); // today (IST)
    const current = assertOk(await request.get(SUMMARY).set(admin.auth));
    assert.equal(current.month, currentMonth(IST));
    assert.equal(current.expense, 42);
    const blank = assertOk(await request.get(SUMMARY).set(admin.auth).query({ month: '' }));
    assert.equal(blank.month, currentMonth(IST));

    const empty = assertOk(await request.get(SUMMARY).set(admin.auth).query({ month: '2001-01' }));
    assert.deepEqual(empty, {
      month: '2001-01',
      currency: 'INR',
      scope: 'family',
      income: 0,
      expense: 0,
      net: 0,
      byCategory: [],
    });
  });

  it('month boundaries follow the family time zone', async () => {
    const { admin } = await setupFamilies();
    // IST midnight of 1 April = 2025-03-31T18:30Z → April, not March.
    await createEntry(admin.auth, { date: '2025-03-31T18:30:00.000Z', amount: 10 });
    await createEntry(admin.auth, { date: '2025-03-31', amount: 1 });
    const march = assertOk(await request.get(SUMMARY).set(admin.auth).query({ month: '2025-03' }));
    const april = assertOk(await request.get(SUMMARY).set(admin.auth).query({ month: '2025-04' }));
    assert.equal(march.expense, 1);
    assert.equal(april.expense, 10);
  });

  it('includes goal contributions as expense/savings and never mixes families', async () => {
    const { admin, member, outsider } = await setupFamilies();
    const goal = await createGoal(admin.auth);
    await contribute(member.auth, goal.id, { amount: 60, date: '2025-04-10' });
    await createEntry(outsider.auth, { date: '2025-04-10', amount: 5000 });
    const summary = assertOk(await request.get(SUMMARY).set(admin.auth).query({ month: '2025-04' }));
    assert.equal(summary.expense, 60);
    assert.deepEqual(summary.byCategory, [{ type: 'expense', category: 'savings', amount: 60 }]);
    const theirs = assertOk(await request.get(SUMMARY).set(outsider.auth).query({ month: '2025-04' }));
    assert.equal(theirs.expense, 5000);
  });

  it('rejects malformed months', async () => {
    const { admin } = await setupFamilies();
    for (const month of ['2025-00', '2025-13', '25-04', '2025/04', 'April']) {
      assertValidation(await request.get(SUMMARY).set(admin.auth).query({ month }), 'month');
    }
  });

  it('getMonthSummary() serves the dashboard (family / personal scope, loads family settings when omitted)', async () => {
    const { admin, member } = await setupFamilies();
    await createEntry(admin.auth, { date: '2025-04-02', amount: 100 });
    await createEntry(member.auth, { date: '2025-04-03', amount: 30 });

    const family = await getMonthSummary({ familyId: admin.family.id, memberId: null, month: '2025-04', timeZone: IST, currency: 'INR' });
    assert.equal(family.scope, 'family');
    assert.equal(family.expense, 130);

    const personal = await getMonthSummary({ familyId: admin.family.id, memberId: member.member.id, month: '2025-04' });
    assert.equal(personal.scope, 'personal');
    assert.equal(personal.expense, 30);
    assert.equal(personal.currency, 'INR');

    const current = await getMonthSummary({ familyId: admin.family.id });
    assert.equal(current.month, currentMonth(IST));
    assert.equal(current.expense, 0);
  });
});

// ---------------------------------------------------------------- goals

describe('/goals CRUD', () => {
  it('admin creates a goal (exact SavingsGoal shape); members cannot', async () => {
    const { admin, member } = await setupFamilies();
    const res = await request
      .post(GOALS)
      .set(admin.auth)
      .send({ title: '  Goa vacation ', description: 'Beach trip', targetAmount: 60000, targetDate: '2026-12-01' });
    const goal = assertOk(res, 201);
    assert.deepEqual(Object.keys(goal).sort(), GOAL_KEYS);
    assert.match(goal.id, OBJECT_ID);
    assert.equal(goal.title, 'Goa vacation');
    assert.equal(goal.description, 'Beach trip');
    assert.equal(goal.targetAmount, 60000);
    assert.equal(goal.savedAmount, 0);
    assert.equal(goal.targetDate, '2026-11-30T18:30:00.000Z');
    assert.equal(goal.status, 'active');
    assert.equal(goal.progress, 0);
    assert.equal(goal.createdById, admin.member.id);
    assert.match(goal.createdAt, ISO);
    assert.match(goal.updatedAt, ISO);
    const raw = await Goal.findById(goal.id).lean();
    assert.equal(raw.targetMinor, 6000000);

    assertError(await request.post(GOALS).set(member.auth).send({ title: 'Mine', targetAmount: 10 }), 403, 'FORBIDDEN');
    assert.equal(await Goal.countDocuments(), 1);
  });

  it('validates goal bodies (422 details)', async () => {
    const { admin } = await setupFamilies();
    assertValidation(await request.post(GOALS).set(admin.auth).send({}), 'title', 'targetAmount');
    const cases = [
      [{ title: '   ', targetAmount: 10 }, 'title'],
      [{ title: 'x'.repeat(81), targetAmount: 10 }, 'title'],
      [{ title: 'Car', targetAmount: 0 }, 'targetAmount'],
      [{ title: 'Car', targetAmount: '10' }, 'targetAmount'],
      [{ title: 'Car', targetAmount: 1e12 + 1 }, 'targetAmount'],
      [{ title: 'Car', targetAmount: 10, targetDate: 'soon' }, 'targetDate'],
      [{ title: 'Car', targetAmount: 10, description: 'x'.repeat(1001) }, 'description'],
    ];
    for (const [body, path] of cases) assertValidation(await request.post(GOALS).set(admin.auth).send(body), path);
    const goal = await createGoal(admin.auth, { title: 'x'.repeat(80), targetDate: null, description: '' });
    assert.equal(goal.targetDate, null);
    assert.equal(goal.description, null);

    for (const [body, path] of [
      [{ title: null }, 'title'],
      [{ targetAmount: -1 }, 'targetAmount'],
      [{ status: 'done' }, 'status'],
    ]) {
      assertValidation(await request.patch(goalUrl(goal.id)).set(admin.auth).send(body), path);
    }
  });

  it('lists goals for every member: active first, then achieved, then archived; status filter', async () => {
    const { admin, member, outsider } = await setupFamilies();
    const archived = await createGoal(admin.auth, { title: 'Old bike' });
    await request.patch(goalUrl(archived.id)).set(admin.auth).send({ status: 'archived' }).expect(200);
    const achieved = await createGoal(admin.auth, { title: 'TV', targetAmount: 100 });
    await contribute(admin.auth, achieved.id, { amount: 100 });
    const activeOld = await createGoal(admin.auth, { title: 'Car' });
    const activeNew = await createGoal(admin.auth, { title: 'Goa' });
    await createGoal(outsider.auth, { title: 'Not ours' });

    const res = await request.get(GOALS).set(member.auth);
    const all = assertOk(res);
    assert.ok(!('meta' in res.body));
    assert.deepEqual(all.map((g) => g.title), ['Goa', 'Car', 'TV', 'Old bike']);
    assert.deepEqual(assertOk(await request.get(GOALS).set(member.auth).query({ status: 'all' })).length, 4);
    assert.deepEqual(assertOk(await request.get(GOALS).set(member.auth).query({ status: 'active' })).map((g) => g.id), [activeNew.id, activeOld.id]);
    assert.deepEqual(assertOk(await request.get(GOALS).set(member.auth).query({ status: 'achieved' })).map((g) => g.id), [achieved.id]);
    assert.deepEqual(assertOk(await request.get(GOALS).set(member.auth).query({ status: 'archived' })).map((g) => g.id), [archived.id]);
    assertValidation(await request.get(GOALS).set(member.auth).query({ status: 'done' }), 'status');

    const dashboard = await listActiveGoals(admin.family.id, { limit: 1 });
    assert.deepEqual(dashboard.map((g) => g.id), [activeNew.id]);
  });

  it('admin edits title / description / target / date; members and other families cannot', async () => {
    const { admin, member, outsider } = await setupFamilies();
    const goal = await createGoal(admin.auth, { description: 'Trip', targetDate: '2026-01-10' });
    const edited = assertOk(
      await request
        .patch(goalUrl(goal.id))
        .set(admin.auth)
        .send({ title: 'Goa 2026', description: null, targetAmount: 700.75, targetDate: null }),
    );
    assert.equal(edited.title, 'Goa 2026');
    assert.equal(edited.description, null);
    assert.equal(edited.targetAmount, 700.75);
    assert.equal(edited.targetDate, null);
    assert.equal(edited.status, 'active');

    assertError(await request.patch(goalUrl(goal.id)).set(member.auth).send({ title: 'x' }), 403, 'FORBIDDEN');
    assertError(await request.delete(goalUrl(goal.id)).set(member.auth), 403, 'FORBIDDEN');
    assertError(await request.patch(goalUrl(goal.id)).set(outsider.auth).send({ title: 'x' }), 404, 'NOT_FOUND');
    assertError(await request.delete(goalUrl(goal.id)).set(outsider.auth), 404, 'NOT_FOUND');
    assertError(await request.patch(goalUrl(UNKNOWN_ID)).set(admin.auth).send({ title: 'x' }), 404, 'NOT_FOUND');
    assertError(await request.patch(goalUrl('bad')).set(admin.auth).send({ title: 'x' }), 400, 'BAD_REQUEST');
    assert.equal((await Goal.findById(goal.id).lean()).title, 'Goa 2026');
  });

  it('status follows the saved amount: lowering the target achieves (+ push), raising it reopens', async () => {
    const { admin, member } = await setupFamilies();
    const goal = await createGoal(admin.auth, { targetAmount: 500 });
    await contribute(member.auth, goal.id, { amount: 300 });

    // An unfinished goal cannot be marked achieved by hand.
    const manual = assertOk(await request.patch(goalUrl(goal.id)).set(admin.auth).send({ status: 'achieved' }));
    assert.equal(manual.status, 'active');
    assert.equal((await goalPushes()).length, 0);

    const lowered = assertOk(await request.patch(goalUrl(goal.id)).set(admin.auth).send({ targetAmount: 300 }));
    assert.equal(lowered.status, 'achieved');
    assert.equal(lowered.progress, 1);
    assert.equal((await goalPushes()).length, 1);

    // Asking for `active` on an achieved goal keeps it achieved (no second push).
    assert.equal(assertOk(await request.patch(goalUrl(goal.id)).set(admin.auth).send({ status: 'active' })).status, 'achieved');
    const raised = assertOk(await request.patch(goalUrl(goal.id)).set(admin.auth).send({ targetAmount: 1000 }));
    assert.equal(raised.status, 'active');
    assert.equal(raised.progress, 0.3);
    assert.equal((await Goal.findById(goal.id).lean()).achievedAt, null);
    assert.equal((await goalPushes()).length, 1);
  });

  it('archive and restore (restored state derived from the saved amount, no push on restore)', async () => {
    const { admin } = await setupFamilies();
    const open = await createGoal(admin.auth, { title: 'Open', targetAmount: 500 });
    await contribute(admin.auth, open.id, { amount: 100 });
    const done = await createGoal(admin.auth, { title: 'Done', targetAmount: 100 });
    await contribute(admin.auth, done.id, { amount: 100 });
    const achievedAt = (await Goal.findById(done.id).lean()).achievedAt;
    assert.equal((await goalPushes()).length, 1);

    for (const goal of [open, done]) {
      const archived = assertOk(await request.patch(goalUrl(goal.id)).set(admin.auth).send({ status: 'archived' }));
      assert.equal(archived.status, 'archived');
    }
    // Editing an archived goal keeps it archived, even when the target is now reached.
    assert.equal(assertOk(await request.patch(goalUrl(open.id)).set(admin.auth).send({ targetAmount: 50 })).status, 'archived');
    await request.patch(goalUrl(open.id)).set(admin.auth).send({ targetAmount: 500 }).expect(200);

    assert.equal(assertOk(await request.patch(goalUrl(open.id)).set(admin.auth).send({ status: 'active' })).status, 'active');
    const restored = assertOk(await request.patch(goalUrl(done.id)).set(admin.auth).send({ status: 'active' }));
    assert.equal(restored.status, 'achieved');
    assert.deepEqual((await Goal.findById(done.id).lean()).achievedAt, achievedAt);
    assert.equal((await goalPushes()).length, 1);
  });

  it('deleting a goal keeps its entries but detaches them (then they are ordinary entries)', async () => {
    const { admin, member } = await setupFamilies();
    const goal = await createGoal(admin.auth);
    const { entry } = await contribute(member.auth, goal.id, { amount: 80 });
    const other = await createGoal(admin.auth, { title: 'Other' });
    const { entry: otherEntry } = await contribute(member.auth, other.id, { amount: 20 });

    assert.equal(assertOk(await request.delete(goalUrl(goal.id)).set(admin.auth)), null);
    assert.equal(await Goal.countDocuments({ _id: goal.id }), 0);
    const kept = await LedgerEntry.findById(entry.id).lean();
    assert.equal(kept.goalId, null);
    assert.equal(kept.amountMinor, 8000);
    assert.equal(String((await LedgerEntry.findById(otherEntry.id).lean()).goalId), other.id);

    const edited = assertOk(await request.patch(entryUrl(entry.id)).set(member.auth).send({ amount: 90 }));
    assert.equal(edited.amount, 90);
    assert.equal(edited.goalId, null);
    assertError(await request.delete(goalUrl(goal.id)).set(admin.auth), 404, 'NOT_FOUND');
  });
});

// ---------------------------------------------------------------- contributions

describe('POST /goals/:id/contributions', () => {
  it('any member contributes → 201 { goal, entry } (expense/savings owned by the caller)', async () => {
    const { admin, member } = await setupFamilies();
    const goal = await createGoal(admin.auth, { targetAmount: 600 });
    const res = await request.post(contributionsUrl(goal.id)).set(member.auth).send({ amount: 125.5, note: 'Birthday money' });
    const result = assertOk(res, 201);
    assert.deepEqual(Object.keys(result).sort(), ['entry', 'goal']);
    assert.deepEqual(Object.keys(result.goal).sort(), GOAL_KEYS);
    assert.deepEqual(Object.keys(result.entry).sort(), ENTRY_KEYS);
    assert.equal(result.goal.savedAmount, 125.5);
    assert.equal(result.goal.progress, 0.2091);
    assert.equal(result.goal.status, 'active');
    assert.equal(result.entry.type, 'expense');
    assert.equal(result.entry.category, 'savings');
    assert.equal(result.entry.amount, 125.5);
    assert.equal(result.entry.note, 'Birthday money');
    assert.equal(result.entry.goalId, goal.id);
    assert.equal(result.entry.memberId, member.member.id);
    assert.equal(result.entry.memberName, 'Priya Sharma');
    assert.equal(result.entry.createdById, member.member.id);
    // Default date: today in the family time zone.
    assert.equal(result.entry.date, localMidnight(0).toISOString());
    assert.equal((await Goal.findById(goal.id).lean()).savedMinor, 12550);
    // The member sees their contribution in their ledger.
    assert.deepEqual((await listEntries(member.auth, { goalId: goal.id })).data.map((e) => e.id), [result.entry.id]);
  });

  it('reaching the target → achieved + one goal_achieved push to the whole family', async () => {
    const { admin, member } = await setupFamilies();
    const goal = await createGoal(admin.auth, { title: 'New fridge', targetAmount: 300 });
    await contribute(member.auth, goal.id, { amount: 299.99 });
    assert.equal((await goalPushes()).length, 0);

    const { goal: achieved } = await contribute(member.auth, goal.id, { amount: 0.01 });
    assert.equal(achieved.status, 'achieved');
    assert.equal(achieved.progress, 1);
    assert.ok((await Goal.findById(goal.id).lean()).achievedAt instanceof Date);

    const pushes = await goalPushes();
    assert.equal(pushes.length, 1);
    const [push] = pushes;
    assert.equal(push.id, goal.id);
    assert.equal(push.familyId, admin.family.id);
    assert.equal(push.route, '/money');
    assert.equal(push.titleKey, 'ledger.push.goalAchieved.title');
    assert.equal(push.bodyKey, 'ledger.push.goalAchieved.body');
    assert.equal(push.vars.title, 'New fridge');
    assert.equal(push.requestedMemberIds, null); // whole family
    assert.deepEqual([...push.memberIds].sort(), [admin.member.id, member.member.id].sort());

    // Overshooting stays achieved; no second push.
    const { goal: over } = await contribute(admin.auth, goal.id, { amount: 50 });
    assert.equal(over.status, 'achieved');
    assert.equal(over.savedAmount, 350);
    assert.equal(over.progress, 1);
    assert.equal((await goalPushes()).length, 1);
  });

  it('concurrent contributions are atomic and only one of them sends the push', async () => {
    const { admin, member } = await setupFamilies();
    const goal = await createGoal(admin.auth, { targetAmount: 500 });
    const results = await Promise.all(
      Array.from({ length: 10 }, (_, i) => request.post(contributionsUrl(goal.id)).set(i % 2 ? admin.auth : member.auth).send({ amount: 100 })),
    );
    for (const res of results) assertOk(res, 201);
    const stored = await Goal.findById(goal.id).lean();
    assert.equal(stored.savedMinor, 100000);
    assert.equal(stored.status, 'achieved');
    assert.equal(await LedgerEntry.countDocuments({ goalId: goal.id }), 10);
    assert.equal((await goalPushes()).length, 1);
  });

  it('archived goals reject contributions with 409 VALIDATION_ERROR', async () => {
    const { admin, member } = await setupFamilies();
    const goal = await createGoal(admin.auth);
    await request.patch(goalUrl(goal.id)).set(admin.auth).send({ status: 'archived' }).expect(200);
    const res = await request.post(contributionsUrl(goal.id)).set(member.auth).send({ amount: 10 });
    const error = assertError(res, 409, 'VALIDATION_ERROR');
    assert.equal(typeof error.details.goalId, 'string');
    assert.match(error.message, /archived/i);
    assert.equal(await LedgerEntry.countDocuments(), 0);
    assert.equal((await Goal.findById(goal.id).lean()).savedMinor, 0);
  });

  it('other family / unknown goal → 404, bad id → 400, invalid body → 422', async () => {
    const { admin, outsider } = await setupFamilies();
    const goal = await createGoal(admin.auth);
    assertError(await request.post(contributionsUrl(goal.id)).set(outsider.auth).send({ amount: 10 }), 404, 'NOT_FOUND');
    assertError(await request.post(contributionsUrl(UNKNOWN_ID)).set(admin.auth).send({ amount: 10 }), 404, 'NOT_FOUND');
    assertError(await request.post(contributionsUrl('bad')).set(admin.auth).send({ amount: 10 }), 400, 'BAD_REQUEST');
    assertValidation(await request.post(contributionsUrl(goal.id)).set(admin.auth).send({}), 'amount');
    for (const body of [{ amount: 0 }, { amount: -1 }, { amount: 0.004 }, { amount: '5' }]) {
      assertValidation(await request.post(contributionsUrl(goal.id)).set(admin.auth).send(body), 'amount');
    }
    assertValidation(await request.post(contributionsUrl(goal.id)).set(admin.auth).send({ amount: 5, note: 'x'.repeat(201) }), 'note');
    assertValidation(
      await request.post(contributionsUrl(goal.id)).set(admin.auth).send({ amount: 5, date: localMidnight(2).toISOString() }),
      'date',
    );
    assert.equal(await LedgerEntry.countDocuments(), 0);
    assert.equal((await Goal.findById(goal.id).lean()).savedMinor, 0);
  });

  it('accepts an explicit date (normalised) and null / blank dates mean today', async () => {
    const { admin } = await setupFamilies();
    const goal = await createGoal(admin.auth);
    assert.equal((await contribute(admin.auth, goal.id, { date: '2025-02-28' })).entry.date, '2025-02-27T18:30:00.000Z');
    assert.equal((await contribute(admin.auth, goal.id, { date: null })).entry.date, localMidnight(0).toISOString());
    assert.equal((await contribute(admin.auth, goal.id, { date: '' })).entry.date, localMidnight(0).toISOString());
    assert.equal((await contribute(admin.auth, goal.id, { date: localDay(1) })).entry.date, localMidnight(1).toISOString());
  });
});

// ---------------------------------------------------------------- i18n & serializers

describe('i18n & serializers', () => {
  it('every ledger message key used by the module exists in en/ledger.json', () => {
    const keys = [
      'ledger.push.goalAchieved.title',
      'ledger.push.goalAchieved.body',
      'ledger.errors.categoryForType',
      'ledger.errors.dateInFuture',
      'ledger.errors.dateTooOld',
      'ledger.errors.memberNotInFamily',
      'ledger.errors.memberSelfOnly',
      'ledger.errors.goalAmountLocked',
      'ledger.errors.goalEntryLocked',
      'ledger.errors.goalArchived',
      'ledger.errors.goalFull',
    ];
    for (const key of keys) assert.ok(hasTranslation(key, 'en'), key);
    assert.match(t('en', 'ledger.push.goalAchieved.body', { title: 'Goa' }), /Goa/);
    // Unsupported / untranslated locales fall back to English.
    assert.equal(t('ta', 'ledger.errors.goalArchived'), t('en', 'ledger.errors.goalArchived'));
  });

  it('error messages are localized from ledger.json (member recording for someone else)', async () => {
    const { admin, member } = await setupFamilies();
    const res = await request.post(ENTRIES).set(member.auth).set('Accept-Language', 'en').send(entryBody({ memberId: admin.member.id }));
    const error = assertError(res, 403, 'FORBIDDEN');
    assert.equal(error.message, t('en', 'ledger.errors.memberSelfOnly'));
  });

  it('serializeEntry / serializeGoal accept lean objects and never expose minor units', async () => {
    const { admin } = await setupFamilies();
    const goal = await createGoal(admin.auth, { targetAmount: 3 });
    await contribute(admin.auth, goal.id, { amount: 1 });
    const leanGoal = await Goal.findById(goal.id).lean();
    const serialized = serializeGoal(leanGoal);
    assert.deepEqual(Object.keys(serialized).sort(), GOAL_KEYS);
    assert.equal(serialized.progress, 0.3333);
    assert.equal(serialized.savedAmount, 1);
    const leanEntry = await LedgerEntry.findOne().lean();
    const entry = serializeEntry(leanEntry);
    assert.deepEqual(Object.keys(entry).sort(), ENTRY_KEYS);
    assert.equal(entry.memberName, admin.member.name);
    assert.equal(serializeEntry(null), null);
    assert.equal(serializeGoal(null), null);
  });
});

// ---------------------------------------------------------------- hardening (b-ledger-harden)
//
// Regression tests for the adversarial review (docs/progress/b-ledger.md "Hardening review"). Each
// `it` names the issue it guards against.

describe('hardening: text (lengths in UTF-16 units, normalisation, invisible text)', () => {
  const EMOJI = '😀'; // 1 code point, 2 UTF-16 code units

  it('counts note / title / description lengths in UTF-16 units and never echoes the text back', async () => {
    const { admin, member } = await setupFamilies();
    // 100 emoji = 200 units = the limit; 101 emoji used to pass zod (code points) and fail in Mongoose
    // with "Path `note` (`😀😀…`, length 202) is longer than …".
    assert.equal((await createEntry(admin.auth, { note: EMOJI.repeat(100) })).note, EMOJI.repeat(100));
    const tooLong = EMOJI.repeat(101);
    const cases = [
      [request.post(ENTRIES).set(admin.auth).send(entryBody({ note: tooLong })), 'note', 'Note must be at most 200 characters'],
      [request.post(GOALS).set(admin.auth).send({ title: EMOJI.repeat(41), targetAmount: 10 }), 'title', 'Title must be at most 80 characters'],
      [
        request.post(GOALS).set(admin.auth).send({ title: 'Car', targetAmount: 10, description: EMOJI.repeat(501) }),
        'description',
        'Description must be at most 1000 characters',
      ],
    ];
    const entry = await createEntry(member.auth);
    const goal = await createGoal(admin.auth, { title: EMOJI.repeat(40), description: EMOJI.repeat(500) });
    assert.equal(goal.title, EMOJI.repeat(40));
    cases.push(
      [request.patch(entryUrl(entry.id)).set(member.auth).send({ note: tooLong }), 'note', 'Note must be at most 200 characters'],
      [request.patch(goalUrl(goal.id)).set(admin.auth).send({ title: EMOJI.repeat(41) }), 'title', 'Title must be at most 80 characters'],
      [request.post(contributionsUrl(goal.id)).set(member.auth).send({ amount: 1, note: tooLong }), 'note', 'Note must be at most 200 characters'],
    );
    for (const [pending, path, message] of cases) {
      const res = await pending;
      const error = assertValidation(res, path);
      assert.equal(error.details[path], message);
      assert.ok(!JSON.stringify(res.body).includes(EMOJI), 'the rejected text must not be echoed');
    }
    assert.equal((await LedgerEntry.findById(entry.id).lean()).note, 'Veggies');
    assert.equal((await Goal.findById(goal.id).lean()).savedMinor, 0);
  });

  it('normalises text like tasks / notices: well-formed UTF-16, control characters, blank-looking values', async () => {
    const { admin } = await setupFamilies();
    // A lone surrogate is stored by MongoDB as U+FFFD: the response must equal what was saved.
    const lone = await createEntry(admin.auth, { note: 'ab\ud800cd' });
    assert.equal(lone.note, 'ab�cd');
    assert.equal((await LedgerEntry.findById(lone.id).lean()).note, lone.note);
    // Multi-line notes: CRLF → LF, NUL / BEL / … removed.
    assert.equal((await createEntry(admin.auth, { note: 'a\u0000b\u0007c\r\nd' })).note, 'abc\nd');
    // Only zero-width / format characters → no note.
    assert.equal((await createEntry(admin.auth, { note: '​‍⁠' })).note, null);
    // Scripts, emoji and RTL text are kept as typed.
    assert.equal((await createEntry(admin.auth, { note: 'بقالة أسبوعية 🥦' })).note, 'بقالة أسبوعية 🥦');
    assert.equal((await createEntry(admin.auth, { note: 'किराना 👨‍👩‍👧' })).note, 'किराना 👨‍👩‍👧');

    // Goal titles are one line (they are shown in the goal_achieved push) and must be visible.
    const goal = await createGoal(admin.auth, { title: '  Goa\ntrip\t2026 ', description: 'Line 1\r\nLine 2\u0000' });
    assert.equal(goal.title, 'Goa trip 2026');
    assert.equal(goal.description, 'Line 1\nLine 2');
    for (const title of ['​', '​‌⁠', '\u0000', '\n\t']) {
      const error = assertValidation(await request.post(GOALS).set(admin.auth).send({ title, targetAmount: 10 }), 'title');
      assert.equal(error.details.title, 'Title is required');
      assertValidation(await request.patch(goalUrl(goal.id)).set(admin.auth).send({ title }), 'title');
    }
    const invisible = assertOk(await request.patch(goalUrl(goal.id)).set(admin.auth).send({ description: '​' }));
    assert.equal(invisible.description, null);
    assert.equal((await Goal.findById(goal.id).lean()).title, 'Goa trip 2026');
  });
});

describe('hardening: injection, mass assignment, bounds', () => {
  it('query operators and repeated keys never widen what a member sees', async () => {
    const { admin, member, outsider } = await setupFamilies();
    await createEntry(admin.auth, { note: 'admin only' });
    const own = await createEntry(member.auth);
    await createEntry(outsider.auth);
    // `memberId[$ne]=…` is a plain unknown key for the query parser → ignored, visibility still applies.
    for (const qs of ['memberId[$ne]=x', 'type[$ne]=income', 'goalId[$exists]=true', 'createdById=' + admin.member.id]) {
      const res = await request.get(`${ENTRIES}?${qs}`).set(member.auth);
      assert.deepEqual(assertOk(res).map((e) => e.id), [own.id], qs);
    }
    const repeated = await request.get(`${ENTRIES}?memberId=${admin.member.id}&memberId=${member.member.id}`).set(member.auth);
    assertValidation(repeated, 'memberId');
    assertValidation(await request.get(`${SUMMARY}?month=2025-01&month=2025-02`).set(member.auth), 'month');
    assertValidation(await request.get(`${GOALS}?status=all&status=active`).set(member.auth), 'status');
  });

  it('operator objects in bodies are rejected (422), never passed to MongoDB', async () => {
    const { admin, member } = await setupFamilies();
    const goal = await createGoal(admin.auth);
    const op = { $ne: null };
    for (const field of ['type', 'amount', 'category', 'note', 'date', 'memberId']) {
      assertValidation(await request.post(ENTRIES).set(member.auth).send(entryBody({ [field]: op })), field);
    }
    const entry = await createEntry(member.auth);
    for (const field of ['type', 'amount', 'category', 'note', 'date', 'memberId']) {
      assertValidation(await request.patch(entryUrl(entry.id)).set(member.auth).send({ [field]: op }), field);
    }
    for (const field of ['amount', 'note', 'date']) {
      assertValidation(await request.post(contributionsUrl(goal.id)).set(member.auth).send({ amount: 1, [field]: op }), field);
    }
    for (const field of ['title', 'description', 'targetAmount', 'targetDate', 'status']) {
      assertValidation(await request.patch(goalUrl(goal.id)).set(admin.auth).send({ [field]: op }), field);
    }
    // `__proto__` in JSON is just an unknown key.
    const proto = await request
      .post(ENTRIES)
      .set(member.auth)
      .set('Content-Type', 'application/json')
      .send(`{"__proto__":{"memberId":"${admin.member.id}"},"type":"expense","amount":1,"category":"rent","date":"2025-04-01"}`);
    assert.equal(assertOk(proto, 201).memberId, member.member.id);
    // Non-object bodies.
    assertValidation(await request.post(ENTRIES).set(member.auth).send([entryBody()]), 'body');
    assertError(await request.post(ENTRIES).set(member.auth).set('Content-Type', 'application/json').send('null'), 400, 'BAD_REQUEST');
    assert.equal(await LedgerEntry.countDocuments({ memberId: admin.member.id }), 0);
    assert.equal((await Goal.findById(goal.id).lean()).savedMinor, 0);
  });

  it('mass assignment: saved amount, status, ownership and family fields are never taken from a body', async () => {
    const { admin, member, outsider } = await setupFamilies();
    const forged = {
      savedAmount: 999,
      savedMinor: 99900,
      progress: 1,
      status: 'achieved',
      achievedAt: new Date().toISOString(),
      familyId: outsider.family.id,
      createdById: member.member.id,
      id: UNKNOWN_ID,
      _id: UNKNOWN_ID,
    };
    const created = await createGoal(admin.auth, { targetAmount: 100, ...forged });
    assert.equal(created.status, 'active');
    assert.equal(created.savedAmount, 0);
    assert.equal(created.createdById, admin.member.id);
    assert.notEqual(created.id, UNKNOWN_ID);

    const { status: _ignored, ...patchForged } = forged;
    const patched = assertOk(await request.patch(goalUrl(created.id)).set(admin.auth).send(patchForged));
    assert.equal(patched.savedAmount, 0);
    assert.equal(patched.status, 'active');
    const raw = await Goal.findById(created.id).lean();
    assert.equal(String(raw.familyId), admin.family.id);
    assert.equal(raw.savedMinor, 0);
    assert.equal(raw.achievedAt, null);
    assert.equal(String(raw.createdById), admin.member.id);

    // An ordinary entry can never be linked to a goal (that would change the saved amount on delete).
    const entry = await createEntry(member.auth);
    const edited = assertOk(
      await request
        .patch(entryUrl(entry.id))
        .set(member.auth)
        .send({ goalId: created.id, createdById: admin.member.id, familyId: outsider.family.id, amountMinor: 5, memberName: 'X' }),
    );
    assert.equal(edited.goalId, null);
    assert.equal(edited.createdById, member.member.id);
    assert.equal(edited.memberName, 'Priya Sharma');
    const rawEntry = await LedgerEntry.findById(entry.id).lean();
    assert.equal(String(rawEntry.familyId), admin.family.id);
    assert.equal(rawEntry.amountMinor, 10000);

    // A contribution is always the caller's expense/savings entry for *this* goal.
    const { entry: contribution, goal: after } = await contribute(member.auth, created.id, {
      amount: 1,
      memberId: admin.member.id,
      createdById: admin.member.id,
      type: 'income',
      category: 'gift',
      goalId: UNKNOWN_ID,
      savedAmount: 1000,
    });
    assert.equal(contribution.memberId, member.member.id);
    assert.equal(contribution.createdById, member.member.id);
    assert.equal(contribution.type, 'expense');
    assert.equal(contribution.category, 'savings');
    assert.equal(contribution.goalId, created.id);
    assert.equal(after.savedAmount, 1);
  });

  it('numeric edge cases: Infinity, -0, 1e13, overflow of a goal', async () => {
    const { admin } = await setupFamilies();
    const raw = (amount) =>
      request
        .post(ENTRIES)
        .set(admin.auth)
        .set('Content-Type', 'application/json')
        .send(`{"type":"expense","amount":${amount},"category":"rent","date":"2025-04-01"}`);
    for (const amount of ['1e400', '-0', '1e13', '"1e3"', '[1]', '{}']) assertValidation(await raw(amount), 'amount');
    // 999999999999.995 rounds to exactly the 1e12 cap.
    assert.equal(assertOk(await raw('999999999999.995'), 201).amount, 1e12);

    const goal = await createGoal(admin.auth, { targetAmount: 1e12 });
    await Goal.updateOne({ _id: goal.id }, { $set: { savedMinor: Number.MAX_SAFE_INTEGER - 50 } });
    const full = assertValidation(await request.post(contributionsUrl(goal.id)).set(admin.auth).send({ amount: 1 }), 'amount');
    assert.equal(full.message, t('en', 'ledger.errors.goalFull'));
    assert.equal((await Goal.findById(goal.id).lean()).savedMinor, Number.MAX_SAFE_INTEGER - 50);
    assert.equal(await LedgerEntry.countDocuments({ goalId: goal.id }), 0);
  });

  it('pagination and months far outside the data never error (empty pages, zero summaries)', async () => {
    const { admin } = await setupFamilies();
    await createEntry(admin.auth);
    for (const page of [2, 1e6, 1e15]) {
      const body = await listEntries(admin.auth, { page, limit: 100 });
      assert.deepEqual(body.data, []);
      assert.equal(body.meta.total, 1);
      assert.equal(body.meta.hasMore, false);
    }
    for (const month of ['0000-01', '1969-12', '9999-12']) {
      assert.equal((await listEntries(admin.auth, { month })).meta.total, 0);
      const summary = assertOk(await request.get(SUMMARY).set(admin.auth).query({ month }));
      assert.equal(summary.month, month);
      assert.equal(summary.net, 0);
    }
    const { headers } = await request.get(SUMMARY).set(admin.auth);
    assert.equal(headers['cache-control'], 'private, no-store');
    assert.equal((await request.get(GOALS).set(admin.auth)).headers['cache-control'], 'private, no-store');
  });

  it('goal target dates are family-local days within 2000-01-01 … 2100-12-31 (past days allowed)', async () => {
    const { admin } = await setupFamilies();
    for (const targetDate of ['1999-12-31', '2101-01-01', '1999-12-31T06:00:00.000Z']) {
      const error = assertValidation(await request.post(GOALS).set(admin.auth).send({ title: 'Car', targetAmount: 1, targetDate }), 'targetDate');
      assert.match(error.details.targetDate, /between/);
    }
    assert.equal((await createGoal(admin.auth, { targetDate: '2000-01-01' })).targetDate, '1999-12-31T18:30:00.000Z');
    const goal = await createGoal(admin.auth, { targetDate: '2100-12-31' });
    assert.equal(goal.targetDate, '2100-12-30T18:30:00.000Z');
    const range = assertValidation(await request.patch(goalUrl(goal.id)).set(admin.auth).send({ targetDate: '1999-12-31' }), 'targetDate');
    assert.equal(range.message, t('en', 'ledger.errors.targetDateRange'));
    assert.equal((await Goal.findById(goal.id).lean()).targetDate.toISOString(), '2100-12-30T18:30:00.000Z');
    assert.equal(assertOk(await request.patch(goalUrl(goal.id)).set(admin.auth).send({ targetDate: '2001-05-01' })).targetDate, '2001-04-30T18:30:00.000Z');
  });

  it('dashboard helpers reject a malformed month (422, not a 500) and clamp the goal limit', async () => {
    const { admin } = await setupFamilies();
    for (const month of ['2025-13', '2025-1', 'April']) {
      await assert.rejects(getMonthSummary({ familyId: admin.family.id, month }), (err) => {
        assert.equal(err.status, 422);
        assert.equal(err.code, 'VALIDATION_ERROR');
        return true;
      });
    }
    for (let i = 0; i < 3; i += 1) await createGoal(admin.auth, { title: `Goal ${i}` });
    // Mongo's limit(0) / negative limits mean "no limit".
    assert.equal((await listActiveGoals(admin.family.id, { limit: 0 })).length, 1);
    assert.equal((await listActiveGoals(admin.family.id, { limit: -5 })).length, 1);
    assert.equal((await listActiveGoals(admin.family.id, { limit: 'all' })).length, 3);
    assert.equal((await listActiveGoals(admin.family.id)).length, 3);
  });
});

describe('hardening: goal_achieved push (spam, recipients, locale)', () => {
  it('a contribute → delete → contribute loop notifies the family only once per 24 h', async () => {
    const { admin, member } = await setupFamilies();
    const goal = await createGoal(admin.auth, { targetAmount: 100 });
    for (let i = 0; i < 4; i += 1) {
      const { entry, goal: reached } = await contribute(member.auth, goal.id, { amount: 100 });
      assert.equal(reached.status, 'achieved');
      assertOk(await request.delete(entryUrl(entry.id)).set(member.auth));
      assert.equal((await Goal.findById(goal.id).lean()).status, 'active');
    }
    assert.equal((await goalPushes()).length, 1);

    // Once the cooldown has passed, reaching the target again is news again.
    const past = new Date(Date.now() - GOAL_ACHIEVED_NOTIFY_COOLDOWN_MS - 1000);
    await Goal.updateOne({ _id: goal.id }, { $set: { achievedAt: past } });
    await contribute(member.auth, goal.id, { amount: 100 });
    assert.equal((await goalPushes()).length, 2);
  });

  it('a new target is a new achievement: raising the target and reaching it notifies again', async () => {
    const { admin, member } = await setupFamilies();
    const goal = await createGoal(admin.auth, { targetAmount: 100 });
    await contribute(member.auth, goal.id, { amount: 150 });
    assert.equal((await goalPushes()).length, 1);
    // Lowering the target of an already achieved goal keeps it achieved: no push.
    assert.equal(assertOk(await request.patch(goalUrl(goal.id)).set(admin.auth).send({ targetAmount: 120 })).status, 'achieved');
    assert.equal((await goalPushes()).length, 1);
    // Raising it reopens the goal and forgets the old achievement.
    assert.equal(assertOk(await request.patch(goalUrl(goal.id)).set(admin.auth).send({ targetAmount: 200 })).status, 'active');
    assert.equal((await Goal.findById(goal.id).lean()).achievedAt, null);
    await contribute(admin.auth, goal.id, { amount: 50 });
    assert.equal((await goalPushes()).length, 2);
  });

  it('only current members of the family receive it, each in their device / account locale', async () => {
    const { admin, member, outsider } = await setupFamilies();
    const leaver = await joinFamilyAs(admin.family.inviteCode, { name: 'Leaver', locale: 'ta' });
    await User.updateOne({ _id: member.user.id }, { $set: { locale: 'es' } });
    await Device.create([
      { userId: admin.user.id, token: 'tok-admin', platform: 'android', locale: 'hi' },
      { userId: member.user.id, token: 'tok-member', platform: 'ios' }, // → account locale `es`
      { userId: outsider.user.id, token: 'tok-outsider', platform: 'android' },
      { userId: leaver.user.id, token: 'tok-leaver', platform: 'android' },
    ]);
    // Removed from the family (user unlinked, as family/me do) → no family notifications.
    await User.updateOne({ _id: leaver.user.id }, { $set: { familyId: null, memberId: null } });
    await Member.deleteOne({ _id: leaver.member.id });

    const goal = await createGoal(admin.auth, { title: 'مكة 🕋', targetAmount: 10 });
    await contribute(member.auth, goal.id, { amount: 10 });
    const [push] = await goalPushes();
    assert.equal(push.route, '/money');
    assert.equal(push.id, goal.id);
    assert.deepEqual([...push.memberIds].sort(), [admin.member.id, member.member.id].sort());
    const byToken = Object.fromEntries(push.messages.map((m) => [m.token, m]));
    assert.deepEqual(Object.keys(byToken).sort(), ['tok-admin', 'tok-member']);
    assert.equal(byToken['tok-admin'].locale, 'hi');
    assert.equal(byToken['tok-member'].locale, 'es');
    for (const message of push.messages) {
      assert.equal(message.title, t(message.locale, 'ledger.push.goalAchieved.title'));
      assert.equal(message.body, t(message.locale, 'ledger.push.goalAchieved.body', { title: 'مكة 🕋' }));
    }
  });
});

describe('hardening: races, compensation, dangling references', () => {
  afterEach(() => mock.restoreAll());

  /** savedMinor must always equal the sum of the goal's linked entries (nothing clamped in these tests). */
  async function assertBalanced(goalId) {
    const goal = await Goal.findById(goalId).lean();
    const entries = await LedgerEntry.find({ goalId }).lean();
    assert.equal(goal.savedMinor, entries.reduce((sum, e) => sum + e.amountMinor, 0));
    assert.equal(goal.status === 'archived' || goal.status === (goal.savedMinor >= goal.targetMinor ? 'achieved' : 'active'), true);
    return { goal, entries };
  }

  it('contributions racing an archive: every 201 is recorded, every other request is a clean 409', async () => {
    const { admin, member } = await setupFamilies();
    const goal = await createGoal(admin.auth, { targetAmount: 1000 });
    const results = await Promise.all(
      Array.from({ length: 12 }, (_, i) =>
        i === 5
          ? request.patch(goalUrl(goal.id)).set(admin.auth).send({ status: 'archived' })
          : request.post(contributionsUrl(goal.id)).set(member.auth).send({ amount: 10 }),
      ),
    );
    const contributions = results.filter((_, i) => i !== 5);
    for (const res of contributions) assert.ok([201, 409].includes(res.status), JSON.stringify(res.body));
    const { goal: stored, entries } = await assertBalanced(goal.id);
    assert.equal(stored.status, 'archived');
    assert.equal(entries.length, contributions.filter((r) => r.status === 201).length);
  });

  it('contributions racing entry deletions and a target change stay balanced', async () => {
    const { admin, member } = await setupFamilies();
    const goal = await createGoal(admin.auth, { targetAmount: 50 });
    const first = await Promise.all(Array.from({ length: 6 }, () => contribute(member.auth, goal.id, { amount: 10 })));
    const results = await Promise.all([
      ...first.slice(0, 4).map(({ entry }) => request.delete(entryUrl(entry.id)).set(member.auth)),
      ...Array.from({ length: 4 }, () => request.post(contributionsUrl(goal.id)).set(admin.auth).send({ amount: 10 })),
      request.patch(goalUrl(goal.id)).set(admin.auth).send({ targetAmount: 55 }),
    ]);
    for (const res of results) assert.ok([200, 201].includes(res.status), JSON.stringify(res.body));
    const { goal: stored } = await assertBalanced(goal.id);
    assert.equal(stored.savedMinor, 6000);
    assert.equal(stored.status, 'achieved');
    assert.equal((await goalPushes()).length, 1);
  });

  it('an achievement is announced even when an entry deletion wins the achieved transition', async () => {
    const { admin, member } = await setupFamilies();
    const goal = await createGoal(admin.auth, { targetAmount: 100 });
    const { entry } = await contribute(member.auth, goal.id, { amount: 50 });
    // A concurrent contribution of 100 whose `$inc` has landed but whose reconcile has not run yet.
    await Goal.updateOne({ _id: goal.id }, { $inc: { savedMinor: 10000 } });
    assertOk(await request.delete(entryUrl(entry.id)).set(member.auth));
    const stored = await Goal.findById(goal.id).lean();
    assert.equal(stored.savedMinor, 10000);
    assert.equal(stored.status, 'achieved');
    const pushes = await goalPushes();
    assert.equal(pushes.length, 1);
    assert.equal(pushes[0].id, goal.id);
  });

  it('a failed entry write is compensated: the saved amount is restored and nothing is announced', async () => {
    const { admin } = await setupFamilies();
    const goal = await createGoal(admin.auth, { targetAmount: 100 });
    mock.method(LedgerEntry, 'create', async () => {
      throw new Error('disk full');
    });
    const error = assertError(await request.post(contributionsUrl(goal.id)).set(admin.auth).send({ amount: 100 }), 500, 'INTERNAL_ERROR');
    assert.ok(!JSON.stringify(error).includes('disk full'));
    mock.restoreAll();
    const stored = await Goal.findById(goal.id).lean();
    assert.equal(stored.savedMinor, 0);
    assert.equal(stored.status, 'active');
    assert.equal(stored.achievedAt, null);
    assert.equal((await goalPushes()).length, 0);
  });

  it('a goal deleted while a contribution is written leaves no orphan entry (404)', async () => {
    const { admin, member } = await setupFamilies();
    const goal = await createGoal(admin.auth, { targetAmount: 100 });
    const original = LedgerEntry.create.bind(LedgerEntry);
    mock.method(LedgerEntry, 'create', async (...args) => {
      await request.delete(goalUrl(goal.id)).set(admin.auth).expect(200);
      return original(...args);
    });
    assertError(await request.post(contributionsUrl(goal.id)).set(member.auth).send({ amount: 100 }), 404, 'NOT_FOUND');
    mock.restoreAll();
    assert.equal(await LedgerEntry.countDocuments(), 0);
    assert.equal(await Goal.countDocuments(), 0);
    assert.equal((await goalPushes()).length, 0);
  });

  it('an entry whose goal vanished without detaching is unlinked on edit instead of staying locked', async () => {
    const { admin, member } = await setupFamilies();
    const goal = await createGoal(admin.auth);
    const { entry } = await contribute(member.auth, goal.id, { amount: 40 });
    await Goal.deleteOne({ _id: goal.id }); // e.g. a goal deletion interrupted before its entries were detached
    const edited = assertOk(await request.patch(entryUrl(entry.id)).set(member.auth).send({ amount: 45, category: 'shopping' }));
    assert.equal(edited.goalId, null);
    assert.equal(edited.amount, 45);
    assert.equal(edited.category, 'shopping');
    assert.equal((await LedgerEntry.findById(entry.id).lean()).goalId, null);
  });

  it('entries of a deleted member stay editable by the admin but cannot be moved to a deleted member', async () => {
    const { admin } = await setupFamilies();
    const kid = await managedMember(admin.family.id, { name: 'Kid' });
    const gone = await managedMember(admin.family.id, { name: 'Gone' });
    const entry = await createEntry(admin.auth, { memberId: kid.id });
    const other = await createEntry(admin.auth);
    await Member.deleteMany({ _id: { $in: [kid.id, gone.id] } });

    const edited = assertOk(await request.patch(entryUrl(entry.id)).set(admin.auth).send({ memberId: kid.id, note: 'kept' }));
    assert.equal(edited.memberId, kid.id);
    assert.equal(edited.memberName, 'Kid');
    assert.deepEqual((await listEntries(admin.auth, { memberId: kid.id })).data.map((e) => e.id), [entry.id]);
    assertValidation(await request.patch(entryUrl(other.id)).set(admin.auth).send({ memberId: gone.id }), 'memberId');
    assertValidation(await request.post(ENTRIES).set(admin.auth).send(entryBody({ memberId: gone.id })), 'memberId');
  });
});

describe('hardening: family time-zone change (rebaseBusinessDates for PATCH /family)', () => {
  it('keeps entries and goal target dates on their calendar day in the new zone', async () => {
    const { admin, outsider } = await setupFamilies();
    const april1 = await createEntry(admin.auth, { date: '2025-04-01' });
    const march31 = await createEntry(admin.auth, { date: '2025-03-31', amount: 5 });
    const goal = await createGoal(admin.auth, { targetDate: '2026-12-01' });
    const noDate = await createGoal(admin.auth, { title: 'Someday' });
    const theirs = await createEntry(outsider.auth, { date: '2025-04-01' });
    await Family.updateOne({ _id: admin.family.id }, { $set: { timezone: 'America/New_York' } });

    // Without the rebase, 1 April (IST midnight = 2025-03-31T18:30Z) would count for March in New York.
    assert.equal((await listEntries(admin.auth, { month: '2025-04' })).meta.total, 0);

    const moved = await rebaseBusinessDates({ familyId: admin.family.id, fromTimeZone: IST, toTimeZone: 'America/New_York' });
    assert.deepEqual(moved, { entries: 2, goals: 1 });
    assert.equal((await LedgerEntry.findById(april1.id).lean()).date.toISOString(), '2025-04-01T04:00:00.000Z');
    assert.equal((await LedgerEntry.findById(march31.id).lean()).date.toISOString(), '2025-03-31T04:00:00.000Z');
    assert.equal((await Goal.findById(goal.id).lean()).targetDate.toISOString(), '2026-12-01T05:00:00.000Z');
    assert.equal((await Goal.findById(noDate.id).lean()).targetDate, null);
    assert.deepEqual((await listEntries(admin.auth, { month: '2025-04' })).data.map((e) => e.id), [april1.id]);
    const april = assertOk(await request.get(SUMMARY).set(admin.auth).query({ month: '2025-04' }));
    assert.equal(april.expense, 100);
    // Other families are untouched; running it again (or with the same zone) changes nothing.
    assert.equal((await LedgerEntry.findById(theirs.id).lean()).date.toISOString(), '2025-03-31T18:30:00.000Z');
    assert.deepEqual(
      await rebaseBusinessDates({ familyId: admin.family.id, fromTimeZone: 'America/New_York', toTimeZone: 'America/New_York' }),
      { entries: 0, goals: 0 },
    );
    assert.deepEqual(
      await rebaseBusinessDates({ familyId: admin.family.id, fromTimeZone: IST, toTimeZone: 'America/New_York' }),
      { entries: 0, goals: 0 },
    );
  });
});

