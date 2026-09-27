import 'package:family_hub/core/network/mock/mock_backend.dart';

/// Registers the `/tasks` mock routes (docs/03-API_CONTRACT.md §7) and seeds
/// the demo family's tasks. Mirrors `family_hub_backend/src/modules/tasks`:
///
/// * `GET /tasks?assigneeId=&status=pending|done|all&due=overdue|today|week`
///   — paginated; `pending` → `dueDate` asc (no due date last) then
///   `createdAt`; `done` → `completedAt` desc; `all` → pending first.
///   Blank values count as "not given"; `status` defaults to `all`; a
///   malformed `assigneeId` → `422`. "Today" / "this week" (Monday-based) /
///   "overdue" are evaluated in the **device's local time** (approximation of
///   the family time zone used by the server). Overdue only matches pending
///   tasks.
/// * `POST /tasks` — `422` body → `422 details.assigneeId` (not in the
///   family) → `403` (a member assigning someone else).
/// * `PATCH /tasks/:id` — `400` id → `422` body → `404` → `403` (admin or
///   creator) → assignee rules **only when the assignee changes**.
/// * `DELETE /tasks/:id` — admin or creator.
/// * `POST /tasks/:id/complete|reopen` — assignee or admin, idempotent;
///   reopening a done task whose assignee left the family → `422
///   details.assigneeId`.
/// * Another family's task → `404 NOT_FOUND`; malformed id → `400`.
/// * `assigneeName` / `createdByName` are the members' current names, `null`
///   for members who left the family (like the backend serializer).
void registerTaskMocks(MockBackend b) {
  _ensureSeeded(b.db);

  b.on('GET', '/tasks', (req) {
    _ensureSeeded(req.db);
    req.requireMember();
    final status = _enumQuery(req, 'status', _listStatuses) ?? 'all';
    final due = _enumQuery(req, 'due', _dueFilters);
    final assigneeId = req.q('assigneeId');
    if (assigneeId != null && !_objectId.hasMatch(assigneeId)) {
      throw const MockException.validation({'assigneeId': 'Invalid id'});
    }
    final range = _DayRanges(DateTime.now());

    final docs = req.familyDocs(MockDb.tasks, (t) {
      if (assigneeId != null &&
          '${t['assigneeId']}'.toLowerCase() != assigneeId.toLowerCase()) {
        return false;
      }
      if (status != 'all' && t['status'] != status) return false;
      return due == null || range.matches(due, t);
    })..sort(compareMockTasks);

    return MockResponse.paged([
      for (final t in docs) mockTaskJson(req.db, t),
    ], req);
  });

  b.on('POST', '/tasks', (req) {
    _ensureSeeded(req.db);
    final me = req.requireMember();
    final fields = _validate(req, partial: false);
    final assigneeId = fields['assigneeId'] as String;
    _checkAssigneeInFamily(req, assigneeId);
    _checkMayAssign(me, assigneeId);
    final doc = req.db.insert(MockDb.tasks, {
      'familyId': me['familyId'],
      'title': fields['title'],
      'description': fields['description'],
      'assigneeId': assigneeId,
      'assigneeName': MockSerializers.memberName(req.db, assigneeId),
      'createdById': me['id'],
      'createdByName': me['name'],
      'dueDate': fields['dueDate'],
      'category': fields['category'] ?? 'other',
      'priority': fields['priority'] ?? 'medium',
      'status': 'pending',
      'completedAt': null,
      'completedById': null,
    });
    return MockResponse.created(mockTaskJson(req.db, doc));
  });

  b.on('GET', '/tasks/:id', (req) {
    _ensureSeeded(req.db);
    req.requireMember();
    return MockResponse.ok(mockTaskJson(req.db, _findTask(req)));
  });

  b.on('PATCH', '/tasks/:id', (req) {
    _ensureSeeded(req.db);
    final me = req.requireMember();
    _checkId(req);
    final fields = _validate(req, partial: true);
    final task = _findTask(req);
    if (!_isAdmin(me) && task['createdById'] != me['id']) {
      throw const MockException.forbidden(
        'Only an admin or the creator can change this task',
      );
    }
    final newAssignee = fields['assigneeId'];
    if (newAssignee is String && newAssignee != task['assigneeId']) {
      _checkAssigneeInFamily(req, newAssignee);
      _checkMayAssign(me, newAssignee);
      fields['assigneeName'] = MockSerializers.memberName(req.db, newAssignee);
    } else {
      // Re-sending the current assignee is a no-op (it may have left).
      fields.remove('assigneeId');
    }
    final updated = fields.isEmpty
        ? task
        : req.db.update(MockDb.tasks, task['id'] as String, fields) ?? task;
    return MockResponse.ok(mockTaskJson(req.db, updated));
  });

  b.on('POST', '/tasks/:id/complete', (req) {
    _ensureSeeded(req.db);
    final me = req.requireMember();
    final task = _findTask(req);
    _checkCompleter(me, task);
    if (task['status'] == 'done') {
      return MockResponse.ok(mockTaskJson(req.db, task)); // idempotent
    }
    final updated = req.db.update(MockDb.tasks, task['id'] as String, {
      'status': 'done',
      'completedAt': req.db.nowIso(),
      'completedById': me['id'],
    });
    return MockResponse.ok(mockTaskJson(req.db, updated ?? task));
  });

  b.on('POST', '/tasks/:id/reopen', (req) {
    _ensureSeeded(req.db);
    final me = req.requireMember();
    final task = _findTask(req);
    _checkCompleter(me, task);
    if (task['status'] != 'done') {
      return MockResponse.ok(mockTaskJson(req.db, task)); // idempotent
    }
    // Removing a member deletes their pending tasks, so a done task of a
    // removed member cannot become pending again: re-assign it first.
    if (_familyMember(req, task['assigneeId']) == null) {
      throw const MockException.validation({
        'assigneeId':
            'The person this task was assigned to is no longer in your family',
      });
    }
    final updated = req.db.update(MockDb.tasks, task['id'] as String, {
      'status': 'pending',
      'completedAt': null,
      'completedById': null,
    });
    return MockResponse.ok(mockTaskJson(req.db, updated ?? task));
  });

  b.on('DELETE', '/tasks/:id', (req) {
    _ensureSeeded(req.db);
    final me = req.requireMember();
    final task = _findTask(req);
    if (!_isAdmin(me) && task['createdById'] != me['id']) {
      throw const MockException.forbidden(
        'Only an admin or the creator can change this task',
      );
    }
    req.db.remove(MockDb.tasks, task['id'] as String);
    return const MockResponse.ok();
  });
}

/// Contract `Task` JSON of a stored task document. `assigneeName` /
/// `createdByName` are the **current** names of those members of the task's
/// family, or `null` when the member no longer exists (done tasks outlive
/// removed members; the app shows a placeholder) — exactly like the backend
/// serializer. Also usable by other mock handlers (e.g. the dashboard's
/// `myTasks`, the data export).
Map<String, dynamic> mockTaskJson(MockDb db, Map<String, dynamic> t) {
  String? name(String idKey) {
    final member = db.findById(MockDb.members, t[idKey]);
    if (member == null || member['familyId'] != t['familyId']) return null;
    final current = '${member['name'] ?? ''}'.trim();
    return current.isEmpty ? null : current;
  }

  return {
    'id': t['id'],
    'title': t['title'],
    'description': t['description'],
    'assigneeId': t['assigneeId'],
    'assigneeName': name('assigneeId'),
    'createdById': t['createdById'],
    'createdByName': name('createdById'),
    'dueDate': t['dueDate'],
    'category': t['category'] ?? 'other',
    'priority': t['priority'] ?? 'medium',
    'status': t['status'] ?? 'pending',
    'completedAt': t['completedAt'],
    'completedById': t['completedById'],
    'createdAt': t['createdAt'],
    'updatedAt': t['updatedAt'],
  };
}

/// Contract sort order of task lists: pending first (`dueDate` asc, no due
/// date last, then `createdAt` asc), then done (`completedAt` desc).
int compareMockTasks(Map<String, dynamic> a, Map<String, dynamic> b) {
  final pa = a['status'] != 'done';
  final pb = b['status'] != 'done';
  if (pa != pb) return pa ? -1 : 1;
  DateTime? date(Map<String, dynamic> t, String key) => MockDb.parse(t[key]);
  var c = pa
      ? _nullsLast(date(a, 'dueDate'), date(b, 'dueDate'))
      : _nullsLast(
          date(a, 'completedAt'),
          date(b, 'completedAt'),
          descending: true,
        );
  if (c == 0 && pa) {
    c = _nullsLast(date(a, 'createdAt'), date(b, 'createdAt'));
  }
  return c != 0 ? c : '${a['id']}'.compareTo('${b['id']}');
}

/// Compares two optional dates; missing values always sort last.
int _nullsLast(DateTime? a, DateTime? b, {bool descending = false}) {
  if (a == null || b == null) {
    if (a == b) return 0;
    return a == null ? 1 : -1;
  }
  return descending ? b.compareTo(a) : a.compareTo(b);
}

// ── Seed ────────────────────────────────────────────────────────────────────

/// Demo tasks of the Sharma family with stable ids (so push-style links such
/// as `/tasks/<id>` survive app restarts). Due dates are relative to the day
/// the mock starts: some overdue, some today / this week / later / none, and
/// a few already done.
abstract final class MockTaskSeed {
  static const mathsHomeworkId = '64f1a0000000000000000301';
  static const guitarPracticeId = '64f1a0000000000000000302';
  static const tidyRoomId = '64f1a0000000000000000303';
  static const bedtimeReadingId = '64f1a0000000000000000304';
  static const bpTabletId = '64f1a0000000000000000305';
  static const morningWalkId = '64f1a0000000000000000306';
  static const electricityBillId = '64f1a0000000000000000307';
  static const carInsuranceId = '64f1a0000000000000000308';
  static const groceryListId = '64f1a0000000000000000309';
  static const dentistId = '64f1a0000000000000000310';
  static const sundayDinnerId = '64f1a0000000000000000311';
  static const kitchenTapId = '64f1a0000000000000000312';
  static const scienceProjectId = '64f1a0000000000000000313';
  static const gasRefillId = '64f1a0000000000000000314';

  static List<Map<String, dynamic>> build(DateTime now) {
    // Date-only values: local midnight → UTC, exactly what the app sends.
    String day(int offset) =>
        MockDb.iso(DateTime(now.year, now.month, now.day + offset));
    String ago({int days = 0, int hours = 0}) =>
        MockDb.iso(now.subtract(Duration(days: days, hours: hours)));

    const names = {
      MockSeed.amitMemberId: 'Amit',
      MockSeed.priyaMemberId: 'Priya',
      MockSeed.aaravMemberId: 'Aarav',
      MockSeed.anayaMemberId: 'Anaya',
      MockSeed.kamlaMemberId: 'Kamla',
    };

    Map<String, dynamic> task({
      required String id,
      required String title,
      String? description,
      required String assignee,
      required String creator,
      String? due,
      required String category,
      required String priority,
      required String createdAt,
      String? completedAt,
      String? completedBy,
    }) => {
      'id': id,
      'familyId': MockSeed.familyId,
      'title': title,
      'description': description,
      'assigneeId': assignee,
      'assigneeName': names[assignee],
      'createdById': creator,
      'createdByName': names[creator],
      'dueDate': due,
      'category': category,
      'priority': priority,
      'status': completedAt == null ? 'pending' : 'done',
      'completedAt': completedAt,
      'completedById': completedAt == null ? null : completedBy,
      'createdAt': createdAt,
      'updatedAt': completedAt ?? createdAt,
    };

    return [
      task(
        id: mathsHomeworkId,
        title: 'Finish maths homework',
        description: 'Chapter 4, exercises 4.1 to 4.3.',
        assignee: MockSeed.aaravMemberId,
        creator: MockSeed.priyaMemberId,
        due: day(0),
        category: 'study',
        priority: 'high',
        createdAt: ago(days: 1),
      ),
      task(
        id: guitarPracticeId,
        title: 'Practise guitar for 30 minutes',
        description: "Work on the chords from Saturday's class.",
        assignee: MockSeed.aaravMemberId,
        creator: MockSeed.amitMemberId,
        due: day(2),
        category: 'skill',
        priority: 'medium',
        createdAt: ago(days: 2),
      ),
      task(
        id: tidyRoomId,
        title: 'Tidy up your room',
        description: 'Toys back in the box and books on the shelf.',
        assignee: MockSeed.anayaMemberId,
        creator: MockSeed.priyaMemberId,
        due: day(-1),
        category: 'chore',
        priority: 'medium',
        createdAt: ago(days: 3),
      ),
      task(
        id: bedtimeReadingId,
        title: 'Read for 20 minutes before bed',
        assignee: MockSeed.anayaMemberId,
        creator: MockSeed.priyaMemberId,
        due: day(0),
        category: 'study',
        priority: 'low',
        createdAt: ago(days: 1),
        completedAt: ago(hours: 1),
        completedBy: MockSeed.priyaMemberId,
      ),
      task(
        id: bpTabletId,
        title: 'Take the evening blood pressure tablet',
        description: 'One tablet after dinner, with water.',
        assignee: MockSeed.kamlaMemberId,
        creator: MockSeed.amitMemberId,
        due: day(0),
        category: 'health',
        priority: 'high',
        createdAt: ago(days: 5),
      ),
      task(
        id: morningWalkId,
        title: 'Morning walk in the park',
        description: '20 minutes, with Priya if possible.',
        assignee: MockSeed.kamlaMemberId,
        creator: MockSeed.amitMemberId,
        due: day(-1),
        category: 'health',
        priority: 'low',
        createdAt: ago(days: 4),
        completedAt: ago(days: 1, hours: 2),
        completedBy: MockSeed.amitMemberId,
      ),
      task(
        id: electricityBillId,
        title: 'Pay the electricity bill',
        description: 'Pay online to avoid the late fee.',
        assignee: MockSeed.amitMemberId,
        creator: MockSeed.priyaMemberId,
        due: day(-3),
        category: 'errand',
        priority: 'high',
        createdAt: ago(days: 7),
      ),
      task(
        id: carInsuranceId,
        title: 'Renew the car insurance',
        assignee: MockSeed.amitMemberId,
        creator: MockSeed.amitMemberId,
        due: day(5),
        category: 'errand',
        priority: 'medium',
        createdAt: ago(days: 6),
      ),
      task(
        id: groceryListId,
        title: 'Plan the weekend grocery list',
        description: 'Check what we need for Sunday lunch.',
        assignee: MockSeed.priyaMemberId,
        creator: MockSeed.priyaMemberId,
        due: day(1),
        category: 'chore',
        priority: 'medium',
        createdAt: ago(days: 2),
      ),
      task(
        id: dentistId,
        title: 'Book a dentist appointment for Anaya',
        assignee: MockSeed.priyaMemberId,
        creator: MockSeed.priyaMemberId,
        category: 'health',
        priority: 'medium',
        createdAt: ago(days: 8),
      ),
      task(
        id: sundayDinnerId,
        title: 'Help cook Sunday dinner',
        assignee: MockSeed.aaravMemberId,
        creator: MockSeed.priyaMemberId,
        due: day(-4),
        category: 'chore',
        priority: 'low',
        createdAt: ago(days: 9),
        completedAt: ago(days: 4, hours: 3),
        completedBy: MockSeed.priyaMemberId,
      ),
      task(
        id: kitchenTapId,
        title: 'Fix the leaking kitchen tap',
        assignee: MockSeed.amitMemberId,
        creator: MockSeed.amitMemberId,
        category: 'chore',
        priority: 'low',
        createdAt: ago(days: 10),
      ),
      task(
        id: scienceProjectId,
        title: 'Science project: solar system model',
        description: 'Poster and model, due at school next week.',
        assignee: MockSeed.aaravMemberId,
        creator: MockSeed.amitMemberId,
        due: day(9),
        category: 'study',
        priority: 'high',
        createdAt: ago(days: 3),
      ),
      task(
        id: gasRefillId,
        title: 'Call the gas agency for a refill',
        assignee: MockSeed.priyaMemberId,
        creator: MockSeed.priyaMemberId,
        due: day(-2),
        category: 'errand',
        priority: 'medium',
        createdAt: ago(days: 6),
        completedAt: ago(days: 2, hours: 5),
        completedBy: MockSeed.priyaMemberId,
      ),
    ];
  }
}

void _ensureSeeded(MockDb db) =>
    db.seedOnce(MockDb.tasks, () => MockTaskSeed.build(DateTime.now()));

// ── Helpers ─────────────────────────────────────────────────────────────────

const _listStatuses = {'pending', 'done', 'all'};
const _dueFilters = {'overdue', 'today', 'week'};
const _categories = {'study', 'chore', 'skill', 'health', 'errand', 'other'};
const _priorities = {'low', 'medium', 'high'};
const _titleMax = 120;
const _descriptionMax = 1000;

final _objectId = RegExp(r'^[0-9a-fA-F]{24}$');

/// Accepted due dates (backend `tasks.schemas.js`): the local calendar days
/// 2000-01-01 … 2100-12-31. Instants are local midnights sent as UTC, so the
/// first day starts up to 14 h before UTC midnight (UTC+14).
final _dueDateMin = DateTime.utc(1999, 12, 31, 10);
final _dueDateMax = DateTime.utc(2101);

/// Text rules of the backend (`toSingleLine` / `toMultiLine` /
/// `hasVisibleText`): runs of control characters in titles become one space;
/// descriptions keep `\n` / `\t` (CRLF / CR → LF) and drop other controls; a
/// title needs one visible character (not only zero-width / format marks).
final _controlRun = RegExp(r'\p{Cc}+', unicode: true);
final _controlExceptTabLf = RegExp(r'[^\P{Cc}\t\n]', unicode: true);
final _visible = RegExp(r'[\p{L}\p{N}\p{S}\p{P}]', unicode: true);

/// Sentinel of [_parseDueDate] for a valid date outside 2000 … 2100.
final _outOfRange = DateTime.utc(0);

/// A full ISO date-time **with** `Z` / offset (what the app sends), or a
/// date-only `YYYY-MM-DD` (→ local midnight, approximating the family time
/// zone). Anything else (no offset, `2026-02-31`, free text) → `null`.
DateTime? _parseDueDate(String v) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})(T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2}))?$',
  ).firstMatch(v);
  if (match == null) return null;
  final y = int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  final d = int.parse(match.group(3)!);
  // Calendar check: DateTime would silently turn 2026-02-31 into March 3rd.
  final day = DateTime.utc(y, m, d);
  if (day.year != y || day.month != m || day.day != d) return null;
  if (match.group(4) == null) {
    // Range-checked on the calendar day (like `new Date('YYYY-MM-DD')`).
    if (day.isBefore(DateTime.utc(2000)) || !day.isBefore(_dueDateMax)) {
      return _outOfRange;
    }
    return DateTime(y, m, d).toUtc();
  }
  return DateTime.tryParse(v)?.toUtc();
}

/// Validated optional enum query value (`422` when not in [allowed]).
String? _enumQuery(MockRequest req, String name, Set<String> allowed) {
  final v = req.q(name);
  if (v == null) return null;
  if (!allowed.contains(v)) {
    throw MockException.validation({name: 'Invalid $name'});
  }
  return v;
}

/// `:id` must be an ObjectId (`400 BAD_REQUEST`, checked before the body
/// like the backend's route validation).
String _checkId(MockRequest req) {
  final id = req.param('id');
  if (!_objectId.hasMatch(id)) {
    throw const MockException.badRequest('Invalid id');
  }
  return id;
}

/// The task of `:id` in the caller's family (`400` malformed id, `404`
/// missing or another family's).
Map<String, dynamic> _findTask(MockRequest req) =>
    req.findInFamily(MockDb.tasks, _checkId(req));

bool _isAdmin(Map<String, dynamic> me) => me['role'] == 'admin';

/// The member [id] of the caller's family, or `null`.
Map<String, dynamic>? _familyMember(MockRequest req, Object? id) {
  final member = id is String ? req.db.findById(MockDb.members, id) : null;
  return member != null && member['familyId'] == req.familyId ? member : null;
}

/// `422 details.assigneeId` unless [assigneeId] is a member of the caller's
/// family (never `404`: that would leak other families' ids).
void _checkAssigneeInFamily(MockRequest req, String assigneeId) {
  if (_familyMember(req, assigneeId) == null) {
    throw const MockException.validation({
      'assigneeId': 'Assignee must be a member of your family',
    });
  }
}

/// `403` unless the caller is an admin or assigns the task to themselves.
void _checkMayAssign(Map<String, dynamic> me, String assigneeId) {
  if (!_isAdmin(me) && assigneeId != me['id']) {
    throw const MockException.forbidden(
      'Members can only assign tasks to themselves',
    );
  }
}

void _checkCompleter(Map<String, dynamic> me, Map<String, dynamic> task) {
  if (!_isAdmin(me) && task['assigneeId'] != me['id']) {
    throw const MockException.forbidden(
      'Only the assignee or an admin can complete or reopen this task',
    );
  }
}

/// Validates the body of `POST /tasks` (all required fields) or `PATCH`
/// ([partial]: only the given fields). Returns the normalised fields to store.
Map<String, dynamic> _validate(MockRequest req, {required bool partial}) {
  final body = req.body;
  final out = <String, dynamic>{};
  final errors = <String, dynamic>{};

  bool has(String key) => body.containsKey(key);

  if (!partial || has('title')) {
    final title = body['title'];
    final trimmed = title is String
        ? title.replaceAll(_controlRun, ' ').trim()
        : null;
    if (trimmed == null || trimmed.isEmpty || !_visible.hasMatch(trimmed)) {
      errors['title'] = 'Title is required';
    } else if (trimmed.length > _titleMax) {
      errors['title'] = 'At most $_titleMax characters';
    } else {
      out['title'] = trimmed;
    }
  }

  if (has('description')) {
    final description = body['description'];
    if (description == null) {
      out['description'] = null;
    } else if (description is! String) {
      errors['description'] = 'Must be text';
    } else {
      final trimmed = description
          .replaceAll(RegExp(r'\r\n?'), '\n')
          .replaceAll(_controlExceptTabLf, '')
          .trim();
      if (trimmed.length > _descriptionMax) {
        errors['description'] = 'At most $_descriptionMax characters';
      } else {
        out['description'] = trimmed.isEmpty ? null : trimmed;
      }
    }
  } else if (!partial) {
    out['description'] = null;
  }

  if (!partial || has('assigneeId')) {
    final assigneeId = body['assigneeId'];
    if (assigneeId == null) {
      errors['assigneeId'] = 'Assignee is required';
    } else if (assigneeId is! String ||
        !_objectId.hasMatch(assigneeId.trim())) {
      errors['assigneeId'] = 'Invalid assignee';
    } else {
      out['assigneeId'] = assigneeId.trim().toLowerCase();
    }
  }

  if (has('dueDate')) {
    final due = body['dueDate'];
    if (due == null || (due is String && due.trim().isEmpty)) {
      out['dueDate'] = null;
    } else {
      final parsed = due is String ? _parseDueDate(due.trim()) : null;
      if (parsed == null) {
        errors['dueDate'] = 'Invalid date';
      } else if (parsed.isBefore(_dueDateMin) ||
          !parsed.isBefore(_dueDateMax)) {
        errors['dueDate'] = 'Due date must be between 2000 and 2100';
      } else {
        out['dueDate'] = MockDb.iso(parsed);
      }
    }
  } else if (!partial) {
    out['dueDate'] = null;
  }

  void enumField(String key, Set<String> allowed) {
    if (!has(key)) return;
    final v = body[key];
    if (v is String && allowed.contains(v)) {
      out[key] = v;
    } else {
      errors[key] = 'Invalid $key';
    }
  }

  enumField('category', _categories);
  enumField('priority', _priorities);

  if (errors.isNotEmpty) throw MockException.validation(errors);
  return out;
}

/// "Today", "this week" (Monday-based) and "overdue" in device local time.
class _DayRanges {
  _DayRanges(DateTime now)
    : startOfToday = DateTime(now.year, now.month, now.day),
      startOfTomorrow = DateTime(now.year, now.month, now.day + 1),
      startOfWeek = DateTime(now.year, now.month, now.day - (now.weekday - 1)),
      startOfNextWeek = DateTime(
        now.year,
        now.month,
        now.day - (now.weekday - 1) + 7,
      );

  final DateTime startOfToday;
  final DateTime startOfTomorrow;
  final DateTime startOfWeek;
  final DateTime startOfNextWeek;

  bool matches(String due, Map<String, dynamic> task) {
    final date = MockDb.parse(task['dueDate']);
    if (date == null) return false;
    bool within(DateTime start, DateTime end) =>
        !date.isBefore(start) && date.isBefore(end);
    return switch (due) {
      'overdue' => task['status'] == 'pending' && date.isBefore(startOfToday),
      'today' => within(startOfToday, startOfTomorrow),
      'week' => within(startOfWeek, startOfNextWeek),
      _ => true,
    };
  }
}
