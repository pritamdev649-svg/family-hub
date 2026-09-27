/**
 * Dashboard: docs/03-API_CONTRACT.md §11 (`GET /dashboard`).
 *
 * Covers the envelope and exact payload shape, the permission matrix (admin / member / other family /
 * removed member / no token), that unknown query keys can neither fail the request nor widen its
 * scope, the per-member task counters (pending, overdue before the start of today, completed since
 * Monday — all in the family time zone, cross-checked against `GET /tasks`), day / week / month
 * boundaries with a fixed clock for a zone east (Asia/Kolkata) and west (America/Los_Angeles) of
 * UTC, the list limits and orders (my tasks ≤ 5 dueDate asc with no due date last, active goals ≤ 3,
 * notices ≤ 3 pinned first), SOS lazy expiry, the month summary scope (admin → family, member →
 * personal), privacy (inviteCode for admins only, lastLocation only when shared `always`, SOS
 * locations follow the owner's sharing mode, no internal keys), that every section is identical to
 * the dedicated endpoint (shared serializers), members / authors who left, an invalid stored time
 * zone, and the query budget (one aggregation for all counters, whatever the family size).
 *
 * Hardening suite (b-dashboard-harden, last describe blocks): token edge cases (expired, deleted
 * user, `alg: none`), HEAD / trailing slash / sub-paths, request bodies on GET (operators, mass
 * assignment, malformed, oversized), prototype-pollution query keys, a forged cross-family actor,
 * exact contract key sets of every nested object, Unicode / emoji / RTL round trips, money edge
 * cases, a DST week and ±14 h / +5:45 zones, completions after the current week, orphaned SOS
 * alerts, concurrent requests (lazy expiry once, no push / e-mail side effects) and the query plans
 * of the two reads that must not scan a family's whole history.
 */
import {
  API,
  addManagedMember,
  flushPushes,
  joinFamilyAs,
  outbox,
  registerFamilyAdmin,
  resetDb,
  sentPushes,
  setupTestApp,
  teardownTestApp,
} from './helpers.js';
import assert from 'node:assert/strict';
import { after, afterEach, before, beforeEach, describe, it } from 'node:test';

const { default: mongoose } = await import('mongoose');
const { default: jwt } = await import('jsonwebtoken');
const { env } = await import('../src/config/env.js');
const { JWT_AUDIENCE, JWT_ISSUER } = await import('../src/lib/constants.js');
const { Family, Goal, LedgerEntry, Member, Notice, SosAlert, Task, User } = await import('../src/models/index.js');
const { currentMonth, startOfDay, startOfWeek, zonedParts, zonedTimeToUtc } = await import('../src/lib/dates.js');
const { getDashboard, memberTaskStats } = await import('../src/modules/dashboard/dashboard.service.js');
const { listLatestNotices } = await import('../src/modules/notices/notices.service.js');

let request;

before(async () => {
  ({ request } = await setupTestApp());
});
beforeEach(resetDb);
after(teardownTestApp);

// ---------------------------------------------------------------- helpers

const IST = 'Asia/Kolkata';
const OBJECT_ID = /^[a-f0-9]{24}$/;
const DAY_MS = 24 * 60 * 60 * 1000;
const DASHBOARD_KEYS = ['activeSos', 'family', 'goals', 'latestNotices', 'me', 'members', 'monthSummary', 'myTasks'];
const STAT_KEYS = ['completedThisWeek', 'member', 'overdueTasks', 'pendingTasks'];
const FORBIDDEN_KEYS = new Set([
  '_id',
  '__v',
  'passwordHash',
  'tokenHash',
  'codeHash',
  'amountMinor',
  'targetMinor',
  'savedMinor',
  'allergiesEnc',
  'notesEnc',
]);

const newId = () => new mongoose.Types.ObjectId();

/** `GET /dashboard` as `auth`; asserts a 200 success envelope and returns `data`. */
async function dashboard(auth, query = '') {
  const res = await request.get(`${API}/dashboard${query}`).set(auth);
  assert.equal(res.status, 200, JSON.stringify(res.body));
  assert.equal(res.body.success, true);
  assert.equal('meta' in res.body, false, 'meta only on paginated lists');
  return res.body.data;
}

async function getData(path, auth) {
  const res = await request.get(`${API}${path}`).set(auth);
  assert.equal(res.status, 200, `${path}: ${JSON.stringify(res.body)}`);
  return res.body.data;
}

async function post(path, auth, body) {
  const res = await request.post(`${API}${path}`).set(auth).send(body);
  assert.ok(res.status === 200 || res.status === 201, `${path}: ${res.status} ${JSON.stringify(res.body)}`);
  return res.body.data;
}

function assertError(res, status, code) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.equal(res.body.success, false);
  assert.equal(res.body.error.code, code);
  assert.equal(typeof res.body.error.message, 'string');
  assert.ok(res.body.error.message.length > 0);
  assert.equal('data' in res.body, false);
}

/** Walks every key of a JSON value. */
function eachKey(value, visit, path = '') {
  if (Array.isArray(value)) value.forEach((v, i) => eachKey(v, visit, `${path}[${i}]`));
  else if (value && typeof value === 'object') {
    for (const [k, v] of Object.entries(value)) {
      visit(k, v, `${path}.${k}`);
      eachKey(v, visit, `${path}.${k}`);
    }
  }
}

function assertNoInternalKeys(data) {
  eachKey(data, (key, _v, path) => assert.equal(FORBIDDEN_KEYS.has(key), false, `internal key at ${path}`));
}

/** `YYYY-MM-DD` of `date` in `timeZone` (ledger business dates). */
function localDay(date, timeZone) {
  const p = zonedParts(date, timeZone);
  return `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`;
}

/** Local midnight `days` days away from the day containing `now` (like the app's due dates). */
function localMidnight(days, timeZone = IST, now = new Date()) {
  const p = zonedParts(now, timeZone);
  return zonedTimeToUtc({ year: p.year, month: p.month, day: p.day + days }, timeZone);
}

/** Actor (`req.user` shape) of a helpers.js session, for direct service calls. */
function actorOf(session) {
  return {
    id: session.user.id,
    email: session.user.email,
    name: session.user.name,
    familyId: session.family.id,
    memberId: session.member.id,
    role: session.member.role,
  };
}

let taskSeq = 0;
function seedTask(familyId, assigneeId, fields = {}) {
  taskSeq += 1;
  return Task.create({
    familyId,
    title: `Task ${taskSeq}`,
    assigneeId,
    createdById: assigneeId,
    category: 'chore',
    priority: 'medium',
    status: 'pending',
    ...fields,
  });
}

function seedDone(familyId, assigneeId, completedAt, fields = {}) {
  return seedTask(familyId, assigneeId, { status: 'done', completedAt, completedById: assigneeId, ...fields });
}

function seedEntry(familyId, member, fields = {}) {
  return LedgerEntry.create({
    familyId,
    type: 'expense',
    amountMinor: 10000,
    category: 'groceries',
    date: new Date(),
    memberId: member.id,
    memberName: member.name,
    createdById: member.id,
    ...fields,
  });
}

function seedAlert(familyId, memberId, fields = {}) {
  const startedAt = fields.startedAt ?? new Date();
  return SosAlert.create({
    familyId,
    memberId,
    status: 'active',
    locationShared: true,
    lastLocation: { lat: 28.61, lng: 77.2, accuracy: 10, recordedAt: startedAt },
    trail: [{ lat: 28.61, lng: 77.2, accuracy: 10, recordedAt: startedAt }],
    startedAt,
    expiresAt: new Date(startedAt.getTime() + 15 * 60 * 1000),
    ...fields,
  });
}

/** Admin + joined member + managed child, all in one family (Asia/Kolkata unless overridden). */
async function familyOfThree(familyOverrides) {
  const admin = await registerFamilyAdmin(familyOverrides ? { family: familyOverrides } : {});
  const member = await joinFamilyAs(admin.family.inviteCode);
  const child = await addManagedMember(admin.auth);
  return { admin, member, child, familyId: admin.family.id };
}

// ---------------------------------------------------------------- access

describe('GET /dashboard — access', () => {
  it('401 UNAUTHORIZED without a token or with a malformed one', async () => {
    assertError(await request.get(`${API}/dashboard`), 401, 'UNAUTHORIZED');
    assertError(await request.get(`${API}/dashboard`).set({ Authorization: 'Bearer not-a-jwt' }), 401, 'UNAUTHORIZED');
    assertError(await request.get(`${API}/dashboard`).set({ Authorization: 'Basic abc' }), 401, 'UNAUTHORIZED');
  });

  it('403 NO_FAMILY for a member who was removed from the family', async () => {
    const { admin, member } = await familyOfThree();
    const del = await request.delete(`${API}/family/members/${member.member.id}`).set(admin.auth);
    assert.equal(del.status, 200, JSON.stringify(del.body));
    assertError(await request.get(`${API}/dashboard`).set(member.auth), 403, 'NO_FAMILY');
  });

  it('403 NO_FAMILY for a member who left the family', async () => {
    const { member } = await familyOfThree();
    const left = await request.post(`${API}/me/leave-family`).set(member.auth);
    assert.equal(left.status, 200, JSON.stringify(left.body));
    assertError(await request.get(`${API}/dashboard`).set(member.auth), 403, 'NO_FAMILY');
  });

  it('403 NO_FAMILY when the family document itself is gone (service check)', async () => {
    const admin = await registerFamilyAdmin();
    await Family.deleteOne({ _id: admin.family.id });
    await assert.rejects(getDashboard(actorOf(admin)), (err) => err.code === 'NO_FAMILY' && err.status === 403);
    await assert.rejects(getDashboard({ familyId: null, memberId: null, role: null }), (err) => err.code === 'NO_FAMILY');
    await assert.rejects(getDashboard({ familyId: 'x', memberId: 'y' }), (err) => err.code === 'NO_FAMILY');
  });

  it('only GET is exposed', async () => {
    const admin = await registerFamilyAdmin();
    for (const method of ['post', 'put', 'patch', 'delete']) {
      const res = await request[method](`${API}/dashboard`).set(admin.auth).send({});
      assertError(res, 404, 'NOT_FOUND');
    }
  });

  it('ignores unknown query keys: they neither fail the request nor change the family or month', async () => {
    const a = await registerFamilyAdmin();
    const b = await registerFamilyAdmin({ family: { name: 'Other Family' } });
    const plain = await dashboard(a.auth);
    const tricked = await dashboard(
      a.auth,
      `?familyId=${b.family.id}&memberId=${b.member.id}&month=1999-01&page=-1&limit=abc&_=1700000000&role=admin`,
    );
    assert.equal(tricked.family.id, a.family.id);
    assert.equal(tricked.me.id, a.member.id);
    assert.equal(tricked.monthSummary.month, plain.monthSummary.month);
    assert.deepEqual(tricked, plain);
    // Operator-shaped keys are stripped too.
    const ops = await dashboard(a.auth, '?familyId[$ne]=x&status[$gt]=');
    assert.equal(ops.family.id, a.family.id);
  });
});

// ---------------------------------------------------------------- shape

describe('GET /dashboard — envelope and shape', () => {
  it('a brand-new family: exact keys, zero counters, empty lists, empty month summary', async () => {
    const admin = await registerFamilyAdmin();
    const res = await request.get(`${API}/dashboard`).set(admin.auth);
    assert.equal(res.status, 200);
    assert.match(res.headers['content-type'], /application\/json/);
    assert.match(res.headers['cache-control'], /no-store/);
    assert.match(res.headers['cache-control'], /private/);
    assert.deepEqual(Object.keys(res.body).sort(), ['data', 'success']);

    const data = res.body.data;
    assert.deepEqual(Object.keys(data).sort(), DASHBOARD_KEYS);
    assert.equal(data.family.id, admin.family.id);
    assert.equal(data.family.memberCount, 1);
    assert.equal(data.family.timezone, IST);
    assert.equal(data.me.id, admin.member.id);
    assert.equal(data.me.role, 'admin');
    assert.equal(data.members.length, 1);
    assert.deepEqual(Object.keys(data.members[0]).sort(), STAT_KEYS);
    assert.deepEqual(data.members[0].member, data.me);
    assert.equal(data.members[0].pendingTasks, 0);
    assert.equal(data.members[0].overdueTasks, 0);
    assert.equal(data.members[0].completedThisWeek, 0);
    assert.deepEqual(data.myTasks, []);
    assert.deepEqual(data.goals, []);
    assert.deepEqual(data.latestNotices, []);
    assert.deepEqual(data.activeSos, []);
    assert.deepEqual(data.monthSummary, {
      month: currentMonth(IST),
      currency: 'INR',
      scope: 'family',
      income: 0,
      expense: 0,
      net: 0,
      byCategory: [],
    });
    assertNoInternalKeys(data);
  });

  it('every section equals its dedicated endpoint (shared serializers), for admin and member', async () => {
    const { admin, member, child } = await familyOfThree();
    const today = localDay(new Date(), IST);

    await post('/tasks', admin.auth, { title: 'Maths homework', assigneeId: member.member.id, dueDate: localMidnight(1).toISOString(), category: 'study', priority: 'high' });
    await post('/tasks', admin.auth, { title: 'Water plants', assigneeId: child.id, category: 'chore' });
    await post('/tasks', admin.auth, { title: 'Pay bills', assigneeId: admin.member.id, dueDate: localMidnight(-2).toISOString(), category: 'errand' });
    await post('/tasks', member.auth, { title: 'Guitar practice', assigneeId: member.member.id, category: 'skill' });
    const goal = await post('/goals', admin.auth, { title: 'Goa vacation', targetAmount: 60000 });
    await post(`/goals/${goal.id}/contributions`, member.auth, { amount: 12500 });
    await post('/ledger/entries', admin.auth, { type: 'income', amount: 85000, category: 'salary', date: today });
    await post('/ledger/entries', member.auth, { type: 'expense', amount: 1250.5, category: 'groceries', date: today });
    await post('/notices', member.auth, { title: 'Dinner at 8', body: 'Grandma is visiting' });
    await post('/notices', admin.auth, { title: 'House rules', body: 'Shoes off', pinned: true });
    await post('/sos', member.auth, { message: 'Flat tyre on the highway' });

    for (const session of [admin, member]) {
      const data = await dashboard(session.auth);
      const isAdminCaller = session === admin;

      const { family } = await getData('/family', session.auth);
      assert.deepEqual(data.family, family);
      const members = await getData('/family/members', session.auth);
      assert.deepEqual(
        data.members.map((m) => m.member),
        members,
        'members in contract order, serialized like GET /family/members',
      );
      assert.deepEqual(data.me, members.find((m) => m.id === session.member.id));

      const myTasks = await getData(`/tasks?assigneeId=${session.member.id}&status=pending&limit=5`, session.auth);
      assert.deepEqual(data.myTasks, myTasks);
      assert.ok(data.myTasks.length > 0);
      assert.ok(data.myTasks.every((t) => t.assigneeId === session.member.id && t.status === 'pending'));

      const goals = await getData('/goals?status=active', session.auth);
      assert.deepEqual(data.goals, goals.slice(0, 3));
      assert.equal(data.goals[0].savedAmount, 12500);
      assert.equal(data.goals[0].progress, 0.2083);

      const notices = await getData('/notices?limit=3', session.auth);
      assert.deepEqual(data.latestNotices, notices);
      assert.equal(data.latestNotices[0].title, 'House rules', 'pinned first');

      const activeSos = await getData('/sos/active', session.auth);
      assert.deepEqual(data.activeSos, activeSos);
      assert.equal(data.activeSos.length, 1);
      assert.equal(data.activeSos[0].memberId, member.member.id);
      assert.deepEqual(data.activeSos[0].trail, []);

      const summary = await getData('/ledger/summary', session.auth);
      assert.deepEqual(data.monthSummary, summary);
      assert.equal(data.monthSummary.scope, isAdminCaller ? 'family' : 'personal');

      assertNoInternalKeys(data);
    }
  });

  it('every id is an ObjectId hex string and every timestamp ISO-8601 UTC', async () => {
    const { admin, member, familyId } = await familyOfThree();
    await seedTask(familyId, admin.member.id, { dueDate: localMidnight(3) });
    await seedAlert(familyId, member.member.id);
    const data = await dashboard(admin.auth);
    eachKey(data, (key, value, path) => {
      if ((key === 'id' || key.endsWith('Id')) && value !== null) assert.match(value, OBJECT_ID, path);
      if ((key.endsWith('At') || key === 'dueDate' || key === 'dateOfBirth') && value !== null) {
        assert.match(value, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/, path);
      }
    });
  });
});

// ---------------------------------------------------------------- permission matrix

describe('GET /dashboard — roles and family isolation', () => {
  it('admin: inviteCode and the family-wide month summary', async () => {
    const { admin, member, child, familyId } = await familyOfThree();
    await seedEntry(familyId, admin.member, { type: 'income', category: 'salary', amountMinor: 5000000 });
    await seedEntry(familyId, member.member, { amountMinor: 12050 });
    await seedEntry(familyId, child, { amountMinor: 2500, category: 'education' });

    const data = await dashboard(admin.auth);
    assert.match(data.family.inviteCode, /^[A-Z2-9]{8}$/);
    assert.equal(data.family.inviteCode, admin.family.inviteCode);
    assert.equal(data.monthSummary.scope, 'family');
    assert.equal(data.monthSummary.income, 50000);
    assert.equal(data.monthSummary.expense, 145.5);
    assert.equal(data.monthSummary.net, 49854.5);
    assert.deepEqual(data.monthSummary.byCategory, [
      { type: 'income', category: 'salary', amount: 50000 },
      { type: 'expense', category: 'groceries', amount: 120.5 },
      { type: 'expense', category: 'education', amount: 25 },
    ]);
  });

  it('member: no inviteCode and a personal month summary (entries whose memberId is theirs)', async () => {
    const { admin, member, familyId } = await familyOfThree();
    await seedEntry(familyId, admin.member, { type: 'income', category: 'salary', amountMinor: 5000000 });
    await seedEntry(familyId, member.member, { amountMinor: 12050 });
    // Recorded by the admin *for* the member → the member's money.
    await seedEntry(familyId, member.member, {
      type: 'income',
      category: 'allowance',
      amountMinor: 50000,
      createdById: admin.member.id,
    });
    // Created by the member but owned by the admin → not personal.
    await seedEntry(familyId, admin.member, { amountMinor: 99900, createdById: member.member.id });

    const data = await dashboard(member.auth);
    assert.equal(data.family.inviteCode, null);
    assert.equal(data.me.role, 'member');
    assert.equal(data.monthSummary.scope, 'personal');
    assert.equal(data.monthSummary.income, 500);
    assert.equal(data.monthSummary.expense, 120.5);
    assert.equal(data.monthSummary.net, 379.5);
    assert.equal(data.monthSummary.currency, 'INR');
  });

  it('admin-only data follows the stored role, not a stale token-time role (demotion race)', async () => {
    const { admin, member } = await familyOfThree();
    // requireAuth saw "admin", then the member was demoted before the dashboard read its data.
    const staleActor = { ...actorOf(member), role: 'admin' };
    const data = await getDashboard(staleActor);
    assert.equal(data.me.role, 'member');
    assert.equal(data.family.inviteCode, null);
    assert.equal(data.monthSummary.scope, 'personal');
    // And the other way round: a freshly promoted member gets the admin view at once.
    await Member.updateOne({ _id: member.member.id }, { $set: { role: 'admin' } });
    const promoted = await getDashboard({ ...actorOf(member), role: 'member' });
    assert.equal(promoted.family.inviteCode, admin.family.inviteCode);
    assert.equal(promoted.monthSummary.scope, 'family');
  });

  it('member and admin see the same members, counters, goals, notices and SOS', async () => {
    const { admin, member, child, familyId } = await familyOfThree();
    await seedTask(familyId, child.id, { dueDate: localMidnight(-1) });
    await seedTask(familyId, member.member.id);
    await Goal.create({ familyId, title: 'Bike', targetMinor: 100000, createdById: admin.member.id });
    await Notice.create({ familyId, title: 'Hi', body: 'All', authorId: admin.member.id });
    await seedAlert(familyId, child.id);

    const asAdmin = await dashboard(admin.auth);
    const asMember = await dashboard(member.auth);
    for (const key of ['members', 'goals', 'latestNotices', 'activeSos']) {
      assert.deepEqual(asMember[key], asAdmin[key], key);
    }
    assert.equal(asMember.members.length, 3);
    assert.equal(asMember.family.memberCount, 3);
  });

  it("another family's data never appears (members, tasks, goals, notices, SOS, money)", async () => {
    const a = await familyOfThree();
    const b = await familyOfThree({ name: 'Other Family', timezone: 'Europe/Berlin', country: 'DE', currency: 'EUR' });
    await seedTask(a.familyId, a.member.member.id, { dueDate: localMidnight(-1) });
    await seedDone(a.familyId, a.member.member.id, new Date());
    await Goal.create({ familyId: a.familyId, title: 'A goal', targetMinor: 1000, createdById: a.admin.member.id });
    await Notice.create({ familyId: a.familyId, title: 'A notice', body: 'x', pinned: true, authorId: a.admin.member.id });
    await seedAlert(a.familyId, a.member.member.id);
    await seedEntry(a.familyId, a.admin.member, { type: 'income', category: 'salary', amountMinor: 700000 });
    await seedTask(b.familyId, b.admin.member.id);

    const aIds = [a.familyId, a.admin.member.id, a.member.member.id, a.child.id, a.admin.family.inviteCode];
    for (const session of [b.admin, b.member]) {
      const data = await dashboard(session.auth);
      assert.equal(data.family.id, b.familyId);
      assert.equal(data.family.currency, 'EUR');
      assert.equal(data.members.length, 3);
      assert.deepEqual(data.goals, []);
      assert.deepEqual(data.latestNotices, []);
      assert.deepEqual(data.activeSos, []);
      assert.equal(data.monthSummary.income, 0);
      assert.equal(data.monthSummary.currency, 'EUR');
      const json = JSON.stringify(data);
      for (const id of aIds) assert.equal(json.includes(id), false, `leaked ${id}`);
      const counts = data.members.reduce((n, m) => n + m.pendingTasks + m.completedThisWeek, 0);
      assert.equal(counts, 1, 'only family B task counted');
    }
  });
});

// ---------------------------------------------------------------- counters

describe('GET /dashboard — member task counters', () => {
  it('pending / overdue / completedThisWeek per assignee in the family time zone', async () => {
    const { admin, member, child, familyId } = await familyOfThree();
    const now = new Date();
    const m = member.member.id;
    await seedTask(familyId, m); // no due date: pending, never overdue
    await seedTask(familyId, m, { dueDate: localMidnight(0, IST, now) }); // due today: not overdue yet
    await seedTask(familyId, m, { dueDate: localMidnight(1, IST, now) }); // tomorrow
    await seedTask(familyId, m, { dueDate: localMidnight(-1, IST, now) }); // yesterday: overdue
    await seedTask(familyId, m, { dueDate: localMidnight(-10, IST, now), createdById: admin.member.id }); // overdue
    await seedDone(familyId, m, now); // this week
    await seedDone(familyId, m, startOfWeek(now, IST)); // Monday 00:00 local: this week
    await seedDone(familyId, m, new Date(startOfWeek(now, IST).getTime() - 1)); // last week
    await seedDone(familyId, m, new Date(now.getTime() - 30 * DAY_MS)); // long ago
    // Done tasks never count as pending / overdue, even with a past due date.
    await seedDone(familyId, m, new Date(now.getTime() - 60 * DAY_MS), { dueDate: localMidnight(-70, IST, now) });
    await seedTask(familyId, child.id, { dueDate: localMidnight(-3, IST, now), createdById: admin.member.id });
    // A task whose assignee left the family is ignored (no row, no crash).
    await seedTask(familyId, newId(), { createdById: admin.member.id });

    const data = await dashboard(admin.auth);
    const byId = Object.fromEntries(data.members.map((row) => [row.member.id, row]));
    assert.equal(data.members.length, 3);
    const { member: _m, ...memberStats } = byId[m];
    assert.deepEqual(memberStats, { pendingTasks: 5, overdueTasks: 2, completedThisWeek: 2 });
    const { member: _c, ...childStats } = byId[child.id];
    assert.deepEqual(childStats, { pendingTasks: 1, overdueTasks: 1, completedThisWeek: 0 });
    const { member: _a, ...adminStats } = byId[admin.member.id];
    assert.deepEqual(adminStats, { pendingTasks: 0, overdueTasks: 0, completedThisWeek: 0 });

    // Same definitions as the task list filters.
    const overdue = await request.get(`${API}/tasks?assigneeId=${m}&status=pending&due=overdue`).set(admin.auth);
    assert.equal(overdue.body.meta.total, byId[m].overdueTasks);
    const pending = await request.get(`${API}/tasks?assigneeId=${m}&status=pending`).set(admin.auth);
    assert.equal(pending.body.meta.total, byId[m].pendingTasks);
  });

  it('counters follow task transitions made through the API', async () => {
    const { admin, member } = await familyOfThree();
    const task = await post('/tasks', admin.auth, {
      title: 'Clean room',
      assigneeId: member.member.id,
      dueDate: localMidnight(-1).toISOString(),
      category: 'chore',
    });
    const statsOf = async () => (await dashboard(member.auth)).members.find((r) => r.member.id === member.member.id);

    let stats = await statsOf();
    assert.deepEqual([stats.pendingTasks, stats.overdueTasks, stats.completedThisWeek], [1, 1, 0]);

    await post(`/tasks/${task.id}/complete`, member.auth, {});
    stats = await statsOf();
    assert.deepEqual([stats.pendingTasks, stats.overdueTasks, stats.completedThisWeek], [0, 0, 1]);

    await post(`/tasks/${task.id}/reopen`, member.auth, {});
    stats = await statsOf();
    assert.deepEqual([stats.pendingTasks, stats.overdueTasks, stats.completedThisWeek], [1, 1, 0]);

    // An admin completing on the assignee's behalf still counts for the assignee.
    await post(`/tasks/${task.id}/complete`, admin.auth, {});
    stats = await statsOf();
    assert.equal(stats.completedThisWeek, 1);
    const adminRow = (await dashboard(admin.auth)).members.find((r) => r.member.id === admin.member.id);
    assert.equal(adminRow.completedThisWeek, 0);
  });

  it('memberTaskStats is defensive for callers outside HTTP validation', async () => {
    assert.equal((await memberTaskStats(null)).size, 0);
    assert.equal((await memberTaskStats('not-an-id')).size, 0);
    assert.equal((await memberTaskStats(String(newId()))).size, 0);
    assert.equal((await memberTaskStats({ $ne: null })).size, 0);
    // An invalid zone → UTC, an invalid clock → server time (no RangeError).
    const admin = await registerFamilyAdmin();
    await seedTask(admin.family.id, admin.member.id);
    const stats = await memberTaskStats(admin.family.id, { timeZone: 'Mars/Olympus_Mons', now: new Date('garbage') });
    assert.deepEqual(stats.get(admin.member.id), { pendingTasks: 1, overdueTasks: 0, completedThisWeek: 0 });
  });
});

// ---------------------------------------------------------------- time zones (fixed clock)

describe('GET /dashboard — day / week / month boundaries (fixed clock)', () => {
  it('Asia/Kolkata: Monday 1 June 00:30 local is still Sunday 31 May in UTC', async () => {
    const admin = await registerFamilyAdmin();
    const familyId = admin.family.id;
    const me = admin.member.id;
    const now = new Date('2026-05-31T19:00:00.000Z'); // Mon 2026-06-01 00:30 IST
    const localMonday = new Date('2026-05-31T18:30:00.000Z'); // Mon 2026-06-01 00:00 IST
    assert.equal(startOfDay(now, IST).getTime(), localMonday.getTime());
    assert.equal(startOfWeek(now, IST).getTime(), localMonday.getTime());

    await seedTask(familyId, me, { dueDate: new Date('2026-05-31T12:00:00.000Z') }); // Sun 17:30 IST → overdue
    await seedTask(familyId, me, { dueDate: localMonday }); // due today → not overdue
    await seedDone(familyId, me, new Date('2026-05-31T18:29:59.999Z')); // Sun 23:59:59.999 IST → last week
    await seedDone(familyId, me, localMonday); // Mon 00:00 IST → this week
    await seedEntry(familyId, admin.member, { type: 'income', category: 'salary', amountMinor: 100000, date: localMonday }); // 1 June
    await seedEntry(familyId, admin.member, { amountMinor: 5000, date: new Date('2026-05-30T18:30:00.000Z') }); // 31 May

    const data = await getDashboard(actorOf(admin), { now });
    const row = data.members[0];
    assert.deepEqual([row.pendingTasks, row.overdueTasks, row.completedThisWeek], [2, 1, 1]);
    assert.equal(data.monthSummary.month, '2026-06');
    assert.equal(data.monthSummary.income, 1000);
    assert.equal(data.monthSummary.expense, 0);
    assert.equal(data.myTasks.length, 2);
    assert.equal(data.myTasks[0].dueDate, '2026-05-31T12:00:00.000Z');
  });

  it('America/Los_Angeles: Sunday 31 May 23:30 local is already Monday 1 June in UTC', async () => {
    const admin = await registerFamilyAdmin({
      family: { timezone: 'America/Los_Angeles', country: 'US', currency: 'USD' },
    });
    const familyId = admin.family.id;
    const me = admin.member.id;
    const now = new Date('2026-06-01T06:30:00.000Z'); // Sun 2026-05-31 23:30 PDT
    const localWeekStart = new Date('2026-05-25T07:00:00.000Z'); // Mon 2026-05-25 00:00 PDT
    assert.equal(startOfWeek(now, 'America/Los_Angeles').getTime(), localWeekStart.getTime());

    await seedDone(familyId, me, new Date('2026-05-26T12:00:00.000Z')); // Tue this (local) week
    await seedDone(familyId, me, new Date('2026-05-25T06:59:59.999Z')); // Sun 24 May 23:59 PDT → last week
    await seedTask(familyId, me, { dueDate: new Date('2026-05-31T07:00:00.000Z') }); // due today (31 May) → not overdue
    await seedTask(familyId, me, { dueDate: new Date('2026-05-31T06:59:59.000Z') }); // 30 May → overdue
    await seedEntry(familyId, admin.member, { amountMinor: 4200, date: new Date('2026-05-31T07:00:00.000Z') }); // 31 May
    await seedEntry(familyId, admin.member, { amountMinor: 9900, date: new Date('2026-06-01T07:00:00.000Z') }); // 1 June

    const data = await getDashboard(actorOf(admin), { now });
    const row = data.members[0];
    assert.deepEqual([row.pendingTasks, row.overdueTasks, row.completedThisWeek], [2, 1, 1]);
    assert.equal(data.monthSummary.month, '2026-05');
    assert.equal(data.monthSummary.currency, 'USD');
    assert.equal(data.monthSummary.expense, 42);
  });

  it('an invalid stored time zone falls back to UTC instead of failing', async () => {
    const admin = await registerFamilyAdmin();
    await Family.collection.updateOne(
      { _id: new mongoose.Types.ObjectId(admin.family.id) },
      { $set: { timezone: 'Mars/Olympus_Mons' } },
    );
    const now = new Date('2026-05-31T19:00:00.000Z'); // Sunday in UTC
    await seedDone(admin.family.id, admin.member.id, new Date('2026-05-25T00:00:00.000Z')); // Mon UTC → this week
    const data = await getDashboard(actorOf(admin), { now });
    assert.equal(data.monthSummary.month, '2026-05');
    assert.equal(data.members[0].completedThisWeek, 1);
    const http = await dashboard(admin.auth);
    assert.equal(http.monthSummary.month, currentMonth('UTC'));
  });
});

// ---------------------------------------------------------------- lists

describe('GET /dashboard — myTasks, goals, latestNotices', () => {
  it('myTasks: only the caller\'s pending tasks, dueDate asc, no due date last, max 5', async () => {
    const { admin, member, familyId } = await familyOfThree();
    const me = member.member.id;
    const noDueOld = await seedTask(familyId, me, { title: 'no due (older)' });
    const in5 = await seedTask(familyId, me, { title: 'in 5 days', dueDate: localMidnight(5) });
    const past = await seedTask(familyId, me, { title: 'overdue', dueDate: localMidnight(-4) });
    const today = await seedTask(familyId, me, { title: 'today', dueDate: localMidnight(0) });
    await seedTask(familyId, me, { title: 'no due (newer)' });
    const tomorrow = await seedTask(familyId, me, { title: 'tomorrow', dueDate: localMidnight(1) });
    await seedDone(familyId, me, new Date(), { title: 'done', dueDate: localMidnight(-9) });
    await seedTask(familyId, admin.member.id, { title: "admin's", dueDate: localMidnight(-9) });

    const data = await dashboard(member.auth);
    assert.deepEqual(
      data.myTasks.map((t) => t.id),
      [past, today, tomorrow, in5, noDueOld].map((t) => String(t._id)),
    );
    assert.ok(data.myTasks.every((t) => t.assigneeName === member.member.name));
    assert.equal(data.members.find((r) => r.member.id === me).pendingTasks, 6, 'counter is not capped');

    const adminView = await dashboard(admin.auth);
    assert.deepEqual(adminView.myTasks.map((t) => t.title), ["admin's"]);
  });

  it('myTasks keep assigneeName / createdByName null for a creator who left', async () => {
    const { admin, member, familyId } = await familyOfThree();
    await seedTask(familyId, admin.member.id, { createdById: member.member.id });
    await request.delete(`${API}/family/members/${member.member.id}`).set(admin.auth).expect(200);
    const data = await dashboard(admin.auth);
    assert.equal(data.myTasks.length, 1);
    assert.equal(data.myTasks[0].createdById, member.member.id);
    assert.equal(data.myTasks[0].createdByName, null);
    assert.equal(data.myTasks[0].assigneeName, admin.member.name);
    assert.equal(data.members.length, 2);
  });

  it('goals: active only, newest first, max 3', async () => {
    const admin = await registerFamilyAdmin();
    const familyId = admin.family.id;
    const base = Date.now() - 10 * DAY_MS;
    const mk = (title, status, i) =>
      Goal.create({ familyId, title, targetMinor: 100000, savedMinor: 25000, status, createdById: admin.member.id, createdAt: new Date(base + i * DAY_MS) });
    await mk('oldest active', 'active', 0);
    await mk('achieved', 'achieved', 1);
    await mk('active 2', 'active', 2);
    await mk('archived', 'archived', 3);
    await mk('active 3', 'active', 4);
    await mk('newest active', 'active', 5);

    const data = await dashboard(admin.auth);
    assert.deepEqual(data.goals.map((g) => g.title), ['newest active', 'active 3', 'active 2']);
    assert.ok(data.goals.every((g) => g.status === 'active' && g.progress === 0.25 && g.targetAmount === 1000));
  });

  it('latestNotices: max 3, pinned first then newest first, author who left → null name', async () => {
    const { admin, member, familyId } = await familyOfThree();
    const base = Date.now() - 10 * DAY_MS;
    const mk = (title, pinned, i, authorId = admin.member.id) =>
      Notice.create({ familyId, title, body: 'b', pinned, authorId, createdAt: new Date(base + i * DAY_MS) });
    await mk('old pinned', true, 0, member.member.id);
    await mk('old', false, 1);
    await mk('middle', false, 2);
    await mk('newest', false, 4);
    await mk('newer', false, 3);
    await request.delete(`${API}/family/members/${member.member.id}`).set(admin.auth).expect(200);

    const data = await dashboard(admin.auth);
    assert.deepEqual(data.latestNotices.map((n) => n.title), ['old pinned', 'newest', 'newer']);
    assert.equal(data.latestNotices[0].authorName, null);
    assert.equal(data.latestNotices[0].authorAvatarUrl, null);
    assert.equal(data.latestNotices[1].authorName, admin.member.name);
  });
});

// ---------------------------------------------------------------- SOS

describe('GET /dashboard — activeSos', () => {
  it('lists only active alerts (newest first) and persists the lazy expiry first', async () => {
    const { admin, member, child, familyId } = await familyOfThree();
    const now = Date.now();
    const older = await seedAlert(familyId, child.id, { startedAt: new Date(now - 5 * 60 * 1000) });
    const newer = await seedAlert(familyId, member.member.id, { startedAt: new Date(now - 60 * 1000) });
    const stale = await seedAlert(familyId, admin.member.id, { startedAt: new Date(now - 20 * 60 * 1000) }); // past expiresAt
    await seedAlert(familyId, admin.member.id, {
      status: 'resolved',
      resolvedAt: new Date(),
      resolvedById: admin.member.id,
      resolution: 'safe',
    });

    const data = await dashboard(member.auth);
    assert.deepEqual(data.activeSos.map((a) => a.id), [String(newer._id), String(older._id)]);
    assert.ok(data.activeSos.every((a) => a.status === 'active' && Array.isArray(a.trail) && a.trail.length === 0));
    assert.equal((await SosAlert.findById(stale._id).lean()).status, 'expired', 'lazy expiry persisted');
  });

  it('SOS locations follow the owner\'s current sharing mode', async () => {
    const { admin, member, child, familyId } = await familyOfThree();
    await Member.updateOne({ _id: member.member.id }, { $set: { locationSharing: 'sos_only' } });
    await Member.updateOne({ _id: child.id }, { $set: { locationSharing: 'never' } });
    await seedAlert(familyId, member.member.id);
    await seedAlert(familyId, child.id);

    const data = await dashboard(admin.auth);
    const byOwner = Object.fromEntries(data.activeSos.map((a) => [a.memberId, a]));
    assert.equal(byOwner[member.member.id].locationShared, true);
    assert.equal(byOwner[member.member.id].lastLocation.lat, 28.61);
    assert.equal(byOwner[child.id].locationShared, false, 'consent withdrawn → hidden');
    assert.equal(byOwner[child.id].lastLocation, null);
    assert.equal(byOwner[member.member.id].memberName, member.member.name);
  });
});

// ---------------------------------------------------------------- privacy

describe('GET /dashboard — privacy', () => {
  it('lastLocation of members only when they share `always`, in `me` and in `members`', async () => {
    const { admin, member, child } = await familyOfThree();
    const point = { lat: 12.97, lng: 77.59, accuracy: 8, recordedAt: new Date() };
    await Member.updateOne({ _id: member.member.id }, { $set: { locationSharing: 'always', lastLocation: point } });
    await Member.updateOne({ _id: child.id }, { $set: { locationSharing: 'sos_only', lastLocation: point } });
    await Member.updateOne({ _id: admin.member.id }, { $set: { locationSharing: 'never', lastLocation: point } });

    const data = await dashboard(member.auth);
    const byId = Object.fromEntries(data.members.map((r) => [r.member.id, r.member]));
    assert.equal(byId[member.member.id].lastLocation.lat, 12.97);
    assert.equal(data.me.lastLocation.lat, 12.97);
    assert.equal(byId[child.id].lastLocation, null);
    assert.equal(byId[admin.member.id].lastLocation, null);
  });

  it('never exposes secrets or internal fields', async () => {
    const { admin, member, familyId } = await familyOfThree();
    await seedTask(familyId, member.member.id);
    await seedAlert(familyId, member.member.id);
    await Goal.create({ familyId, title: 'G', targetMinor: 1000, savedMinor: 10, createdById: admin.member.id });
    for (const session of [admin, member]) {
      const data = await dashboard(session.auth);
      assertNoInternalKeys(data);
      const json = JSON.stringify(data);
      assert.equal(json.includes(session.password), false);
      assert.equal(json.includes(session.tokens.refreshToken), false);
    }
  });
});

// ---------------------------------------------------------------- efficiency

describe('GET /dashboard — query budget', () => {
  const ops = [];
  const logger = (collection, method) => ops.push(`${collection}.${method}`);

  afterEach(() => {
    mongoose.set('debug', false);
    ops.length = 0;
  });

  it('one aggregation for every member counter, independent of the family size', async () => {
    const admin = await registerFamilyAdmin();
    const familyId = admin.family.id;
    for (let i = 0; i < 6; i += 1) {
      const kid = await addManagedMember(admin.auth, { name: `Kid ${i}` });
      await seedTask(familyId, kid.id, { dueDate: localMidnight(-1) });
      await seedDone(familyId, kid.id, new Date());
    }
    mongoose.set('debug', logger);
    const data = await dashboard(admin.auth);
    mongoose.set('debug', false);

    assert.equal(data.members.length, 7);
    assert.ok(data.members.filter((r) => r.member.role === 'member').every((r) => r.overdueTasks === 1 && r.completedThisWeek === 1));
    const count = (op) => ops.filter((o) => o === op).length;
    assert.deepEqual(
      ops.filter((op) => op.startsWith('tasks.')),
      ['tasks.aggregate', 'tasks.aggregate'],
      'counters (one aggregation for all members) + myTasks',
    );
    assert.equal(count('members.find'), 1, 'one member map for names, counters and serialization');
    assert.equal(count('families.findOne'), 1);
    assert.equal(count('ledger_entries.aggregate'), 1, 'month summary');
    // Today: requireAuth (user + member) + 9 dashboard reads. Grows with nothing but new sections.
    assert.ok(ops.length <= 12, `too many queries: ${ops.join(', ')}`);
  });

  it('the query count does not grow with the family size or the amount of data', async () => {
    const small = await registerFamilyAdmin();
    mongoose.set('debug', logger);
    await dashboard(small.auth);
    mongoose.set('debug', false);
    const baseline = ops.length;
    ops.length = 0;

    const big = await registerFamilyAdmin({ family: { name: 'Big Family' } });
    const familyId = big.family.id;
    for (let i = 0; i < 8; i += 1) {
      const kid = await addManagedMember(big.auth, { name: `Kid ${i}` });
      await seedTask(familyId, kid.id);
      await seedTask(familyId, big.member.id, { createdById: kid.id });
      await Notice.create({ familyId, title: `N${i}`, body: 'b', authorId: kid.id });
      await Goal.create({ familyId, title: `G${i}`, targetMinor: 1000, createdById: big.member.id });
      await seedAlert(familyId, kid.id);
      await seedEntry(familyId, { id: kid.id, name: `Kid ${i}` });
    }
    mongoose.set('debug', logger);
    const data = await dashboard(big.auth);
    mongoose.set('debug', false);
    assert.equal(data.members.length, 9);
    assert.equal(data.myTasks.length, 5);
    assert.equal(data.activeSos.length, 8);
    assert.equal(ops.length, baseline, ops.join(', '));
  });
});

// ================================================================ hardening (b-dashboard-harden)

/** Contract §2 / §7 / §8 / §9 / §10 / §11 key sets — the dashboard must not add, drop or rename a field. */
const CONTRACT_KEYS = Object.freeze({
  family: ['country', 'createdAt', 'currency', 'id', 'inviteCode', 'memberCount', 'name', 'ownerId', 'timezone'],
  member: [
    'avatarUrl', 'createdAt', 'dateOfBirth', 'designation', 'email', 'familyId', 'gender', 'guardianConsent',
    'hasAccount', 'id', 'lastLocation', 'locationSharing', 'name', 'phone', 'role', 'updatedAt', 'userId',
  ],
  task: [
    'assigneeId', 'assigneeName', 'category', 'completedAt', 'completedById', 'createdAt', 'createdById',
    'createdByName', 'description', 'dueDate', 'id', 'priority', 'status', 'title', 'updatedAt',
  ],
  goal: [
    'createdAt', 'createdById', 'description', 'id', 'progress', 'savedAmount', 'status', 'targetAmount',
    'targetDate', 'title', 'updatedAt',
  ],
  notice: ['authorAvatarUrl', 'authorId', 'authorName', 'body', 'createdAt', 'id', 'imageUrl', 'pinned', 'title', 'updatedAt'],
  sos: [
    'expiresAt', 'id', 'lastLocation', 'locationShared', 'memberAvatarUrl', 'memberId', 'memberName', 'memberPhone',
    'message', 'resolution', 'resolvedAt', 'resolvedById', 'startedAt', 'status', 'trail',
  ],
  location: ['accuracy', 'lat', 'lng', 'recordedAt'],
  summary: ['byCategory', 'currency', 'expense', 'income', 'month', 'net', 'scope'],
  byCategory: ['amount', 'category', 'type'],
});

const keysOf = (value) => Object.keys(value).sort();

/** Access token signed like services/tokens.js, with overridable claims / options. */
function signAccess(subject, { secret = env.JWT_ACCESS_SECRET, claims = {}, ...opts } = {}) {
  return jwt.sign(claims, secret, { algorithm: 'HS256', issuer: JWT_ISSUER, audience: JWT_AUDIENCE, subject, ...opts });
}

const bearer = (token) => ({ Authorization: `Bearer ${token}` });

describe('GET /dashboard — hardening: tokens, methods and request shapes', () => {
  it('401 TOKEN_EXPIRED for an expired token; 401 UNAUTHORIZED for a forged, unsigned, foreign or orphaned one', async () => {
    const admin = await registerFamilyAdmin();
    const expired = signAccess(admin.user.id, { claims: { exp: Math.floor(Date.now() / 1000) - 60 } });
    assertError(await request.get(`${API}/dashboard`).set(bearer(expired)), 401, 'TOKEN_EXPIRED');

    const forged = signAccess(admin.user.id, { secret: 'x'.repeat(64) });
    const unsigned = jwt.sign({ sub: admin.user.id }, null, { algorithm: 'none' });
    const otherAudience = signAccess(admin.user.id, { audience: 'someone-else' });
    const notAnId = signAccess('{"$ne":null}');
    for (const token of [forged, unsigned, otherAudience, notAnId]) {
      assertError(await request.get(`${API}/dashboard`).set(bearer(token)), 401, 'UNAUTHORIZED');
    }

    // A still-valid token of a user deleted meanwhile.
    const valid = signAccess(admin.user.id);
    await dashboard(bearer(valid));
    await User.deleteOne({ _id: admin.user.id });
    assertError(await request.get(`${API}/dashboard`).set(bearer(valid)), 401, 'UNAUTHORIZED');
  });

  it('HEAD sends the headers only; a trailing slash works; sub-paths are 404 NOT_FOUND', async () => {
    const admin = await registerFamilyAdmin();
    const head = await request.head(`${API}/dashboard`).set(admin.auth);
    assert.equal(head.status, 200);
    assert.match(head.headers['cache-control'], /no-store/);
    assert.equal(head.text ?? '', '');

    const slash = await request.get(`${API}/dashboard/`).set(admin.auth);
    assert.equal(slash.status, 200);
    assert.equal(slash.body.data.family.id, admin.family.id);

    for (const path of ['/dashboard/x', `/dashboard/${admin.family.id}`, '/dashboard/..%2Ffamily', '/dashboard/%00']) {
      assertError(await request.get(`${API}${path}`).set(admin.auth), 404, 'NOT_FOUND');
    }
  });

  it('a GET body is ignored: operators and mass-assignment fields change neither scope, role nor data', async () => {
    const { admin, member } = await familyOfThree();
    const plain = await dashboard(member.auth);
    const res = await request
      .get(`${API}/dashboard`)
      .set(member.auth)
      .send({
        familyId: { $ne: null },
        memberId: admin.member.id,
        role: 'admin',
        me: { role: 'admin' },
        $where: 'sleep(1000)',
        savedMinor: 1e15,
      });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.deepEqual(res.body.data, plain);
    assert.equal(res.body.data.family.inviteCode, null);
    assert.equal(res.body.data.monthSummary.scope, 'personal');
    assert.equal((await Member.findById(member.member.id).lean()).role, 'member', 'nothing written');
  });

  it('a malformed or oversized body is a clean 4xx error envelope, never a 500', async () => {
    const admin = await registerFamilyAdmin();
    const malformed = await request
      .get(`${API}/dashboard`)
      .set(admin.auth)
      .set('Content-Type', 'application/json')
      .send('{"familyId":');
    assertError(malformed, 400, 'BAD_REQUEST');

    const huge = await request
      .get(`${API}/dashboard`)
      .set(admin.auth)
      .set('Content-Type', 'application/json')
      .send(JSON.stringify({ x: 'a'.repeat(200_000) }));
    assert.equal(huge.status, 413);
    assert.equal(huge.body.success, false);
    assert.equal(typeof huge.body.error.code, 'string');
    assert.equal(typeof huge.body.error.message, 'string');
  });

  it('prototype-pollution and repeated query keys are ignored and pollute nothing', async () => {
    const { member } = await familyOfThree();
    const plain = await dashboard(member.auth);
    const data = await dashboard(
      member.auth,
      '?__proto__[role]=admin&constructor[prototype][role]=admin&role=admin&role=member&familyId=&familyId[]=x',
    );
    assert.deepEqual(data, plain);
    assert.equal(data.family.inviteCode, null);
    assert.equal({}.role, undefined);
    assert.equal(Object.prototype.role, undefined);
  });

  it('service: a forged actor (member of another family, operator-shaped ids, bad clock) never crosses families', async () => {
    const a = await registerFamilyAdmin();
    const b = await registerFamilyAdmin({ family: { name: 'Other Family' } });
    const noFamily = (err) => err.status === 403 && err.code === 'NO_FAMILY';
    await assert.rejects(getDashboard({ ...actorOf(a), memberId: b.member.id }), noFamily);
    await assert.rejects(getDashboard({ ...actorOf(a), familyId: b.family.id }), noFamily);
    await assert.rejects(getDashboard({ ...actorOf(a), familyId: { $ne: null } }), noFamily);
    await assert.rejects(getDashboard({ ...actorOf(a), memberId: { $gt: '' } }), noFamily);
    await assert.rejects(getDashboard(undefined), noFamily);

    // An unusable injected clock falls back to the server time (no RangeError → 500).
    for (const now of [new Date('garbage'), 'yesterday', 0]) {
      const data = await getDashboard(actorOf(a), { now });
      assert.equal(data.monthSummary.month, currentMonth(IST));
    }
  });
});

describe('GET /dashboard — hardening: contract conformance and text', () => {
  it('every nested object has exactly the contract keys and value types (admin and member)', async () => {
    const { admin, member, child } = await familyOfThree();
    const point = { lat: 12.97, lng: 77.59, accuracy: 8, recordedAt: new Date() };
    await Member.updateOne({ _id: member.member.id }, { $set: { locationSharing: 'always', lastLocation: point } });
    for (const session of [admin, member]) {
      await post('/tasks', session.auth, { title: 'Own task', assigneeId: session.member.id, category: 'chore' });
    }
    await post('/tasks', admin.auth, { title: 'Kid task', assigneeId: child.id, dueDate: localMidnight(-1).toISOString(), category: 'study' });
    const goal = await post('/goals', admin.auth, { title: 'Bike', targetAmount: 300, targetDate: localMidnight(90).toISOString() });
    await post(`/goals/${goal.id}/contributions`, member.auth, { amount: 100 });
    await post('/ledger/entries', admin.auth, { type: 'income', amount: 500, category: 'salary', date: localDay(new Date(), IST) });
    await post('/notices', admin.auth, { title: 'Notice', body: 'Body', pinned: true });
    await post('/sos', member.auth, { message: 'Help', location: { lat: 12.9, lng: 77.5, accuracy: 5 } });

    for (const session of [admin, member]) {
      const data = await dashboard(session.auth);
      assert.deepEqual(keysOf(data.family), CONTRACT_KEYS.family);
      assert.equal(Number.isInteger(data.family.memberCount), true);
      for (const m of [data.me, ...data.members.map((row) => row.member)]) {
        assert.deepEqual(keysOf(m), CONTRACT_KEYS.member);
        assert.equal(typeof m.hasAccount, 'boolean');
        assert.equal(typeof m.guardianConsent, 'boolean');
        if (m.lastLocation) assert.deepEqual(keysOf(m.lastLocation), CONTRACT_KEYS.location);
      }
      for (const row of data.members) {
        assert.deepEqual(keysOf(row), STAT_KEYS);
        for (const key of ['pendingTasks', 'overdueTasks', 'completedThisWeek']) {
          assert.equal(Number.isInteger(row[key]) && row[key] >= 0, true, `${key} = ${row[key]}`);
        }
      }
      assert.ok(data.myTasks.length > 0 && data.goals.length > 0 && data.latestNotices.length > 0 && data.activeSos.length > 0);
      for (const t of data.myTasks) assert.deepEqual(keysOf(t), CONTRACT_KEYS.task);
      for (const g of data.goals) {
        assert.deepEqual(keysOf(g), CONTRACT_KEYS.goal);
        for (const key of ['targetAmount', 'savedAmount', 'progress']) assert.equal(Number.isFinite(g[key]), true);
      }
      for (const n of data.latestNotices) {
        assert.deepEqual(keysOf(n), CONTRACT_KEYS.notice);
        assert.equal(typeof n.pinned, 'boolean');
      }
      for (const s of data.activeSos) {
        assert.deepEqual(keysOf(s), CONTRACT_KEYS.sos);
        assert.deepEqual(s.trail, []);
        if (s.lastLocation) assert.deepEqual(keysOf(s.lastLocation), CONTRACT_KEYS.location);
      }
      assert.ok(data.activeSos.some((s) => s.lastLocation), 'a shared SOS location is present');
      assert.deepEqual(keysOf(data.monthSummary), CONTRACT_KEYS.summary);
      for (const key of ['income', 'expense', 'net']) assert.equal(Number.isFinite(data.monthSummary[key]), true);
      assert.ok(data.monthSummary.byCategory.length > 0);
      for (const row of data.monthSummary.byCategory) assert.deepEqual(keysOf(row), CONTRACT_KEYS.byCategory);
    }
  });

  it('Unicode, emoji and right-to-left text round-trip unchanged in every section', async () => {
    const text = {
      family: 'عائلة شارما 👨‍👩‍👧‍👦',
      admin: 'أميت شارما',
      kid: 'आरव 🦁',
      designation: 'மாணவர் தலைவர்',
      task: 'கணக்கு வீட்டுப்பாடம் ✏️ — واجب',
      description: 'Ch. ४ · 😀 · 第四章',
      goal: 'Viagem 🇧🇷 à Goa',
      noticeTitle: '🎉 दावत at 8 · مرحبا',
      noticeBody: 'שלום\nこんにちは 👋🏽',
      sos: 'مساعدة! 🚑',
    };
    const nfc = (s) => s.normalize('NFC');
    const admin = await registerFamilyAdmin({ name: text.admin, family: { name: text.family } });
    const kid = await addManagedMember(admin.auth, { name: text.kid, designation: text.designation });
    await post('/tasks', admin.auth, { title: text.task, description: text.description, assigneeId: admin.member.id, category: 'study' });
    await post('/goals', admin.auth, { title: text.goal, targetAmount: 100 });
    await post('/notices', admin.auth, { title: text.noticeTitle, body: text.noticeBody });
    await post('/sos', admin.auth, { message: text.sos });

    const res = await request.get(`${API}/dashboard`).set(admin.auth);
    assert.equal(res.status, 200);
    assert.match(res.headers['content-type'], /charset=utf-8/i);
    const data = res.body.data;
    assert.equal(data.family.name, nfc(text.family));
    assert.equal(data.me.name, nfc(text.admin));
    const kidRow = data.members.find((row) => row.member.id === kid.id);
    assert.equal(kidRow.member.name, nfc(text.kid));
    assert.equal(kidRow.member.designation, nfc(text.designation));
    assert.equal(data.myTasks[0].title, nfc(text.task));
    assert.equal(data.myTasks[0].description, nfc(text.description));
    assert.equal(data.myTasks[0].assigneeName, nfc(text.admin));
    assert.equal(data.goals[0].title, nfc(text.goal));
    assert.equal(data.latestNotices[0].title, nfc(text.noticeTitle));
    assert.equal(data.latestNotices[0].body, nfc(text.noticeBody));
    assert.equal(data.latestNotices[0].authorName, nfc(text.admin));
    assert.equal(data.activeSos[0].message, nfc(text.sos));
    assert.equal(data.activeSos[0].memberName, nfc(text.admin));
  });

  it('month summary money edge cases: 0.1 + 0.2, the maximum amount, a negative net', async () => {
    const admin = await registerFamilyAdmin();
    const familyId = admin.family.id;
    await seedEntry(familyId, admin.member, { amountMinor: 10 });
    await seedEntry(familyId, admin.member, { amountMinor: 20 });
    let summary = (await dashboard(admin.auth)).monthSummary;
    assert.equal(summary.expense, 0.3);
    assert.equal(summary.net, -0.3);
    assert.deepEqual(summary.byCategory, [{ type: 'expense', category: 'groceries', amount: 0.3 }]);

    await seedEntry(familyId, admin.member, { type: 'income', category: 'salary', amountMinor: 1e14 }); // 1e12 = contract max
    summary = (await dashboard(admin.auth)).monthSummary;
    assert.equal(summary.income, 1e12);
    assert.equal(summary.net, 999999999999.7);
  });
});

describe('GET /dashboard — hardening: dates and time zones (fixed clock)', () => {
  it('a completion dated after the current week is not "this week" (clock skew / imported data)', async () => {
    const admin = await registerFamilyAdmin();
    const familyId = admin.family.id;
    const me = admin.member.id;
    const now = new Date('2026-06-03T06:30:00.000Z'); // Wed 3 June 12:00 IST
    const nextMonday = new Date('2026-06-07T18:30:00.000Z'); // Mon 8 June 00:00 IST
    await seedDone(familyId, me, new Date(nextMonday.getTime() - 1)); // Sun 7 June 23:59:59.999 IST → this week
    await seedDone(familyId, me, nextMonday); // next week
    await seedDone(familyId, me, new Date('2031-01-01T00:00:00.000Z')); // far future

    const data = await getDashboard(actorOf(admin), { now });
    assert.equal(data.members[0].completedThisWeek, 1);
    assert.equal((await memberTaskStats(familyId, { timeZone: IST, now })).get(me).completedThisWeek, 1);
  });

  it('America/New_York, the week DST starts: Monday 00:00 EST … next Monday 00:00 EDT', async () => {
    const NY = 'America/New_York';
    const admin = await registerFamilyAdmin({ family: { timezone: NY, country: 'US', currency: 'USD' } });
    const familyId = admin.family.id;
    const me = admin.member.id;
    const now = new Date('2026-03-08T16:00:00.000Z'); // Sun 8 Mar 12:00 EDT (clocks sprang forward at 02:00)
    const weekStart = new Date('2026-03-02T05:00:00.000Z'); // Mon 2 Mar 00:00 EST (UTC−5)
    const weekEnd = new Date('2026-03-09T04:00:00.000Z'); // Mon 9 Mar 00:00 EDT (UTC−4)
    const todayStart = new Date('2026-03-08T05:00:00.000Z'); // Sun 8 Mar 00:00 EST
    assert.equal(startOfWeek(now, NY).getTime(), weekStart.getTime());
    assert.equal(startOfDay(now, NY).getTime(), todayStart.getTime());

    await seedDone(familyId, me, weekStart); // counts
    await seedDone(familyId, me, new Date(weekStart.getTime() - 1)); // Sun 1 Mar 23:59:59.999 EST → last week
    await seedDone(familyId, me, new Date(weekEnd.getTime() - 1)); // Sun 8 Mar 23:59:59.999 EDT → counts
    await seedDone(familyId, me, weekEnd); // next week
    await seedTask(familyId, me, { dueDate: todayStart }); // due today → not overdue
    await seedTask(familyId, me, { dueDate: new Date(todayStart.getTime() - 1) }); // Sat 7 Mar → overdue

    const data = await getDashboard(actorOf(admin), { now });
    const row = data.members[0];
    assert.deepEqual([row.pendingTasks, row.overdueTasks, row.completedThisWeek], [2, 1, 2]);
    assert.equal(data.monthSummary.month, '2026-03');
  });

  it('+14 h, −11 h and +5:45 zones: month summary and overdue flip at local midnight', async () => {
    const cases = [
      { zone: 'Pacific/Kiritimati', now: '2026-06-30T10:30:00.000Z', month: '2026-07' }, // Wed 1 July 00:30 (+14)
      { zone: 'Pacific/Pago_Pago', now: '2026-06-30T10:30:00.000Z', month: '2026-06' }, // Mon 29 June 23:30 (−11)
      { zone: 'Asia/Kathmandu', now: '2026-06-30T18:15:00.000Z', month: '2026-07' }, // 1 July 00:00 (+5:45)
      { zone: 'Asia/Kathmandu', now: '2026-06-30T18:14:59.999Z', month: '2026-06' }, // 30 June 23:59:59.999
    ];
    for (const { zone, now: iso, month } of cases) {
      const admin = await registerFamilyAdmin({ family: { name: `Family ${zone}` } });
      const familyId = admin.family.id;
      await Family.updateOne({ _id: familyId }, { $set: { timezone: zone } });
      const now = new Date(iso);
      const julyStart = zonedTimeToUtc({ year: 2026, month: 7, day: 1 }, zone);
      await seedEntry(familyId, admin.member, { amountMinor: 100, date: julyStart }); // 1 July local
      await seedEntry(familyId, admin.member, { amountMinor: 200, date: new Date(julyStart.getTime() - 1) }); // 30 June local
      const todayStart = startOfDay(now, zone);
      await seedTask(familyId, admin.member.id, { dueDate: todayStart }); // due today
      await seedTask(familyId, admin.member.id, { dueDate: new Date(todayStart.getTime() - 1) }); // yesterday

      const data = await getDashboard(actorOf(admin), { now });
      const label = `${zone} @ ${iso}`;
      assert.equal(data.monthSummary.month, month, label);
      assert.equal(data.monthSummary.expense, month === '2026-07' ? 1 : 2, label);
      assert.deepEqual([data.members[0].pendingTasks, data.members[0].overdueTasks], [2, 1], label);
    }
  });
});

describe('GET /dashboard — hardening: SOS, concurrency and side effects', () => {
  it('an active alert whose owner row is gone is listed like /sos/active but shows no location or names', async () => {
    const { member, familyId } = await familyOfThree();
    const ghost = newId();
    await seedAlert(familyId, ghost, { message: 'still active' });
    const data = await dashboard(member.auth);
    assert.deepEqual(data.activeSos, await getData('/sos/active', member.auth));
    const alert = data.activeSos.find((a) => a.memberId === String(ghost));
    assert.ok(alert);
    assert.equal(alert.memberName, null);
    assert.equal(alert.memberPhone, null);
    assert.equal(alert.memberAvatarUrl, null);
    assert.equal(alert.locationShared, false, 'fails closed: an owner outside the family shares nothing');
    assert.equal(alert.lastLocation, null);
    assert.deepEqual(alert.trail, []);
  });

  it('concurrent requests agree, persist the lazy expiry once and send no push or e-mail', async () => {
    const { admin, member, child, familyId } = await familyOfThree();
    const stale = await seedAlert(familyId, child.id, { startedAt: new Date(Date.now() - 20 * 60 * 1000) });
    await seedTask(familyId, member.member.id, { dueDate: localMidnight(-1) });
    await flushPushes();
    sentPushes.length = 0;
    outbox.length = 0;

    const sessions = Array.from({ length: 10 }, (_, i) => (i % 2 ? member : admin));
    const responses = await Promise.all(sessions.map((s) => request.get(`${API}/dashboard`).set(s.auth)));
    for (const res of responses) assert.equal(res.status, 200, JSON.stringify(res.body));
    for (const session of [admin, member]) {
      const bodies = responses.filter((_, i) => sessions[i] === session).map((r) => JSON.stringify(r.body));
      assert.equal(new Set(bodies).size, 1, 'every concurrent response of one caller is identical');
    }
    assert.ok(responses.every((r) => r.body.data.activeSos.length === 0));

    const stored = await SosAlert.findById(stale._id).lean();
    assert.equal(stored.status, 'expired');
    assert.equal(stored.resolvedAt ?? null, null, 'expired, not resolved');
    await flushPushes();
    assert.equal(sentPushes.length, 0, 'reading the dashboard never notifies anyone');
    assert.equal(outbox.length, 0);
  });
});

// ---------------------------------------------------------------- query plans

/**
 * Reads that must stay bounded however long the family has used the app. The two index-dependent
 * checks run as `todo` until the models owner adds the index (docs/progress/b-dashboard.md,
 * handoffs); they turn into regular checks automatically once the schema declares it.
 */
const schemaHasIndex = (Model, matches) => Model.schema.indexes().some(([fields]) => matches(Object.keys(fields)));
const TASK_COMPLETED_INDEX = schemaHasIndex(Task, (k) => k[0] === 'familyId' && k.includes('status') && k.includes('completedAt'));
const NOTICE_SORT_INDEX = schemaHasIndex(Notice, (k) => k.join() === 'familyId,pinned,createdAt,_id');

describe('GET /dashboard — hardening: query plans', () => {
  /**
   * Runs `fn` with the MongoDB profiler on and returns the profile rows of this app's collections.
   * `system.profile` is dropped afterwards: helpers.js#resetDb cannot write to it.
   */
  async function profiled(fn) {
    const { db } = mongoose.connection;
    await db.command({ profile: 2 });
    let rows;
    try {
      await fn();
    } finally {
      await db.command({ profile: 0 });
      rows = await db.collection('system.profile').find({}).toArray();
      await db.dropCollection('system.profile').catch(() => {});
    }
    return rows.filter((r) => !/\.(system\.profile|\$cmd)$/.test(r.ns));
  }

  const examined = (rows, collection) =>
    rows.filter((r) => r.ns.endsWith(`.${collection}`)).reduce((n, r) => n + (r.docsExamined ?? 0), 0);

  it('no collection scan anywhere in a dashboard request', async () => {
    const { admin, familyId } = await familyOfThree();
    await seedTask(familyId, admin.member.id);
    await seedDone(familyId, admin.member.id, new Date());
    await seedAlert(familyId, admin.member.id);
    await seedEntry(familyId, admin.member);
    const rows = await profiled(() => dashboard(admin.auth));
    const scans = rows.filter((r) => String(r.planSummary ?? '').includes('COLLSCAN'));
    assert.deepEqual(scans.map((r) => `${r.ns} ${r.op}`), []);
    assert.ok(rows.length > 0, 'profiler captured the request');
  });

  it(
    "counters read only pending and this week's done tasks, not the family's whole history",
    { todo: TASK_COMPLETED_INDEX ? false : 'needs Task index { familyId: 1, status: 1, completedAt: -1 } (models owner)' },
    async () => {
      const admin = await registerFamilyAdmin();
      const familyId = admin.family.id;
      const me = admin.member.id;
      const now = Date.now();
      const old = Array.from({ length: 300 }, (_, i) => ({
        familyId, title: `old ${i}`, assigneeId: me, createdById: me, category: 'chore', priority: 'low',
        status: 'done', completedAt: new Date(now - (30 + i) * DAY_MS), completedById: me,
      }));
      await Task.insertMany(old);
      await seedDone(familyId, me, new Date());
      await seedTask(familyId, me);
      const rows = await profiled(() => memberTaskStats(familyId, { timeZone: IST }));
      assert.ok(examined(rows, 'tasks') <= 10, `examined ${examined(rows, 'tasks')} task documents`);
    },
  );

  it(
    'latest notices come straight from the index (no blocking sort over every notice)',
    { todo: NOTICE_SORT_INDEX ? false : 'needs Notice index { familyId: 1, pinned: -1, createdAt: -1, _id: -1 } (models owner)' },
    async () => {
      const admin = await registerFamilyAdmin();
      const familyId = admin.family.id;
      const base = Date.now();
      await Notice.insertMany(
        Array.from({ length: 200 }, (_, i) => ({
          familyId, title: `N${i}`, body: 'b', pinned: i === 150, authorId: admin.member.id, createdAt: new Date(base - i * 60_000),
        })),
      );
      const rows = await profiled(() => listLatestNotices(familyId, { limit: 3, members: new Map() }));
      const noticeRows = rows.filter((r) => r.ns.endsWith('.notices'));
      assert.ok(examined(rows, 'notices') <= 3, `examined ${examined(rows, 'notices')} notices`);
      assert.equal(noticeRows.some((r) => r.hasSortStage), false, 'blocking in-memory sort');
    },
  );
});
