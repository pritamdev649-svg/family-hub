/**
 * Tasks module: docs/03-API_CONTRACT.md §7 (`/tasks`).
 *
 * Covers the envelope and Task shape, create / get / list / patch / complete / reopen / delete,
 * the permission matrix (admin / creator / assignee / other member / other family → 404 / no family),
 * validation details, contract sort orders + pagination, the due filters evaluated in the family time
 * zone, idempotent and race-safe complete / reopen, `task_assigned` / `task_completed` pushes
 * (recipients, route, private health texts) and names resolved from the member directory.
 */
import { API, flushPushes, joinFamilyAs, registerFamilyAdmin, resetDb, sentPushes, setupTestApp, teardownTestApp } from './helpers.js';
import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

const { default: mongoose } = await import('mongoose');
const { Task, Member, Family, User, Device } = await import('../src/models/index.js');
const { dayRange, startOfDay, weekRange } = await import('../src/lib/dates.js');
const { hasTranslation, t } = await import('../src/lib/i18n.js');
const { pushTitle, PUSH_TITLE_MAX } = await import('../src/modules/tasks/tasks.service.js');
const { serializeTask } = await import('../src/modules/tasks/tasks.serializer.js');
const { hasVisibleText, toMultiLine, toSingleLine } = await import('../src/modules/tasks/tasks.schemas.js');

let request;

before(async () => {
  ({ request } = await setupTestApp());
});
beforeEach(resetDb);
after(teardownTestApp);

// ---------------------------------------------------------------- helpers

const OBJECT_ID = /^[a-f0-9]{24}$/;
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const TASK_KEYS = [
  'assigneeId',
  'assigneeName',
  'category',
  'completedAt',
  'completedById',
  'createdAt',
  'createdById',
  'createdByName',
  'description',
  'dueDate',
  'id',
  'priority',
  'status',
  'title',
  'updatedAt',
];
const UNKNOWN_ID = '0123456789abcdef01234567';

const oid = (id) => new mongoose.Types.ObjectId(String(id));

function assertOk(res, status = 200) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.equal(res.body.success, true);
  assert.ok('data' in res.body);
  return res.body.data;
}

function assertPaged(res) {
  const data = assertOk(res);
  assert.ok(Array.isArray(data));
  assert.deepEqual(Object.keys(res.body.meta).sort(), ['hasMore', 'limit', 'page', 'total']);
  return { data, meta: res.body.meta };
}

function assertError(res, status, code) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.equal(res.body.success, false);
  assert.equal(res.body.error.code, code);
  assert.equal(typeof res.body.error.message, 'string');
  assert.ok(res.body.error.message.length > 0);
  assert.ok(!('data' in res.body));
  return res.body.error;
}

function assertTaskShape(task) {
  assert.deepEqual(Object.keys(task).sort(), TASK_KEYS);
  assert.match(task.id, OBJECT_ID);
  assert.match(task.assigneeId, OBJECT_ID);
  assert.match(task.createdById, OBJECT_ID);
  assert.match(task.createdAt, ISO);
  assert.match(task.updatedAt, ISO);
  assert.ok(!('_id' in task) && !('__v' in task) && !('familyId' in task));
}

/**
 * Family "Sharma" (Asia/Kolkata): admin Amit, member Priya (account), managed child Anaya (no account).
 * Family "Other": admin Olivia. Pushes from the setup (member_joined) are dropped.
 */
async function setupFamilies() {
  const admin = await registerFamilyAdmin({ name: 'Amit Sharma' });
  const member = await joinFamilyAs(admin.family.inviteCode, { name: 'Priya Sharma' });
  const childDoc = await Member.create({
    familyId: admin.family.id,
    name: 'Anaya',
    role: 'member',
    dateOfBirth: new Date('2016-08-01T00:00:00.000Z'),
    guardianConsent: true,
  });
  const other = await registerFamilyAdmin({ name: 'Olivia Other', family: { name: 'Other Family' } });
  await flushPushes();
  sentPushes.length = 0;
  return {
    familyId: admin.family.id,
    admin: { auth: admin.auth, id: admin.member.id, userId: admin.user.id, name: 'Amit Sharma' },
    member: { auth: member.auth, id: member.member.id, userId: member.user.id, name: 'Priya Sharma' },
    child: { id: String(childDoc._id), name: 'Anaya' },
    other: { auth: other.auth, id: other.member.id, familyId: other.family.id },
  };
}

const post = (auth, path, body) => request.post(`${API}${path}`).set(auth).send(body);
const patch = (auth, path, body) => request.patch(`${API}${path}`).set(auth).send(body);
const get = (auth, path) => request.get(`${API}${path}`).set(auth);
const del = (auth, path) => request.delete(`${API}${path}`).set(auth);

async function createTask(auth, body) {
  return assertOk(await post(auth, '/tasks', { title: 'Finish maths homework', ...body }), 201);
}

async function taskPushes(type) {
  await flushPushes();
  return sentPushes.filter((p) => p.type === type);
}

/** Inserts a task directly (bypasses timestamps so createdAt / completedAt can be controlled). */
async function insertTask(familyId, fields) {
  const at = fields.createdAt ?? new Date();
  const doc = {
    familyId: oid(familyId),
    title: 'Seeded task',
    description: null,
    dueDate: null,
    category: 'other',
    priority: 'medium',
    status: 'pending',
    completedAt: null,
    completedById: null,
    createdAt: at,
    updatedAt: at,
    ...fields,
  };
  for (const key of ['familyId', 'assigneeId', 'createdById', 'completedById']) if (doc[key]) doc[key] = oid(doc[key]);
  const res = await Task.collection.insertOne(doc);
  return String(res.insertedId);
}

const ids = (list) => list.map((task) => task.id);

// ---------------------------------------------------------------- auth / envelope

describe('tasks: authentication and family scope', () => {
  it('rejects anonymous calls on every route with 401', async () => {
    const id = UNKNOWN_ID;
    const calls = [
      request.get(`${API}/tasks`),
      request.post(`${API}/tasks`).send({}),
      request.get(`${API}/tasks/${id}`),
      request.patch(`${API}/tasks/${id}`).send({}),
      request.post(`${API}/tasks/${id}/complete`),
      request.post(`${API}/tasks/${id}/reopen`),
      request.delete(`${API}/tasks/${id}`),
    ];
    for (const res of await Promise.all(calls)) assertError(res, 401, 'UNAUTHORIZED');
  });

  it('answers 403 NO_FAMILY for a user without a family', async () => {
    const admin = await registerFamilyAdmin();
    await User.updateOne({ _id: admin.user.id }, { familyId: null, memberId: null });
    assertError(await get(admin.auth, '/tasks'), 403, 'NO_FAMILY');
    assertError(await post(admin.auth, '/tasks', { title: 'x', assigneeId: admin.member.id }), 403, 'NO_FAMILY');
  });

  it('answers 400 BAD_REQUEST for a malformed task id', async () => {
    const { admin } = await setupFamilies();
    const bad = 'not-an-id';
    assertError(await get(admin.auth, `/tasks/${bad}`), 400, 'BAD_REQUEST');
    assertError(await patch(admin.auth, `/tasks/${bad}`, { title: 'x' }), 400, 'BAD_REQUEST');
    assertError(await post(admin.auth, `/tasks/${bad}/complete`), 400, 'BAD_REQUEST');
    assertError(await post(admin.auth, `/tasks/${bad}/reopen`), 400, 'BAD_REQUEST');
    assertError(await del(admin.auth, `/tasks/${bad}`), 400, 'BAD_REQUEST');
  });

  it('answers 404 for an unknown task and for a task of another family on every route', async () => {
    const f = await setupFamilies();
    const foreign = await createTask(f.other.auth, { assigneeId: f.other.id });
    for (const id of [UNKNOWN_ID, foreign.id]) {
      assertError(await get(f.admin.auth, `/tasks/${id}`), 404, 'NOT_FOUND');
      assertError(await patch(f.admin.auth, `/tasks/${id}`, { title: 'x' }), 404, 'NOT_FOUND');
      assertError(await post(f.admin.auth, `/tasks/${id}/complete`), 404, 'NOT_FOUND');
      assertError(await post(f.admin.auth, `/tasks/${id}/reopen`), 404, 'NOT_FOUND');
      assertError(await del(f.admin.auth, `/tasks/${id}`), 404, 'NOT_FOUND');
    }
    const untouched = await Task.findById(foreign.id).lean();
    assert.equal(untouched.title, 'Finish maths homework');
    assert.equal(untouched.status, 'pending');
  });
});

// ---------------------------------------------------------------- create

describe('POST /tasks', () => {
  it('admin creates a task for a member: 201, full Task shape, names filled, task_assigned push', async () => {
    const f = await setupFamilies();
    const res = await post(f.admin.auth, '/tasks', {
      title: '  Finish maths homework  ',
      description: ' Ch. 4 ',
      assigneeId: f.member.id,
      dueDate: '2026-10-01T18:30:00.000Z',
      category: 'study',
      priority: 'high',
    });
    const task = assertOk(res, 201);
    assert.ok(!('meta' in res.body));
    assertTaskShape(task);
    assert.equal(task.title, 'Finish maths homework');
    assert.equal(task.description, 'Ch. 4');
    assert.equal(task.assigneeId, f.member.id);
    assert.equal(task.assigneeName, f.member.name);
    assert.equal(task.createdById, f.admin.id);
    assert.equal(task.createdByName, f.admin.name);
    assert.equal(task.dueDate, '2026-10-01T18:30:00.000Z');
    assert.equal(task.category, 'study');
    assert.equal(task.priority, 'high');
    assert.equal(task.status, 'pending');
    assert.equal(task.completedAt, null);
    assert.equal(task.completedById, null);

    const stored = await Task.findById(task.id).lean();
    assert.equal(String(stored.familyId), f.familyId);

    const pushes = await taskPushes('task_assigned');
    assert.equal(pushes.length, 1);
    const [push] = pushes;
    assert.equal(push.id, task.id);
    assert.equal(push.route, `/tasks/${task.id}`);
    assert.equal(push.familyId, f.familyId);
    assert.deepEqual(push.requestedMemberIds, [f.member.id]);
    assert.deepEqual(push.memberIds, [f.member.id]);
    assert.equal(push.titleKey, 'tasks.push.assigned.title');
    assert.equal(push.bodyKey, 'tasks.push.assigned.body');
    assert.deepEqual(push.vars, { name: f.admin.name, title: 'Finish maths homework' });
    assert.equal(push.channelId, 'general');
    assert.equal(push.highPriority, false);
  });

  it('defaults category / priority and leaves description / dueDate null', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.admin.id });
    assert.equal(task.category, 'other');
    assert.equal(task.priority, 'medium');
    assert.equal(task.description, null);
    assert.equal(task.dueDate, null);
  });

  it('sends no push when the assignee is the creator', async () => {
    const f = await setupFamilies();
    await createTask(f.admin.auth, { assigneeId: f.admin.id });
    await createTask(f.member.auth, { assigneeId: f.member.id });
    assert.equal((await taskPushes('task_assigned')).length, 0);
  });

  it('member may create a task only for themselves (403 FORBIDDEN, localized message)', async () => {
    const f = await setupFamilies();
    const own = await createTask(f.member.auth, { assigneeId: f.member.id });
    assert.equal(own.createdById, f.member.id);
    assert.equal(own.assigneeName, f.member.name);

    for (const assigneeId of [f.admin.id, f.child.id]) {
      const err = assertError(await post(f.member.auth, '/tasks', { title: 'x', assigneeId }), 403, 'FORBIDDEN');
      assert.equal(err.message, t('en', 'tasks.errors.assignSelfOnly'));
    }
    assert.equal(await Task.countDocuments({}), 1);
  });

  it('admin may assign a managed profile (no account): created, but no push is sent', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.child.id, category: 'chore' });
    assert.equal(task.assigneeName, 'Anaya');
    assert.equal((await taskPushes('task_assigned')).length, 0);
  });

  it('rejects an assignee outside the family with 422 details.assigneeId (never 404)', async () => {
    const f = await setupFamilies();
    for (const assigneeId of [f.other.id, UNKNOWN_ID]) {
      for (const auth of [f.admin.auth, f.member.auth]) {
        const err = assertError(await post(auth, '/tasks', { title: 'x', assigneeId }), 422, 'VALIDATION_ERROR');
        assert.ok(err.details.assigneeId);
        assert.equal(err.message, t('en', 'tasks.errors.assigneeNotInFamily'));
      }
    }
    assert.equal(await Task.countDocuments({}), 0);
  });

  it('validates the body with field details', async () => {
    const f = await setupFamilies();
    const cases = [
      [{}, ['title', 'assigneeId']],
      [{ title: '   ', assigneeId: f.admin.id }, ['title']],
      [{ title: 'x'.repeat(121), assigneeId: f.admin.id }, ['title']],
      [{ title: 42, assigneeId: f.admin.id }, ['title']],
      [{ title: null, assigneeId: null }, ['title', 'assigneeId']],
      [{ title: 'x', assigneeId: 'abc' }, ['assigneeId']],
      [{ title: 'x', assigneeId: f.admin.id, description: 'd'.repeat(1001) }, ['description']],
      [{ title: 'x', assigneeId: f.admin.id, description: 5 }, ['description']],
      [{ title: 'x', assigneeId: f.admin.id, category: 'fun' }, ['category']],
      [{ title: 'x', assigneeId: f.admin.id, category: null }, ['category']],
      [{ title: 'x', assigneeId: f.admin.id, priority: 'urgent' }, ['priority']],
      [{ title: 'x', assigneeId: f.admin.id, dueDate: 'tomorrow' }, ['dueDate']],
      [{ title: 'x', assigneeId: f.admin.id, dueDate: '2026-02-31' }, ['dueDate']],
      [{ title: 'x', assigneeId: f.admin.id, dueDate: '2026-10-01T10:00:00' }, ['dueDate']],
      [{ title: 'x', assigneeId: f.admin.id, dueDate: '1999-12-31T00:00:00.000Z' }, ['dueDate']],
      [{ title: 'x', assigneeId: f.admin.id, dueDate: '2101-01-01T00:00:00.000Z' }, ['dueDate']],
      [{ title: 'x', assigneeId: f.admin.id, dueDate: 1790000000000 }, ['dueDate']],
    ];
    for (const [body, fields] of cases) {
      const err = assertError(await post(f.admin.auth, '/tasks', body), 422, 'VALIDATION_ERROR');
      assert.deepEqual(Object.keys(err.details).sort(), [...fields].sort(), JSON.stringify(body));
    }
    assert.equal(await Task.countDocuments({}), 0);
  });

  it('accepts the exact length limits and blank optional fields', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, {
      title: 't'.repeat(120),
      description: '   ',
      dueDate: '',
      assigneeId: f.admin.id,
    });
    assert.equal(task.title.length, 120);
    assert.equal(task.description, null);
    assert.equal(task.dueDate, null);
    const long = await createTask(f.admin.auth, { description: 'd'.repeat(1000), assigneeId: f.admin.id });
    assert.equal(long.description.length, 1000);
  });

  it('strips read-only keys (status, completedAt, familyId, createdById)', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, {
      assigneeId: f.admin.id,
      status: 'done',
      completedAt: '2026-01-01T00:00:00.000Z',
      completedById: f.admin.id,
      createdById: f.member.id,
      familyId: f.other.familyId,
    });
    assert.equal(task.status, 'pending');
    assert.equal(task.completedAt, null);
    assert.equal(task.createdById, f.admin.id);
    const stored = await Task.findById(task.id).lean();
    assert.equal(String(stored.familyId), f.familyId);
  });

  it('reads a date-only dueDate as midnight in the family time zone', async () => {
    const f = await setupFamilies();
    const kolkata = await createTask(f.admin.auth, { assigneeId: f.admin.id, dueDate: '2026-10-05' });
    assert.equal(kolkata.dueDate, '2026-10-04T18:30:00.000Z');

    await Family.updateOne({ _id: f.familyId }, { timezone: 'America/New_York' });
    const newYork = await createTask(f.admin.auth, { assigneeId: f.admin.id, dueDate: '2026-10-05' });
    assert.equal(newYork.dueDate, '2026-10-05T04:00:00.000Z');

    // A full ISO instant (what the app sends) is stored as given.
    const exact = await createTask(f.admin.auth, { assigneeId: f.admin.id, dueDate: '2026-10-05T04:00:00+05:30' });
    assert.equal(exact.dueDate, '2026-10-04T22:30:00.000Z');
  });

  it('keeps health task titles out of push texts and shortens long titles', async () => {
    const f = await setupFamilies();
    await Device.create({ userId: f.member.userId, token: 'device-priya', platform: 'android', locale: 'en' });

    const health = await createTask(f.admin.auth, {
      title: 'Take the blood pressure tablet',
      category: 'health',
      assigneeId: f.member.id,
    });
    const longTitle = `${'Clean the garage '.repeat(6)}today`;
    const chore = await createTask(f.admin.auth, { title: longTitle, category: 'chore', assigneeId: f.member.id });

    const pushes = await taskPushes('task_assigned');
    assert.equal(pushes.length, 2);
    const [healthPush, chorePush] = pushes;
    assert.equal(healthPush.id, health.id);
    assert.equal(healthPush.bodyKey, 'tasks.push.assigned.bodyPrivate');
    assert.deepEqual(healthPush.vars, { name: f.admin.name });
    assert.equal(healthPush.messages.length, 1);
    assert.equal(healthPush.messages[0].token, 'device-priya');
    assert.equal(healthPush.messages[0].title, `New task from ${f.admin.name}`);
    assert.ok(!healthPush.messages[0].body.includes('blood pressure'));

    assert.equal(chorePush.id, chore.id);
    assert.equal(chorePush.vars.title, pushTitle(longTitle));
    assert.equal(Array.from(chorePush.vars.title).length, PUSH_TITLE_MAX);
    assert.ok(chorePush.vars.title.endsWith('…'));
    assert.equal(chorePush.messages[0].body, chorePush.vars.title);
  });
});

// ---------------------------------------------------------------- get

describe('GET /tasks/:id', () => {
  it('any family member reads any task of the family', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.child.id });
    for (const auth of [f.admin.auth, f.member.auth]) {
      const res = await get(auth, `/tasks/${task.id}`);
      const data = assertOk(res);
      assert.ok(!('meta' in res.body));
      assert.deepEqual(data, task);
    }
    assertError(await get(f.other.auth, `/tasks/${task.id}`), 404, 'NOT_FOUND');
  });

  it('resolves names from the current member directory (renames, removed members → null)', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.child.id });
    await Member.updateOne({ _id: f.child.id }, { name: 'Anaya S.' });
    assert.equal(assertOk(await get(f.member.auth, `/tasks/${task.id}`)).assigneeName, 'Anaya S.');

    await Member.deleteOne({ _id: f.child.id });
    const orphan = assertOk(await get(f.member.auth, `/tasks/${task.id}`));
    assert.equal(orphan.assigneeId, f.child.id);
    assert.equal(orphan.assigneeName, null);
    assert.equal(orphan.createdByName, f.admin.name);
  });
});

// ---------------------------------------------------------------- list

describe('GET /tasks', () => {
  /** p1…p5 pending, d1…d3 done in the Sharma family; one foreign task. Expected contract order. */
  async function seedOrdering(f) {
    const base = { familyId: f.familyId, assigneeId: f.member.id, createdById: f.admin.id };
    const d = (s) => new Date(s);
    const p1 = await insertTask(f.familyId, { ...base, title: 'p1', dueDate: d('2026-10-01T00:00:00Z'), createdAt: d('2026-09-01T00:00:00Z') });
    const p2 = await insertTask(f.familyId, { ...base, title: 'p2', dueDate: d('2026-10-05T00:00:00Z'), createdAt: d('2026-09-03T00:00:00Z') });
    const p3 = await insertTask(f.familyId, { ...base, title: 'p3', dueDate: d('2026-10-05T00:00:00Z'), createdAt: d('2026-09-02T00:00:00Z') });
    const p4 = await insertTask(f.familyId, { ...base, title: 'p4', createdAt: d('2026-09-01T00:00:00Z') });
    const p5 = await insertTask(f.familyId, { ...base, title: 'p5', assigneeId: f.child.id, createdAt: d('2026-09-05T00:00:00Z') });
    const done = { ...base, status: 'done', completedById: f.member.id };
    const d1 = await insertTask(f.familyId, { ...done, title: 'd1', dueDate: d('2026-09-01T00:00:00Z'), completedAt: d('2026-09-10T00:00:00Z') });
    const d2 = await insertTask(f.familyId, { ...done, title: 'd2', completedAt: d('2026-09-20T00:00:00Z') });
    const d3 = await insertTask(f.familyId, { ...done, title: 'd3', assigneeId: f.child.id, completedAt: d('2026-09-15T00:00:00Z') });
    await insertTask(f.other.familyId, { assigneeId: f.other.id, createdById: f.other.id, title: 'foreign' });
    return { pending: [p1, p3, p2, p4, p5], done: [d2, d3, d1], child: [p5, d3] };
  }

  it('returns an empty paginated list for a new family', async () => {
    const f = await setupFamilies();
    const { data, meta } = assertPaged(await get(f.member.auth, '/tasks'));
    assert.deepEqual(data, []);
    assert.deepEqual(meta, { page: 1, limit: 20, total: 0, hasMore: false });
  });

  it('sorts all → pending first (dueDate asc, no due date last, then createdAt), then done (completedAt desc)', async () => {
    const f = await setupFamilies();
    const order = await seedOrdering(f);
    const all = assertPaged(await get(f.member.auth, '/tasks'));
    assert.deepEqual(ids(all.data), [...order.pending, ...order.done]);
    assert.equal(all.meta.total, 8);
    all.data.forEach(assertTaskShape);

    const explicit = assertPaged(await get(f.member.auth, '/tasks?status=all'));
    assert.deepEqual(ids(explicit.data), [...order.pending, ...order.done]);

    const pending = assertPaged(await get(f.member.auth, '/tasks?status=pending'));
    assert.deepEqual(ids(pending.data), order.pending);
    assert.equal(pending.meta.total, 5);

    const done = assertPaged(await get(f.member.auth, '/tasks?status=done'));
    assert.deepEqual(ids(done.data), order.done);
    assert.ok(done.data.every((task) => task.status === 'done' && ISO.test(task.completedAt)));
  });

  it('paginates without overlaps or gaps and reports hasMore', async () => {
    const f = await setupFamilies();
    const order = await seedOrdering(f);
    const expected = [...order.pending, ...order.done];
    const seen = [];
    for (const [page, hasMore] of [[1, true], [2, true], [3, false]]) {
      const { data, meta } = assertPaged(await get(f.admin.auth, `/tasks?page=${page}&limit=3`));
      assert.deepEqual(meta, { page, limit: 3, total: 8, hasMore });
      seen.push(...ids(data));
    }
    assert.deepEqual(seen, expected);
    const beyond = assertPaged(await get(f.admin.auth, '/tasks?page=4&limit=3'));
    assert.deepEqual(beyond.data, []);
    assert.deepEqual(beyond.meta, { page: 4, limit: 3, total: 8, hasMore: false });
  });

  it('filters by assigneeId (another family\'s member id simply matches nothing)', async () => {
    const f = await setupFamilies();
    const order = await seedOrdering(f);
    const child = assertPaged(await get(f.member.auth, `/tasks?assigneeId=${f.child.id}`));
    assert.deepEqual(ids(child.data), order.child);
    assert.ok(child.data.every((task) => task.assigneeName === 'Anaya'));

    const childDone = assertPaged(await get(f.member.auth, `/tasks?assigneeId=${f.child.id}&status=done`));
    assert.deepEqual(ids(childDone.data), [order.child[1]]);

    const foreign = assertPaged(await get(f.member.auth, `/tasks?assigneeId=${f.other.id}`));
    assert.deepEqual(foreign.data, []);
    assert.equal(foreign.meta.total, 0);

    const blank = assertPaged(await get(f.member.auth, '/tasks?assigneeId=&status=&due='));
    assert.equal(blank.meta.total, 8);
  });

  it('validates the query (422 details)', async () => {
    const f = await setupFamilies();
    const cases = [
      ['status=open', ['status']],
      ['due=tomorrow', ['due']],
      ['assigneeId=abc', ['assigneeId']],
      ['page=0', ['page']],
      ['limit=0', ['limit']],
      ['limit=101', ['limit']],
      ['page=x&limit=y', ['page', 'limit']],
      ['status=done&status=pending', ['status']],
    ];
    for (const [query, fields] of cases) {
      const err = assertError(await get(f.admin.auth, `/tasks?${query}`), 422, 'VALIDATION_ERROR');
      assert.deepEqual(Object.keys(err.details).sort(), [...fields].sort(), query);
    }
    const max = assertPaged(await get(f.admin.auth, '/tasks?limit=100'));
    assert.equal(max.meta.limit, 100);
  });

  /**
   * Seeds tasks around the today / week boundaries of `timeZone` and compares every due filter with
   * the expected ids. The boundaries differ from UTC, so evaluating in the wrong zone fails.
   */
  async function checkDueFilters(f, timeZone) {
    await Task.deleteMany({});
    await Family.updateOne({ _id: f.familyId }, { timezone: timeZone });
    const now = new Date();
    const today = dayRange(now, timeZone);
    const week = weekRange(now, timeZone);
    const ms = (d, delta) => new Date(d.getTime() + delta);
    const specs = [
      { due: ms(today.start, -1), status: 'pending' },
      { due: ms(today.start, -1), status: 'done' },
      { due: ms(today.start, -3 * 86_400_000), status: 'pending' },
      { due: today.start, status: 'pending' },
      { due: ms(today.end, -1), status: 'pending' },
      { due: ms(today.start, 3_600_000), status: 'done' },
      { due: today.end, status: 'pending' },
      { due: week.start, status: 'pending' },
      { due: ms(week.start, -1), status: 'pending' },
      { due: ms(week.end, -1), status: 'done' },
      { due: week.end, status: 'pending' },
      { due: null, status: 'pending' },
      { due: null, status: 'done' },
    ];
    const seeded = [];
    for (const [i, spec] of specs.entries()) {
      const id = await insertTask(f.familyId, {
        title: `t${i}`,
        assigneeId: f.member.id,
        createdById: f.admin.id,
        dueDate: spec.due,
        status: spec.status,
        completedAt: spec.status === 'done' ? new Date() : null,
        completedById: spec.status === 'done' ? f.member.id : null,
        createdAt: new Date(Date.UTC(2026, 0, 1, 0, 0, i)),
      });
      seeded.push({ id, ...spec });
    }
    const within = (d, { start, end }) => d && d >= start && d < end;
    const expectIds = (predicate) => seeded.filter(predicate).map((s) => s.id).sort();
    const startOfToday = startOfDay(now, timeZone);
    const expectations = {
      'due=overdue': expectIds((s) => s.status === 'pending' && s.due && s.due < startOfToday),
      'due=overdue&status=pending': expectIds((s) => s.status === 'pending' && s.due && s.due < startOfToday),
      'due=overdue&status=done': [],
      'due=today': expectIds((s) => within(s.due, today)),
      'due=today&status=pending': expectIds((s) => s.status === 'pending' && within(s.due, today)),
      'due=today&status=done': expectIds((s) => s.status === 'done' && within(s.due, today)),
      'due=week': expectIds((s) => within(s.due, week)),
      'due=week&status=done': expectIds((s) => s.status === 'done' && within(s.due, week)),
    };
    // Fixture sanity (exact counts depend on the weekday: e.g. on a Monday week.start is today).
    assert.ok(expectations['due=overdue'].length >= 3, 'fixture: overdue tasks');
    assert.ok(expectations['due=today'].length >= 3, 'fixture: tasks due today');
    assert.ok(expectations['due=today&status=done'].length >= 1, 'fixture: done task due today');
    for (const [query, expected] of Object.entries(expectations)) {
      const { data, meta } = assertPaged(await get(f.member.auth, `/tasks?${query}&limit=100`));
      assert.deepEqual(ids(data).sort(), expected, `${timeZone} ${query}`);
      assert.equal(meta.total, expected.length);
    }
  }

  for (const timeZone of ['Asia/Kolkata', 'America/Los_Angeles', 'Pacific/Kiritimati']) {
    it(`evaluates due=overdue|today|week in the family time zone (${timeZone})`, async () => {
      const f = await setupFamilies();
      await checkDueFilters(f, timeZone);
    });
  }

  it('lists only the caller family\'s tasks', async () => {
    const f = await setupFamilies();
    await createTask(f.other.auth, { assigneeId: f.other.id });
    const mine = await createTask(f.admin.auth, { assigneeId: f.member.id });
    const { data } = assertPaged(await get(f.member.auth, '/tasks'));
    assert.deepEqual(ids(data), [mine.id]);
    const theirs = assertPaged(await get(f.other.auth, '/tasks'));
    assert.equal(theirs.meta.total, 1);
    assert.notEqual(theirs.data[0].id, mine.id);
  });
});

// ---------------------------------------------------------------- patch

describe('PATCH /tasks/:id', () => {
  it('admin edits any task; only the given fields change; null clears description / dueDate', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.member.auth, {
      assigneeId: f.member.id,
      description: 'Ch. 4',
      dueDate: '2026-10-01T18:30:00.000Z',
      category: 'study',
    });
    await new Promise((r) => setTimeout(r, 5));
    const updated = assertOk(
      await patch(f.admin.auth, `/tasks/${task.id}`, { title: ' Ch. 5 ', priority: 'high', description: null, dueDate: null }),
    );
    assertTaskShape(updated);
    assert.equal(updated.title, 'Ch. 5');
    assert.equal(updated.priority, 'high');
    assert.equal(updated.description, null);
    assert.equal(updated.dueDate, null);
    assert.equal(updated.category, 'study');
    assert.equal(updated.assigneeId, f.member.id);
    assert.equal(updated.createdById, f.member.id);
    assert.ok(updated.updatedAt > task.updatedAt);
    assert.equal(updated.createdAt, task.createdAt);
  });

  it('creator (member) edits their own task; a non-creator member gets 403', async () => {
    const f = await setupFamilies();
    const own = await createTask(f.member.auth, { assigneeId: f.member.id });
    assert.equal(assertOk(await patch(f.member.auth, `/tasks/${own.id}`, { category: 'chore' })).category, 'chore');

    const assigned = await createTask(f.admin.auth, { assigneeId: f.member.id });
    const err = assertError(await patch(f.member.auth, `/tasks/${assigned.id}`, { title: 'mine now' }), 403, 'FORBIDDEN');
    assert.equal(err.message, t('en', 'tasks.errors.editNotAllowed'));
    assert.equal((await Task.findById(assigned.id).lean()).title, 'Finish maths homework');
  });

  it('permission check comes before body validation of the assignee (403 before 422)', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.admin.id });
    assertError(await patch(f.member.auth, `/tasks/${task.id}`, { assigneeId: UNKNOWN_ID }), 403, 'FORBIDDEN');
    assertError(await patch(f.other.auth, `/tasks/${task.id}`, { assigneeId: UNKNOWN_ID }), 404, 'NOT_FOUND');
  });

  it('validates the body (422 details; title / category / priority / assigneeId cannot be null)', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.admin.id });
    const cases = [
      [{ title: null }, ['title']],
      [{ title: '' }, ['title']],
      [{ title: 'x'.repeat(121) }, ['title']],
      [{ category: null }, ['category']],
      [{ priority: null }, ['priority']],
      [{ priority: 'urgent' }, ['priority']],
      [{ assigneeId: null }, ['assigneeId']],
      [{ dueDate: 'soon' }, ['dueDate']],
      [{ description: 'd'.repeat(1001) }, ['description']],
    ];
    for (const [body, fields] of cases) {
      const err = assertError(await patch(f.admin.auth, `/tasks/${task.id}`, body), 422, 'VALIDATION_ERROR');
      assert.deepEqual(Object.keys(err.details).sort(), fields, JSON.stringify(body));
    }
  });

  it('an empty body (or only read-only keys) returns the task unchanged', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.member.id });
    assert.deepEqual(assertOk(await patch(f.admin.auth, `/tasks/${task.id}`, {})), task);
    const same = assertOk(
      await patch(f.admin.auth, `/tasks/${task.id}`, { status: 'done', completedAt: '2026-01-01T00:00:00.000Z' }),
    );
    assert.equal(same.status, 'pending');
    assert.equal(same.completedAt, null);
  });

  it('re-assigning: admin → any member with a task_assigned push; unknown / foreign assignee → 422', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.admin.id });
    assert.equal((await taskPushes('task_assigned')).length, 0);

    const moved = assertOk(await patch(f.admin.auth, `/tasks/${task.id}`, { assigneeId: f.member.id }));
    assert.equal(moved.assigneeId, f.member.id);
    assert.equal(moved.assigneeName, f.member.name);
    const pushes = await taskPushes('task_assigned');
    assert.equal(pushes.length, 1);
    assert.deepEqual(pushes[0].requestedMemberIds, [f.member.id]);
    assert.equal(pushes[0].route, `/tasks/${task.id}`);

    // Same assignee again → no new push.
    assertOk(await patch(f.admin.auth, `/tasks/${task.id}`, { assigneeId: f.member.id, title: 'Renamed' }));
    assert.equal((await taskPushes('task_assigned')).length, 1);

    for (const assigneeId of [f.other.id, UNKNOWN_ID]) {
      const err = assertError(await patch(f.admin.auth, `/tasks/${task.id}`, { assigneeId }), 422, 'VALIDATION_ERROR');
      assert.ok(err.details.assigneeId);
    }
    assert.equal((await Task.findById(task.id).lean()).assigneeId.toString(), f.member.id);
  });

  it('a member-creator may only re-assign to themselves', async () => {
    const f = await setupFamilies();
    // Created while the member was an admin, assigned to the child.
    const id = await insertTask(f.familyId, { assigneeId: f.child.id, createdById: f.member.id, title: 'Old task' });
    const err = assertError(await patch(f.member.auth, `/tasks/${id}`, { assigneeId: f.admin.id }), 403, 'FORBIDDEN');
    assert.equal(err.message, t('en', 'tasks.errors.assignSelfOnly'));
    const mine = assertOk(await patch(f.member.auth, `/tasks/${id}`, { assigneeId: f.member.id }));
    assert.equal(mine.assigneeId, f.member.id);
    assert.equal((await taskPushes('task_assigned')).length, 0);
  });

  it('re-sending the current assignee works even after that member was removed', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.child.id });
    await post(f.admin.auth, `/tasks/${task.id}/complete`);
    await Member.deleteOne({ _id: f.child.id });
    const edited = assertOk(await patch(f.admin.auth, `/tasks/${task.id}`, { assigneeId: f.child.id, title: 'Kept' }));
    assert.equal(edited.title, 'Kept');
    assert.equal(edited.assigneeName, null);
  });

  it('a date-only dueDate is resolved in the family time zone', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.admin.id });
    const updated = assertOk(await patch(f.admin.auth, `/tasks/${task.id}`, { dueDate: '2026-12-31' }));
    assert.equal(updated.dueDate, '2026-12-30T18:30:00.000Z');
  });
});

// ---------------------------------------------------------------- complete / reopen

describe('POST /tasks/:id/complete and /reopen', () => {
  it('assignee completes: done + completedAt/completedById, task_completed push to the creator', async () => {
    const f = await setupFamilies();
    await Device.create({ userId: f.admin.userId, token: 'device-amit', platform: 'ios', locale: 'en' });
    const task = await createTask(f.admin.auth, { title: 'Tidy up your room', category: 'chore', assigneeId: f.member.id });

    const before = Date.now();
    const done = assertOk(await post(f.member.auth, `/tasks/${task.id}/complete`));
    assertTaskShape(done);
    assert.equal(done.status, 'done');
    assert.equal(done.completedById, f.member.id);
    assert.ok(new Date(done.completedAt).getTime() >= before - 1000);

    const pushes = await taskPushes('task_completed');
    assert.equal(pushes.length, 1);
    const [push] = pushes;
    assert.equal(push.id, task.id);
    assert.equal(push.route, `/tasks/${task.id}`);
    assert.deepEqual(push.requestedMemberIds, [f.admin.id]);
    assert.deepEqual(push.memberIds, [f.admin.id]);
    assert.equal(push.titleKey, 'tasks.push.completed.title');
    assert.equal(push.bodyKey, 'tasks.push.completed.body');
    assert.deepEqual(push.vars, { name: f.member.name, title: 'Tidy up your room' });
    assert.equal(push.messages[0].token, 'device-amit');
    assert.equal(push.messages[0].body, t('en', 'tasks.push.completed.body', push.vars));
  });

  it('complete is idempotent: same completedAt, no second push', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.member.id });
    const first = assertOk(await post(f.member.auth, `/tasks/${task.id}/complete`));
    const again = assertOk(await post(f.member.auth, `/tasks/${task.id}/complete`));
    const byAdmin = assertOk(await post(f.admin.auth, `/tasks/${task.id}/complete`));
    assert.equal(again.completedAt, first.completedAt);
    assert.equal(byAdmin.completedAt, first.completedAt);
    assert.equal(byAdmin.completedById, f.member.id);
    assert.equal((await taskPushes('task_completed')).length, 1);
  });

  it('parallel completes are race-safe: one transition, one push', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.member.id });
    const results = await Promise.all(
      Array.from({ length: 6 }, () => post(f.member.auth, `/tasks/${task.id}/complete`)),
    );
    const completedAts = new Set(results.map((res) => assertOk(res).completedAt));
    assert.equal(completedAts.size, 1);
    assert.equal((await taskPushes('task_completed')).length, 1);
  });

  it('admin may complete any task; no push when the completer is the creator', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.child.id });
    const done = assertOk(await post(f.admin.auth, `/tasks/${task.id}/complete`));
    assert.equal(done.completedById, f.admin.id);
    assert.equal((await taskPushes('task_completed')).length, 0);
  });

  it('admin completing a member-created task notifies that member; health titles stay private', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.member.auth, { title: 'Blood test', category: 'health', assigneeId: f.member.id });
    assertOk(await post(f.admin.auth, `/tasks/${task.id}/complete`));
    const [push] = await taskPushes('task_completed');
    assert.deepEqual(push.requestedMemberIds, [f.member.id]);
    assert.equal(push.bodyKey, 'tasks.push.completed.bodyPrivate');
    assert.deepEqual(push.vars, { name: f.admin.name });
  });

  it('only the assignee or an admin may complete / reopen (403 with a localized message)', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.child.id });
    let err = assertError(await post(f.member.auth, `/tasks/${task.id}/complete`), 403, 'FORBIDDEN');
    assert.equal(err.message, t('en', 'tasks.errors.completeNotAllowed'));
    assert.equal((await Task.findById(task.id).lean()).status, 'pending');

    assertOk(await post(f.admin.auth, `/tasks/${task.id}/complete`));
    err = assertError(await post(f.member.auth, `/tasks/${task.id}/reopen`), 403, 'FORBIDDEN');
    assert.equal((await Task.findById(task.id).lean()).status, 'done');

    // The creator (member) who is not the assignee cannot complete either.
    const id = await insertTask(f.familyId, { assigneeId: f.child.id, createdById: f.member.id });
    assertError(await post(f.member.auth, `/tasks/${id}/complete`), 403, 'FORBIDDEN');
  });

  it('reopen clears completion and is idempotent; complete → reopen → complete works again', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.member.id });
    const untouched = assertOk(await post(f.member.auth, `/tasks/${task.id}/reopen`));
    assert.equal(untouched.status, 'pending');
    assert.equal(untouched.updatedAt, task.updatedAt);

    assertOk(await post(f.member.auth, `/tasks/${task.id}/complete`));
    const reopened = assertOk(await post(f.member.auth, `/tasks/${task.id}/reopen`));
    assert.equal(reopened.status, 'pending');
    assert.equal(reopened.completedAt, null);
    assert.equal(reopened.completedById, null);
    const again = assertOk(await post(f.admin.auth, `/tasks/${task.id}/reopen`));
    assert.equal(again.updatedAt, reopened.updatedAt);

    const redone = assertOk(await post(f.member.auth, `/tasks/${task.id}/complete`));
    assert.equal(redone.status, 'done');
    assert.equal((await taskPushes('task_completed')).length, 2);
  });

  it('reopening a done task whose assignee left the family → 422 details.assigneeId until re-assigned', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.child.id });
    assertOk(await post(f.admin.auth, `/tasks/${task.id}/complete`));
    await Member.deleteOne({ _id: f.child.id });

    const err = assertError(await post(f.admin.auth, `/tasks/${task.id}/reopen`), 422, 'VALIDATION_ERROR');
    assert.ok(err.details.assigneeId);
    assert.equal(err.message, t('en', 'tasks.errors.assigneeRemoved'));
    assert.equal((await Task.findById(task.id).lean()).status, 'done');

    assertOk(await patch(f.admin.auth, `/tasks/${task.id}`, { assigneeId: f.member.id }));
    assert.equal(assertOk(await post(f.admin.auth, `/tasks/${task.id}/reopen`)).status, 'pending');
  });

  it('completing a task whose creator was removed sends no push', async () => {
    const f = await setupFamilies();
    const id = await insertTask(f.familyId, { assigneeId: f.member.id, createdById: UNKNOWN_ID });
    const done = assertOk(await post(f.member.auth, `/tasks/${id}/complete`));
    assert.equal(done.createdByName, null);
    assert.equal((await taskPushes('task_completed')).length, 0);
  });
});

// ---------------------------------------------------------------- delete

describe('DELETE /tasks/:id', () => {
  it('creator deletes their own task: data null, then 404', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.member.auth, { assigneeId: f.member.id });
    const res = await del(f.member.auth, `/tasks/${task.id}`);
    assert.equal(assertOk(res), null);
    assertError(await get(f.member.auth, `/tasks/${task.id}`), 404, 'NOT_FOUND');
    assertError(await del(f.member.auth, `/tasks/${task.id}`), 404, 'NOT_FOUND');
  });

  it('admin deletes any task; a non-creator member (even the assignee) gets 403; other family 404', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.member.id });
    const err = assertError(await del(f.member.auth, `/tasks/${task.id}`), 403, 'FORBIDDEN');
    assert.equal(err.message, t('en', 'tasks.errors.editNotAllowed'));
    assertError(await del(f.other.auth, `/tasks/${task.id}`), 404, 'NOT_FOUND');
    assert.equal(await Task.countDocuments({ _id: task.id }), 1);

    const memberTask = await createTask(f.member.auth, { assigneeId: f.member.id });
    assert.equal(assertOk(await del(f.admin.auth, `/tasks/${memberTask.id}`)), null);
    assert.equal(assertOk(await del(f.admin.auth, `/tasks/${task.id}`)), null);
    assert.equal(await Task.countDocuments({}), 0);
  });
});

// ---------------------------------------------------------------- units / i18n

describe('tasks: helpers and translations', () => {
  it('English tasks.json has every push and error text with the expected placeholders', () => {
    const keys = [
      'tasks.push.assigned.title',
      'tasks.push.assigned.body',
      'tasks.push.assigned.bodyPrivate',
      'tasks.push.completed.title',
      'tasks.push.completed.body',
      'tasks.push.completed.bodyPrivate',
      'tasks.errors.assigneeNotInFamily',
      'tasks.errors.assigneeRemoved',
      'tasks.errors.assignSelfOnly',
      'tasks.errors.editNotAllowed',
      'tasks.errors.completeNotAllowed',
    ];
    for (const key of keys) assert.ok(hasTranslation(key, 'en'), key);
    assert.equal(t('en', 'tasks.push.assigned.title', { name: 'Amit' }), 'New task from Amit');
    assert.equal(t('en', 'tasks.push.completed.body', { name: 'Priya', title: 'Homework' }), 'Priya completed: Homework');
    for (const key of ['tasks.push.assigned.bodyPrivate', 'tasks.push.completed.bodyPrivate']) {
      assert.ok(!t('en', key, { name: 'X' }).includes('{title}'), key);
    }
  });

  it('pushTitle keeps short titles and cuts long ones by grapheme clusters', () => {
    assert.equal(pushTitle('  Homework  '), 'Homework');
    const emoji = '🧹'.repeat(PUSH_TITLE_MAX + 5);
    const cut = pushTitle(emoji);
    assert.equal(Array.from(cut).length, PUSH_TITLE_MAX);
    assert.ok(cut.endsWith('…'));
    assert.ok(!cut.includes('�'));
    const exact = '🧹'.repeat(PUSH_TITLE_MAX);
    assert.equal(pushTitle(exact), exact);
  });

  it('serializeTask works on lean objects and returns null for nothing', () => {
    const members = new Map();
    assert.equal(serializeTask(null, members), null);
    const _id = oid(UNKNOWN_ID);
    const out = serializeTask(
      { _id, title: 'x', assigneeId: _id, createdById: _id, category: 'other', priority: 'low', status: 'pending' },
      members,
    );
    assert.deepEqual(Object.keys(out).sort(), TASK_KEYS);
    assert.equal(out.id, UNKNOWN_ID);
    assert.equal(out.assigneeName, null);
    assert.equal(out.dueDate, null);
    assert.equal(out.description, null);
  });
});

// ---------------------------------------------------------------- hardening (b-tasks-harden)

/**
 * Runs `effect` right after the next `Model[method](...)` query whose filter matches `match` has read
 * its result (up to `times` calls) — simulates a concurrent request landing between the service's
 * read and its write, deterministically.
 */
function afterNextRead(Model, method, effect, { match = () => true, times = 1 } = {}) {
  const own = Object.hasOwn(Model, method);
  const original = Model[method];
  let left = times;
  const restore = () => {
    if (own) Model[method] = original;
    else delete Model[method];
  };
  Model[method] = function stubbed(...args) {
    const query = original.apply(this, args);
    if (!match(args[0] ?? {})) return query;
    left -= 1;
    if (left <= 0) restore();
    const exec = query.exec.bind(query);
    query.exec = async (...execArgs) => {
      const result = await exec(...execArgs);
      await effect(result);
      return result;
    };
    return query;
  };
  return restore;
}

/** getMemberMap's query: `Member.find({ familyId })` (push recipient lookups have more keys). */
const memberMapQuery = (filter) => Object.keys(filter).length === 1 && 'familyId' in filter;

describe('tasks hardening: injection, mass assignment, text', () => {
  it('rejects MongoDB operator objects in body fields and ignores bracket keys in the query', async () => {
    const f = await setupFamilies();
    const bodies = [
      [{ title: { $ne: null }, assigneeId: f.admin.id }, 'title'],
      [{ title: 'x', assigneeId: { $ne: null } }, 'assigneeId'],
      [{ title: 'x', assigneeId: [f.admin.id] }, 'assigneeId'],
      [{ title: 'x', assigneeId: f.admin.id, dueDate: { $gt: '' } }, 'dueDate'],
      [{ title: 'x', assigneeId: f.admin.id, description: { $regex: '.*' } }, 'description'],
      [{ title: 'x', assigneeId: f.admin.id, category: { $in: ['study'] } }, 'category'],
      [{ title: 'x', assigneeId: f.admin.id, priority: ['high'] }, 'priority'],
    ];
    for (const [body, field] of bodies) {
      const err = assertError(await post(f.admin.auth, '/tasks', body), 422, 'VALIDATION_ERROR');
      assert.ok(err.details[field], JSON.stringify(body));
    }
    assert.equal(await Task.countDocuments({}), 0);

    const task = await createTask(f.admin.auth, { assigneeId: f.member.id });
    for (const body of [{ title: { $set: 'x' } }, { assigneeId: { $exists: true } }, { dueDate: { $type: 9 } }]) {
      assertError(await patch(f.admin.auth, `/tasks/${task.id}`, body), 422, 'VALIDATION_ERROR');
    }
    // Operator keys at the top level are unknown keys → stripped, never reach the update.
    const same = assertOk(await patch(f.admin.auth, `/tasks/${task.id}`, { $set: { status: 'done' }, $where: '1' }));
    assert.equal(same.status, 'pending');

    await createTask(f.other.auth, { assigneeId: f.other.id });
    for (const query of ['status[$ne]=x', 'assigneeId[$ne]=x', 'familyId=' + f.other.familyId, 'assigneeId[$gt]=']) {
      const { data } = assertPaged(await get(f.member.auth, `/tasks?${query}`));
      assert.deepEqual(ids(data), [task.id], query);
    }
  });

  it('PATCH strips mass-assignment keys (familyId, createdById, status, completion, _id, timestamps)', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.member.auth, { assigneeId: f.member.id });
    const fields = JSON.stringify({
      title: 'Mine',
      familyId: f.other.familyId,
      createdById: f.admin.id,
      status: 'done',
      completedAt: '2026-01-01T00:00:00.000Z',
      completedById: f.admin.id,
      _id: UNKNOWN_ID,
      id: UNKNOWN_ID,
      createdAt: '2000-01-01T00:00:00.000Z',
    });
    // A literal `__proto__` key (JSON.stringify of an object literal would drop it).
    const raw = `${fields.slice(0, -1)},"__proto__":{"status":"done","familyId":"${f.other.familyId}"}}`;
    const res = await request
      .patch(`${API}/tasks/${task.id}`)
      .set(f.member.auth)
      .set('content-type', 'application/json')
      .send(raw);
    const updated = assertOk(res);
    assert.equal(updated.title, 'Mine');
    assert.equal(updated.id, task.id);
    assert.equal(updated.status, 'pending');
    assert.equal(updated.createdById, f.member.id);
    assert.equal(updated.completedAt, null);
    assert.equal(updated.createdAt, task.createdAt);
    const stored = await Task.findById(task.id).lean();
    assert.equal(String(stored.familyId), f.familyId);
    assert.equal(String(stored.createdById), f.member.id);
    assert.equal(await Task.countDocuments({ familyId: f.other.familyId }), 0);
  });

  it('never leaks internals or the submitted values in errors and responses', async () => {
    const f = await setupFamilies();
    const marker = 'SECRET-MARKER';
    const bodies = [
      { title: `${marker}${'x'.repeat(130)}`, assigneeId: f.admin.id },
      { title: 'x', assigneeId: `${marker}` },
      { title: 'x', assigneeId: f.admin.id, category: marker },
      { title: 'x', assigneeId: f.admin.id, dueDate: marker },
      { title: '🧹'.repeat(61), assigneeId: f.admin.id },
    ];
    for (const body of bodies) {
      const err = assertError(await post(f.admin.auth, '/tasks', body), 422, 'VALIDATION_ERROR');
      const text = JSON.stringify(err);
      assert.ok(!text.includes(marker) && !text.includes('🧹'), text);
      assert.ok(!/Path `|mongoose|Cast to/i.test(text), text);
    }
    const task = await createTask(f.admin.auth, { assigneeId: f.member.id });
    const list = assertPaged(await get(f.member.auth, '/tasks'));
    for (const item of [task, ...list.data, assertOk(await get(f.member.auth, `/tasks/${task.id}`))]) {
      assertTaskShape(item);
    }
    const notFound = assertError(await get(f.other.auth, `/tasks/${task.id}`), 404, 'NOT_FOUND');
    assert.ok(!('details' in notFound));
  });

  it('counts title / description limits in UTF-16 units like the model (emoji never slip past zod)', async () => {
    const f = await setupFamilies();
    const ok = await createTask(f.admin.auth, {
      title: '🧹'.repeat(60),
      description: '🧹'.repeat(500),
      assigneeId: f.admin.id,
    });
    assert.equal(ok.title, '🧹'.repeat(60));
    let err = assertError(await post(f.admin.auth, '/tasks', { title: '🧹'.repeat(61), assigneeId: f.admin.id }), 422, 'VALIDATION_ERROR');
    assert.equal(err.details.title, 'Title must be at most 120 characters');
    err = assertError(
      await post(f.admin.auth, '/tasks', { title: 'x', description: '🧹'.repeat(501), assigneeId: f.admin.id }),
      422,
      'VALIDATION_ERROR',
    );
    assert.equal(err.details.description, 'Description must be at most 1000 characters');
    err = assertError(await patch(f.admin.auth, `/tasks/${ok.id}`, { title: '👨‍👩‍👧'.repeat(20) }), 422, 'VALIDATION_ERROR');
    assert.ok(err.details.title);
    assert.equal(await Task.countDocuments({}), 1);
  });

  it('keeps RTL, Indic, emoji and bidi marks exactly as typed', async () => {
    const f = await setupFamilies();
    const titles = ['اشترِ الحليب 🥛', 'दूध लाओ क्षत्रिय', '‏שלום‎ ok', 'பால் வாங்கு 👨‍👩‍👧 🇮🇳', '١٢٣'];
    for (const title of titles) {
      const task = await createTask(f.admin.auth, { title, description: `${title}\n${title}`, assigneeId: f.admin.id });
      assert.equal(task.title, title);
      assert.equal(task.description, `${title}\n${title}`);
      const stored = await Task.findById(task.id).lean();
      assert.equal(stored.title, title);
    }
  });

  it('normalises control characters, lone surrogates and invisible-only titles', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, {
      title: ' Buy\u0000milk\r\n\tnow\u007F! ',
      description: 'Line 1\r\nLine 2\rLine 3\u0000\u0007\n\tIndented\u0085',
      assigneeId: f.admin.id,
    });
    assert.equal(task.title, 'Buy milk now !');
    assert.equal(task.description, 'Line 1\nLine 2\nLine 3\n\tIndented');

    const surrogate = await createTask(f.admin.auth, { title: 'Milk \uD83E', assigneeId: f.admin.id });
    assert.equal(surrogate.title, 'Milk �');
    assert.equal((await Task.findById(surrogate.id).lean()).title, surrogate.title);

    const controlOnly = await createTask(f.admin.auth, { title: 'x', description: '\u0000\u0007', assigneeId: f.admin.id });
    assert.equal(controlOnly.description, null);

    for (const title of ['​​', '‍⁠­', '́', '\n\t\r', ' 　']) {
      const err = assertError(await post(f.admin.auth, '/tasks', { title, assigneeId: f.admin.id }), 422, 'VALIDATION_ERROR');
      assert.equal(err.details.title, 'Title is required', JSON.stringify(title));
      assertError(await patch(f.admin.auth, `/tasks/${task.id}`, { title }), 422, 'VALIDATION_ERROR');
    }
    assert.equal(await Task.countDocuments({}), 3);

    // Units
    assert.equal(toSingleLine('a\n\n\tb'), 'a b');
    assert.equal(toMultiLine('a\r\n\u0000b'), 'a\nb');
    assert.equal(hasVisibleText('​'), false);
    assert.equal(hasVisibleText('👍'), true);
  });

  it('due date window: local midnight of 2000-01-01 … 2100-12-31 in any zone; junk types rejected', async () => {
    const f = await setupFamilies();
    const accepted = [
      '1999-12-31T18:30:00.000Z', // 2000-01-01 00:00 in Asia/Kolkata (what the app sends)
      '1999-12-31T10:00:00.000Z', // 2000-01-01 00:00 in UTC+14
      '2100-12-31T12:00:00.000Z', // 2100-12-31 00:00 in UTC−12
      '2000-01-01',
      '2100-12-31',
    ];
    for (const dueDate of accepted) await createTask(f.admin.auth, { assigneeId: f.admin.id, dueDate });
    const rejected = ['1999-12-31T09:59:59.999Z', '1999-12-31', '2101-01-01T00:00:00.000Z', '2101-01-01', true, 0, [], {}, 'NaN'];
    for (const dueDate of rejected) {
      const err = assertError(await post(f.admin.auth, '/tasks', { title: 'x', assigneeId: f.admin.id, dueDate }), 422, 'VALIDATION_ERROR');
      assert.ok(err.details.dueDate, JSON.stringify(dueDate));
    }
    assert.equal(await Task.countDocuments({}), accepted.length);
  });

  it('pagination bounds: huge / fractional / non-numeric page and limit', async () => {
    const f = await setupFamilies();
    await createTask(f.admin.auth, { assigneeId: f.admin.id });
    const far = assertPaged(await get(f.admin.auth, `/tasks?page=${Number.MAX_SAFE_INTEGER}&limit=100`));
    assert.deepEqual(far.data, []);
    assert.equal(far.meta.total, 1);
    assert.equal(far.meta.hasMore, false);
    for (const query of ['page=9007199254740992', 'page=1.5', 'page=-1', 'page=NaN', 'page=Infinity', 'limit=0.5', 'limit=1e3', 'limit=-5']) {
      const err = assertError(await get(f.admin.auth, `/tasks?${query}`), 422, 'VALIDATION_ERROR');
      assert.ok(Object.keys(err.details).length >= 1, query);
    }
  });
});

describe('tasks hardening: authorization', () => {
  it('a demoted admin loses admin powers on the next request', async () => {
    const f = await setupFamilies();
    await Member.updateOne({ _id: f.member.id }, { role: 'admin' });
    const task = await createTask(f.member.auth, { assigneeId: f.child.id });
    await Member.updateOne({ _id: f.member.id }, { role: 'member' });
    assertError(await post(f.member.auth, '/tasks', { title: 'x', assigneeId: f.child.id }), 403, 'FORBIDDEN');
    assertError(await post(f.member.auth, `/tasks/${task.id}/complete`), 403, 'FORBIDDEN');
    // Still the creator: may edit / delete, but only re-assign to themselves.
    assertError(await patch(f.member.auth, `/tasks/${task.id}`, { assigneeId: f.admin.id }), 403, 'FORBIDDEN');
    assertOk(await patch(f.member.auth, `/tasks/${task.id}`, { title: 'Still mine' }));
  });

  it('a removed member with a still-valid token gets 403 NO_FAMILY on every route', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.member.auth, { assigneeId: f.member.id });
    await Member.deleteOne({ _id: f.member.id }); // user row still points at the family
    const calls = [
      get(f.member.auth, '/tasks'),
      post(f.member.auth, '/tasks', { title: 'x', assigneeId: f.member.id }),
      get(f.member.auth, `/tasks/${task.id}`),
      patch(f.member.auth, `/tasks/${task.id}`, { title: 'x' }),
      post(f.member.auth, `/tasks/${task.id}/complete`),
      post(f.member.auth, `/tasks/${task.id}/reopen`),
      del(f.member.auth, `/tasks/${task.id}`),
    ];
    for (const res of await Promise.all(calls)) assertError(res, 403, 'NO_FAMILY');
    assert.equal((await Task.findById(task.id).lean()).title, 'Finish maths homework');
  });

  it('another family cannot use this family\'s member ids anywhere', async () => {
    const f = await setupFamilies();
    const theirs = await createTask(f.other.auth, { assigneeId: f.other.id });
    for (const assigneeId of [f.admin.id, f.member.id, f.child.id]) {
      assertError(await post(f.other.auth, '/tasks', { title: 'x', assigneeId }), 422, 'VALIDATION_ERROR');
      assertError(await patch(f.other.auth, `/tasks/${theirs.id}`, { assigneeId }), 422, 'VALIDATION_ERROR');
      const { data } = assertPaged(await get(f.other.auth, `/tasks?assigneeId=${assigneeId}`));
      assert.deepEqual(data, []);
    }
    assert.equal((await Task.findById(theirs.id).lean()).assigneeId.toString(), f.other.id);
    assert.equal((await taskPushes('task_assigned')).length, 0);
  });
});

describe('tasks hardening: races', () => {
  it('complete: a task re-assigned between the permission check and the write → 403 for the old assignee', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.member.id });
    await flushPushes();
    afterNextRead(Task, 'findOne', () => Task.collection.updateOne({ _id: oid(task.id) }, { $set: { assigneeId: oid(f.admin.id) } }));
    const err = assertError(await post(f.member.auth, `/tasks/${task.id}/complete`), 403, 'FORBIDDEN');
    assert.equal(err.message, t('en', 'tasks.errors.completeNotAllowed'));
    const stored = await Task.findById(task.id).lean();
    assert.equal(stored.status, 'pending');
    assert.equal(stored.completedById, null);
    assert.equal((await taskPushes('task_completed')).length, 0);
  });

  it('complete: an admin who loses that race retries on fresh data and succeeds', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.member.auth, { assigneeId: f.member.id });
    await flushPushes();
    afterNextRead(Task, 'findOne', () => Task.collection.updateOne({ _id: oid(task.id) }, { $set: { assigneeId: oid(f.admin.id) } }));
    const done = assertOk(await post(f.admin.auth, `/tasks/${task.id}/complete`));
    assert.equal(done.status, 'done');
    assert.equal(done.assigneeId, f.admin.id);
    assert.equal(done.completedById, f.admin.id);
    assert.equal((await taskPushes('task_completed')).length, 1);
  });

  it('complete: a task whose assignee keeps changing gives up with 409 CONFLICT, unchanged', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.member.id });
    await flushPushes();
    let flip = false;
    const restore = afterNextRead(
      Task,
      'findOne',
      () => {
        flip = !flip;
        return Task.collection.updateOne({ _id: oid(task.id) }, { $set: { assigneeId: oid(flip ? f.admin.id : f.member.id) } });
      },
      { times: 3 },
    );
    try {
      assertError(await post(f.admin.auth, `/tasks/${task.id}/complete`), 409, 'CONFLICT');
    } finally {
      restore();
    }
    assert.equal((await Task.findById(task.id).lean()).status, 'pending');
  });

  it('reopen: a task re-assigned between the permission check and the write → 403 for the old assignee', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.member.id });
    const done = assertOk(await post(f.member.auth, `/tasks/${task.id}/complete`));
    await flushPushes();
    afterNextRead(Task, 'findOne', () => Task.collection.updateOne({ _id: oid(task.id) }, { $set: { assigneeId: oid(f.admin.id) } }));
    assertError(await post(f.member.auth, `/tasks/${task.id}/reopen`), 403, 'FORBIDDEN');
    const stored = await Task.findById(task.id).lean();
    assert.equal(stored.status, 'done');
    assert.equal(stored.completedAt.toISOString(), done.completedAt);
  });

  it('parallel reopens are race-safe: one transition, every caller sees pending', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.member.id });
    assertOk(await post(f.member.auth, `/tasks/${task.id}/complete`));
    const results = await Promise.all(Array.from({ length: 6 }, () => post(f.member.auth, `/tasks/${task.id}/reopen`)));
    const updatedAts = new Set(results.map((res) => assertOk(res).updatedAt));
    assert.equal(updatedAts.size, 1);
    assert.ok(results.every((res) => res.body.data.status === 'pending' && res.body.data.completedAt === null));
  });

  it('create: an assignee removed right after the check → 422, the task is not kept, no push', async () => {
    const f = await setupFamilies();
    afterNextRead(Member, 'find', () => Member.deleteOne({ _id: f.member.id }), { match: memberMapQuery });
    const err = assertError(await post(f.admin.auth, '/tasks', { title: 'x', assigneeId: f.member.id }), 422, 'VALIDATION_ERROR');
    assert.ok(err.details.assigneeId);
    assert.equal(err.message, t('en', 'tasks.errors.assigneeNotInFamily'));
    assert.equal(await Task.countDocuments({}), 0);
    assert.equal((await taskPushes('task_assigned')).length, 0);
  });

  it('PATCH: re-assigning to a member removed right after the check → 422 and the whole PATCH is undone', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.admin.id, description: 'Keep me' });
    await flushPushes();
    afterNextRead(Member, 'find', () => Member.deleteOne({ _id: f.member.id }), { match: memberMapQuery });
    const err = assertError(
      await patch(f.admin.auth, `/tasks/${task.id}`, { assigneeId: f.member.id, title: 'Changed', description: null }),
      422,
      'VALIDATION_ERROR',
    );
    assert.ok(err.details.assigneeId);
    const stored = await Task.findById(task.id).lean();
    assert.equal(String(stored.assigneeId), f.admin.id);
    assert.equal(stored.title, 'Finish maths homework');
    assert.equal(stored.description, 'Keep me');
    assert.equal(stored.updatedAt.toISOString(), task.updatedAt);
    assert.equal((await taskPushes('task_assigned')).length, 0);
  });

  it('reopen: an assignee removed right after the check → 422 and the task stays done as before', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.member.id });
    const done = assertOk(await post(f.member.auth, `/tasks/${task.id}/complete`));
    await flushPushes();
    afterNextRead(Member, 'find', () => Member.deleteOne({ _id: f.member.id }), { match: memberMapQuery });
    const err = assertError(await post(f.admin.auth, `/tasks/${task.id}/reopen`), 422, 'VALIDATION_ERROR');
    assert.equal(err.message, t('en', 'tasks.errors.assigneeRemoved'));
    const stored = await Task.findById(task.id).lean();
    assert.equal(stored.status, 'done');
    assert.equal(stored.completedAt.toISOString(), done.completedAt);
    assert.equal(String(stored.completedById), f.member.id);
    assert.equal(stored.updatedAt.toISOString(), done.updatedAt);
  });
});

describe('tasks hardening: pushes', () => {
  it('re-assigning a done task sends no task_assigned push; a pending one does', async () => {
    const f = await setupFamilies();
    const task = await createTask(f.admin.auth, { assigneeId: f.admin.id });
    assertOk(await post(f.admin.auth, `/tasks/${task.id}/complete`));
    const moved = assertOk(await patch(f.admin.auth, `/tasks/${task.id}`, { assigneeId: f.member.id }));
    assert.equal(moved.assigneeId, f.member.id);
    assert.equal((await taskPushes('task_assigned')).length, 0);

    const pending = await createTask(f.admin.auth, { assigneeId: f.admin.id });
    assertOk(await patch(f.admin.auth, `/tasks/${pending.id}`, { assigneeId: f.member.id }));
    const pushes = await taskPushes('task_assigned');
    assert.equal(pushes.length, 1);
    assert.equal(pushes[0].id, pending.id);
  });

  it('reaches only the recipient\'s devices, each in its own locale (not the actor\'s language)', async () => {
    const f = await setupFamilies();
    await User.updateOne({ _id: f.member.userId }, { locale: 'ta' });
    await Device.create([
      { userId: f.member.userId, token: 'priya-hi', platform: 'android', locale: 'hi' },
      { userId: f.member.userId, token: 'priya-default', platform: 'ios', locale: null },
      { userId: f.admin.userId, token: 'amit-phone', platform: 'android', locale: 'en' },
    ]);
    const other = await Member.findById(f.other.id).lean();
    await Device.create({ userId: other.userId, token: 'olivia-phone', platform: 'android', locale: 'en' });

    const res = await request
      .post(`${API}/tasks`)
      .set(f.admin.auth)
      .set('Accept-Language', 'es')
      .send({ title: 'Water the plants', assigneeId: f.member.id });
    const task = assertOk(res, 201);
    const [push] = await taskPushes('task_assigned');
    const byToken = Object.fromEntries(push.messages.map((m) => [m.token, m]));
    assert.deepEqual(Object.keys(byToken).sort(), ['priya-default', 'priya-hi']);
    assert.equal(byToken['priya-hi'].locale, 'hi');
    assert.equal(byToken['priya-default'].locale, 'ta');
    for (const message of push.messages) {
      assert.equal(message.title, t(message.locale, 'tasks.push.assigned.title', { name: f.admin.name }));
      assert.equal(message.body, t(message.locale, 'tasks.push.assigned.body', { title: 'Water the plants' }));
    }

    assertOk(await post(f.member.auth, `/tasks/${task.id}/complete`));
    const [completed] = await taskPushes('task_completed');
    assert.deepEqual(completed.messages.map((m) => m.token), ['amit-phone']);
  });

  it('push titles never split a grapheme cluster (Indic conjuncts, ZWJ emoji, flags)', async () => {
    const f = await setupFamilies();
    await Device.create({ userId: f.member.userId, token: 'priya', platform: 'android', locale: 'hi' });
    const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
    const clusters = (s) => Array.from(segmenter.segment(s), (part) => part.segment);
    // 61+ clusters within the 120-unit title limit; the cut (cluster 59) lands on a multi-code-point cluster.
    const samples = [
      `${'a'.repeat(58)}क्षत्रिक्ष`,
      `${'a'.repeat(58)}👨‍👩‍👧👨‍👩‍👧👨‍👩‍👧`,
      `${'b'.repeat(58)}🇮🇳🇮🇳🇮🇳`,
      `${'c'.repeat(57)}ত্রত্রত্রত্র`,
    ];
    for (const title of samples) {
      assert.ok(clusters(title).length > PUSH_TITLE_MAX && title.length <= 120, title);
      const cut = pushTitle(title);
      const parts = clusters(cut);
      assert.equal(parts.length, PUSH_TITLE_MAX, title);
      assert.equal(parts.at(-1), '…');
      // Every kept cluster is a whole cluster of the original title.
      assert.ok(title.startsWith(parts.slice(0, -1).join('')), title);
      assert.deepEqual(parts.slice(0, -1), clusters(title).slice(0, PUSH_TITLE_MAX - 1));
    }
    const task = await createTask(f.admin.auth, { title: samples[0], assigneeId: f.member.id });
    const [push] = await taskPushes('task_assigned');
    assert.equal(push.id, task.id);
    assert.equal(push.messages[0].body, pushTitle(samples[0]));
  });
});
