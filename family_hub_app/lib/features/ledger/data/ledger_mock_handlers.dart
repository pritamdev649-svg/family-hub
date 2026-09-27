import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/shared/json.dart';

/// Registers the `/ledger` and `/goals` mock routes
/// (docs/03-API_CONTRACT.md §8) and seeds two months of demo entries plus
/// the "Goa vacation" goal for the demo family.
///
/// Mirrors the backend (`family_hub_backend/src/modules/ledger`):
/// * Check order: `401` → `403 NO_FAMILY` → `403 FORBIDDEN` (admin-only goal
///   writes) → `400 BAD_REQUEST` (malformed `:id`) → `422` (malformed body /
///   query) → `404` (not in the family / not visible) → `403` (role) →
///   `422` business rules (date window, member of the family, goal-linked
///   locks). One `422` reports every problem of its stage.
/// * Money is stored in integer minor units (`amountMinor`, `targetMinor`,
///   `savedMinor`) and exposed in major units.
/// * `memberName` is the member's **current** name; entries of removed
///   members keep the stored snapshot.
void registerLedgerMocks(MockBackend b) {
  seedLedgerMockData(b.db);

  b.on('GET', '/ledger/entries', _listEntries);
  b.on('POST', '/ledger/entries', _createEntry);
  b.on('PATCH', '/ledger/entries/:id', _updateEntry);
  b.on('DELETE', '/ledger/entries/:id', _deleteEntry);
  b.on('GET', '/ledger/summary', (req) {
    req.requireMember();
    final month = req.q('month');
    if (month != null && !_isMonthKey(month)) {
      throw const MockException.validation({'month': 'Expected YYYY-MM'});
    }
    return MockResponse.ok(mockLedgerSummary(req, month: month));
  });

  b.on('GET', '/goals', (req) {
    req.requireMember();
    final status = req.q('status') ?? 'all';
    if (!_goalFilters.contains(status)) {
      throw MockException.validation({
        'status': 'Status must be one of: ${_goalFilters.join(', ')}',
      });
    }
    return MockResponse.ok(mockGoalsList(req, status: status));
  });
  b.on('POST', '/goals', _createGoal);
  b.on('PATCH', '/goals/:id', _updateGoal);
  b.on('DELETE', '/goals/:id', _deleteGoal);
  b.on('POST', '/goals/:id/contributions', _contribute);
}

// ── Contract constants ───────────────────────────────────────────────────────

const _types = ['income', 'expense'];

const _incomeCategories = [
  'salary',
  'business',
  'allowance',
  'gift',
  'interest',
  'other_income',
];

const _expenseCategories = [
  'groceries',
  'utilities',
  'rent',
  'education',
  'health',
  'transport',
  'dining',
  'shopping',
  'entertainment',
  'household_help',
  'savings',
  'other_expense',
];

const _allCategories = [..._incomeCategories, ..._expenseCategories];

const _goalStatuses = ['active', 'achieved', 'archived'];
const _goalFilters = [..._goalStatuses, 'all'];

const _noteMax = 200;
const _goalTitleMax = 80;
const _goalDescriptionMax = 1000;

/// Contract maximum: `1e12` major units = `1e14` minor units.
const _maxMinor = 100000000000000;

/// Earliest business day accepted for entries (backend `FIRST_ENTRY_DAY`).
final _firstEntryDay = DateTime(2000);

/// Coarse window for any business date (backend `LEDGER_DATE_MIN/MAX`).
final _coarseDateMin = DateTime.utc(1999, 12, 31);
final _coarseDateMax = DateTime.utc(2101);

/// Stable id of the seeded "Goa vacation" goal.
const mockGoaGoalId = '64f1a0000000000000000501';

final _objectIdPattern = RegExp(r'^[0-9a-fA-F]{24}$');
final _monthPattern = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

List<String> _categoriesFor(String type) =>
    type == 'income' ? _incomeCategories : _expenseCategories;

bool _isMonthKey(String v) => _monthPattern.hasMatch(v);

bool _isObjectId(Object? v) => v is String && _objectIdPattern.hasMatch(v);

// ── Serializers (also used by the dashboard / export mocks) ─────────────────

double _major(Object? minor) => asInt(minor) / 100;

/// Contract `LedgerEntry` for a stored entry document. With [db] the
/// `memberName` is the member's current name (snapshot for removed members),
/// like the backend serializer.
Map<String, dynamic> mockEntryJson(Map<String, dynamic> e, {MockDb? db}) {
  final live = db == null ? '' : MockSerializers.memberName(db, e['memberId']);
  return {
    'id': e['id'],
    'type': e['type'],
    'amount': _major(e['amountMinor']),
    'category': e['category'],
    'note': e['note'],
    'date': e['date'],
    'memberId': e['memberId'],
    'memberName': live.isNotEmpty ? live : e['memberName'],
    'createdById': e['createdById'],
    'goalId': e['goalId'],
    'createdAt': e['createdAt'],
  };
}

/// Fraction saved, truncated to 4 decimals and capped to [0, 1] (backend
/// `progress` virtual).
double _progress(int saved, int target) {
  if (target <= 0) return 0;
  final ratio = saved <= 0 ? 0.0 : saved / target;
  final truncated = (ratio * 10000 + 1e-9).floorToDouble() / 10000;
  return truncated > 1 ? 1 : truncated;
}

/// Contract `SavingsGoal` for a stored goal document.
Map<String, dynamic> mockGoalJson(Map<String, dynamic> g) {
  final saved = asInt(g['savedMinor']);
  final target = asInt(g['targetMinor']);
  return {
    'id': g['id'],
    'title': g['title'],
    'description': g['description'],
    'targetAmount': target / 100,
    'savedAmount': saved / 100,
    'targetDate': g['targetDate'],
    'status': g['status'],
    'progress': _progress(saved, target),
    'createdById': g['createdById'],
    'createdAt': g['createdAt'],
    'updatedAt': g['updatedAt'],
  };
}

/// Goals of the caller's family for `GET /goals?status=` (and the
/// dashboard): active first, then achieved, then archived; newest first
/// within a status.
List<Map<String, dynamic>> mockGoalsList(
  MockRequest req, {
  String status = 'all',
}) {
  final goals = req.familyDocs(
    MockDb.goals,
    (g) => status == 'all' || g['status'] == status,
  );
  int rank(Object? s) => switch (s) {
    'active' => 0,
    'achieved' => 1,
    _ => 2,
  };
  goals.sort((a, b) {
    final r = rank(a['status']).compareTo(rank(b['status']));
    if (r != 0) return r;
    return '${b['createdAt']}'.compareTo('${a['createdAt']}');
  });
  return [for (final g in goals) mockGoalJson(g)];
}

/// `GET /ledger/summary` payload (also the dashboard's `monthSummary`):
/// admins get the family scope, members their personal scope
/// (entries whose `memberId` is theirs). [month] null = current month.
/// `byCategory` is sorted by amount desc, then income first, then category.
Map<String, dynamic> mockLedgerSummary(MockRequest req, {String? month}) {
  final me = req.requireMember();
  final family = req.requireFamily();
  final isAdmin = me['role'] == 'admin';
  final key = month ?? DateTime.now().monthKey;
  if (!_isMonthKey(key)) {
    throw const MockException.validation({'month': 'Expected YYYY-MM'});
  }
  final entries = req.familyDocs(
    MockDb.ledgerEntries,
    (e) => _monthKeyOf(e) == key && (isAdmin || e['memberId'] == me['id']),
  );

  var income = 0;
  var expense = 0;
  final byCategory = <(String, String), int>{};
  for (final e in entries) {
    final minor = asInt(e['amountMinor']);
    final type = e['type'] == 'income' ? 'income' : 'expense';
    if (type == 'income') {
      income += minor;
    } else {
      expense += minor;
    }
    final k = (type, '${e['category']}');
    byCategory[k] = (byCategory[k] ?? 0) + minor;
  }
  final categories = byCategory.entries.where((c) => c.value != 0).toList()
    ..sort((a, b) {
      final byAmount = b.value.compareTo(a.value);
      if (byAmount != 0) return byAmount;
      final byType = _types
          .indexOf(a.key.$1)
          .compareTo(_types.indexOf(b.key.$1));
      if (byType != 0) return byType;
      return a.key.$2.compareTo(b.key.$2);
    });

  return {
    'month': key,
    'currency': family['currency'],
    'scope': isAdmin ? 'family' : 'personal',
    'income': income / 100,
    'expense': expense / 100,
    'net': (income - expense) / 100,
    'byCategory': [
      for (final c in categories)
        {'type': c.key.$1, 'category': c.key.$2, 'amount': c.value / 100},
    ],
  };
}

// ── Validation helpers ───────────────────────────────────────────────────────

/// Collects `422` problems (first message per field) so one response
/// reports all of them, like the backend's `ValidationIssues`.
class _Issues {
  final Map<String, String> details = {};

  void add(String field, String message) =>
      details.putIfAbsent(field, () => message);

  bool has(String field) => details.containsKey(field);

  void throwIfAny() {
    if (details.isNotEmpty) throw MockException.validation(details);
  }
}

/// `:id` path parameter; `400 BAD_REQUEST` when it is not an ObjectId
/// (backend `idParams`).
String _pathId(MockRequest req) {
  final id = req.param('id').trim();
  if (!_objectIdPattern.hasMatch(id)) {
    throw const MockException(
      400,
      'BAD_REQUEST',
      'Invalid request parameters',
      {'id': 'Invalid id'},
    );
  }
  return id.toLowerCase();
}

/// Optional ObjectId query value (`422` when malformed).
String? _queryId(MockRequest req, String name, _Issues issues) {
  final v = req.q(name);
  if (v == null) return null;
  if (!_objectIdPattern.hasMatch(v)) {
    issues.add(name, 'Invalid id');
    return null;
  }
  return v.toLowerCase();
}

/// `YYYY-MM` of an entry's business date (calendar day of the date-only
/// value, independent of the viewer's time zone).
String? _monthKeyOf(Map<String, dynamic> e) =>
    calendarDate(MockDb.parse(e['date']))?.monthKey;

bool _isAdmin(Map<String, dynamic> me) => me['role'] == 'admin';

/// Members see entries that are theirs or that they created.
bool _visibleTo(Map<String, dynamic> me, Map<String, dynamic> e) =>
    _isAdmin(me) || e['memberId'] == me['id'] || e['createdById'] == me['id'];

/// Money in minor units (backend `moneyAmount`: a JSON number, > 0,
/// ≤ 1e12, at least 0.01 after rounding), or null with an issue.
int? _amountMinor(Object? v, String field, _Issues issues) {
  if (v == null) {
    issues.add(field, 'Amount is required');
    return null;
  }
  if (v is! num || !v.isFinite) {
    issues.add(field, 'Amount must be a number');
    return null;
  }
  if (v <= 0) {
    issues.add(field, 'Amount must be greater than 0');
    return null;
  }
  final minor = (v * 100).round();
  if (minor > _maxMinor) {
    issues.add(field, 'Amount is too large');
    return null;
  }
  if (minor < 1) {
    issues.add(field, 'Amount must be at least 0.01');
    return null;
  }
  return minor;
}

/// Trimmed optional text (null / blank → null) with a max length.
String? _optionalText(Object? v, String field, int max, _Issues issues) {
  if (v == null) return null;
  if (v is! String) {
    issues.add(field, 'Must be text');
    return null;
  }
  final t = v.trim();
  if (t.isEmpty) return null;
  if (t.length > max) {
    issues.add(field, 'Must be at most $max characters');
    return null;
  }
  return t;
}

/// A business date (`YYYY-MM-DD` or ISO date-time) inside the coarse
/// 2000–2100 window (backend `businessDate`), or null with an issue.
DateTime? _businessDate(Object? v, String field, _Issues issues) {
  final parsed = v is String ? DateTime.tryParse(v.trim()) : null;
  if (parsed == null) {
    issues.add(field, v == null ? 'Date is required' : 'Invalid date');
    return null;
  }
  final utc = parsed.toUtc();
  if (utc.isBefore(_coarseDateMin) || !utc.isBefore(_coarseDateMax)) {
    issues.add(field, 'Date must be between 2000 and 2100');
    return null;
  }
  return parsed;
}

/// Service-level entry-date window: 1 Jan 2000 … tomorrow (contract:
/// `date ≤ today + 1 day`). Returns the stored ISO value, or null with an
/// issue.
String? _entryDateInWindow(DateTime date, String field, _Issues issues) {
  final day = calendarDate(date)!;
  final max = DateTime.now().startOfDay.add(const Duration(days: 1));
  if (day.isAfter(max)) {
    issues.add(field, 'Date cannot be later than tomorrow');
    return null;
  }
  if (day.isBefore(_firstEntryDay)) {
    issues.add(field, 'Date cannot be before 1 January 2000');
    return null;
  }
  return MockDb.iso(date);
}

/// Member [id] of the caller's family, or null (never 404: that would leak
/// whether an id exists in another family).
Map<String, dynamic>? _familyMember(MockRequest req, String id) {
  final m = req.db.findById(MockDb.members, id);
  return m != null && m['familyId'] == req.familyId ? m : null;
}

void _memberNotInFamily(_Issues issues) =>
    issues.add('memberId', 'Member must belong to your family');

/// Recomputes `status` / `achievedAt` of a non-archived goal from its saved
/// amount (saved ≥ target → achieved, else active).
Map<String, dynamic> _deriveStatus(Map<String, dynamic> goal, String nowIso) {
  if (goal['status'] == 'archived') return const {};
  final achieved = asInt(goal['savedMinor']) >= asInt(goal['targetMinor']);
  if (achieved) {
    return {'status': 'achieved', 'achievedAt': goal['achievedAt'] ?? nowIso};
  }
  return {'status': 'active', 'achievedAt': null};
}

// ── Entries ──────────────────────────────────────────────────────────────────

MockResponse _listEntries(MockRequest req) {
  final me = req.requireMember();
  final issues = _Issues();
  final month = req.q('month');
  if (month != null && !_isMonthKey(month)) {
    issues.add('month', 'Expected YYYY-MM');
  }
  final type = req.q('type');
  if (type != null && !_types.contains(type)) {
    issues.add('type', 'Type must be one of: ${_types.join(', ')}');
  }
  final memberId = _queryId(req, 'memberId', issues);
  final goalId = _queryId(req, 'goalId', issues);
  // Pagination is validated with the rest of the query.
  try {
    req.page;
    req.limit;
  } on MockException catch (e) {
    for (final entry in (e.details ?? const {}).entries) {
      issues.add(entry.key, '${entry.value}');
    }
  }
  issues.throwIfAny();

  final entries = req.familyDocs(
    MockDb.ledgerEntries,
    (e) =>
        _visibleTo(me, e) &&
        (month == null || _monthKeyOf(e) == month) &&
        (type == null || e['type'] == type) &&
        (memberId == null || e['memberId'] == memberId) &&
        (goalId == null || e['goalId'] == goalId),
  );
  entries.sort((a, b) {
    final byDate = '${b['date']}'.compareTo('${a['date']}');
    if (byDate != 0) return byDate;
    return '${b['createdAt']}'.compareTo('${a['createdAt']}');
  });
  return MockResponse.paged([
    for (final e in entries) mockEntryJson(e, db: req.db),
  ], req);
}

MockResponse _createEntry(MockRequest req) {
  final me = req.requireMember();
  final body = req.body;

  // 1. Body format (zod-level `createEntryBody`).
  final format = _Issues();
  final type = body['type'];
  if (type == null) {
    format.add('type', 'Type is required');
  } else if (!_types.contains(type)) {
    format.add('type', 'Type must be one of: ${_types.join(', ')}');
  }
  final amount = _amountMinor(body['amount'], 'amount', format);
  final category = body['category'];
  if (category == null) {
    format.add('category', 'Category is required');
  } else if (!_allCategories.contains(category)) {
    format.add('category', 'Unknown category');
  } else if (type is String &&
      _types.contains(type) &&
      !_categoriesFor(type).contains(category)) {
    format.add('category', 'Category "$category" is not valid for $type');
  }
  final note = _optionalText(body['note'], 'note', _noteMax, format);
  final date = _businessDate(body['date'], 'date', format);
  final requested = body['memberId'];
  if (requested != null && !_isObjectId(requested)) {
    format.add('memberId', 'Invalid id');
  }
  format.throwIfAny();

  // 2. Role, then business rules.
  final issues = _Issues();
  var owner = me;
  final requestedId = (requested as String?)?.toLowerCase();
  if (requestedId != null && requestedId != me['id']) {
    if (!_isAdmin(me)) {
      throw const MockException.forbidden(
        'Members can only record money for themselves',
      );
    }
    final member = _familyMember(req, requestedId);
    if (member == null) {
      _memberNotInFamily(issues);
    } else {
      owner = member;
    }
  }
  final storedDate = _entryDateInWindow(date!, 'date', issues);
  issues.throwIfAny();

  final entry = req.db.insert(MockDb.ledgerEntries, {
    'familyId': me['familyId'],
    'type': type,
    'amountMinor': amount,
    'category': category,
    'note': note,
    'date': storedDate,
    'memberId': owner['id'],
    'memberName': owner['name'],
    'createdById': me['id'],
    'goalId': null,
  });
  return MockResponse.created(mockEntryJson(entry, db: req.db));
}

/// The entry [id] if the caller may see it (404 otherwise) and change it
/// (403 unless admin or creator).
Map<String, dynamic> _modifiableEntry(
  MockRequest req,
  Map<String, dynamic> me,
  String id,
) {
  final entry = req.findInFamily(MockDb.ledgerEntries, id);
  if (!_visibleTo(me, entry)) throw const MockException.notFound();
  if (!_isAdmin(me) && entry['createdById'] != me['id']) {
    throw const MockException.forbidden();
  }
  return entry;
}

MockResponse _updateEntry(MockRequest req) {
  final me = req.requireMember();
  final id = _pathId(req);
  final body = req.body;

  // 1. Body format (zod-level `updateEntryBody`: every key optional, only
  //    `note` may be null).
  final format = _Issues();
  final hasType = body.containsKey('type');
  final newType = body['type'];
  if (hasType && !_types.contains(newType)) {
    format.add('type', 'Type must be one of: ${_types.join(', ')}');
  }
  int? newAmount;
  if (body.containsKey('amount')) {
    newAmount = _amountMinor(body['amount'], 'amount', format);
  }
  final hasCategory = body.containsKey('category');
  final newCategory = body['category'];
  if (hasCategory && !_allCategories.contains(newCategory)) {
    format.add('category', 'Unknown category');
  } else if (hasCategory &&
      hasType &&
      _types.contains(newType) &&
      !_categoriesFor('$newType').contains(newCategory)) {
    format.add('category', 'Category "$newCategory" is not valid for $newType');
  }
  final hasNote = body.containsKey('note');
  final note = _optionalText(body['note'], 'note', _noteMax, format);
  DateTime? newDate;
  if (body.containsKey('date')) {
    newDate = _businessDate(body['date'], 'date', format);
  }
  final hasMember = body.containsKey('memberId');
  final requested = body['memberId'];
  if (hasMember && !_isObjectId(requested)) {
    format.add('memberId', 'Invalid member');
  }
  format.throwIfAny();

  // 2. Existence / visibility (404), then role (403).
  final entry = _modifiableEntry(req, me, id);

  // 3. Business rules.
  final issues = _Issues();
  final patch = <String, dynamic>{};

  final requestedId = (requested as String?)?.toLowerCase();
  if (hasMember && requestedId != entry['memberId']) {
    if (!_isAdmin(me) && requestedId != me['id']) {
      throw const MockException.forbidden(
        'Members can only record money for themselves',
      );
    }
    final owner = _familyMember(req, requestedId!);
    if (owner == null) {
      _memberNotInFamily(issues);
    } else {
      patch['memberId'] = owner['id'];
      patch['memberName'] = owner['name'];
    }
  }

  final type = hasType ? '$newType' : '${entry['type']}';
  final category = hasCategory ? '$newCategory' : '${entry['category']}';
  if (entry['goalId'] != null) {
    if (newAmount != null && newAmount != asInt(entry['amountMinor'])) {
      issues.add(
        'amount',
        'The amount of a goal contribution cannot be changed. Delete it and '
            'contribute again.',
      );
    }
    if (type != entry['type']) {
      issues.add('type', 'A goal contribution is always an expense');
    }
    if (category != entry['category']) {
      issues.add(
        'category',
        'A goal contribution always uses the "savings" category',
      );
    }
  } else if (newAmount != null) {
    patch['amountMinor'] = newAmount;
  }
  if (!issues.has('type') &&
      !issues.has('category') &&
      !_categoriesFor(type).contains(category)) {
    issues.add('category', 'Category "$category" is not valid for $type');
  }
  if (type != entry['type'] || category != entry['category']) {
    patch['type'] = type;
    patch['category'] = category;
  }
  if (hasNote) patch['note'] = note;
  if (newDate != null) {
    final stored = _entryDateInWindow(newDate, 'date', issues);
    if (stored != null) patch['date'] = stored;
  }
  issues.throwIfAny();

  final updated = patch.isEmpty
      ? entry
      : req.db.update(MockDb.ledgerEntries, entry['id'] as String, patch)!;
  return MockResponse.ok(mockEntryJson(updated, db: req.db));
}

MockResponse _deleteEntry(MockRequest req) {
  final me = req.requireMember();
  final entry = _modifiableEntry(req, me, _pathId(req));
  req.db.remove(MockDb.ledgerEntries, entry['id'] as String);

  final goal = req.db.findById(MockDb.goals, entry['goalId']);
  if (goal != null && goal['familyId'] == entry['familyId']) {
    final saved = asInt(goal['savedMinor']) - asInt(entry['amountMinor']);
    final next = {...goal, 'savedMinor': saved < 0 ? 0 : saved};
    req.db.update(MockDb.goals, goal['id'] as String, {
      'savedMinor': next['savedMinor'],
      // Reopen the goal when it drops below target.
      ..._deriveStatus(next, req.db.nowIso()),
    });
  }
  return const MockResponse.ok();
}

// ── Goals ────────────────────────────────────────────────────────────────────

String? _goalTitle(Object? v, _Issues issues) {
  if (v == null) {
    issues.add('title', 'Title is required');
    return null;
  }
  if (v is! String) {
    issues.add('title', 'Title must be text');
    return null;
  }
  final t = v.trim();
  if (t.isEmpty) {
    issues.add('title', 'Title is required');
    return null;
  }
  if (t.length > _goalTitleMax) {
    issues.add('title', 'Title must be at most $_goalTitleMax characters');
    return null;
  }
  return t;
}

/// Optional business date for `targetDate` (`null` clears it).
String? _optionalDate(Object? v, String field, _Issues issues) {
  if (v == null || (v is String && v.trim().isEmpty)) return null;
  final parsed = _businessDate(v, field, issues);
  return parsed == null ? null : MockDb.iso(parsed);
}

MockResponse _createGoal(MockRequest req) {
  final me = req.requireAdmin();
  final body = req.body;
  final issues = _Issues();
  final title = _goalTitle(body['title'], issues);
  final description = _optionalText(
    body['description'],
    'description',
    _goalDescriptionMax,
    issues,
  );
  final target = _amountMinor(body['targetAmount'], 'targetAmount', issues);
  final targetDate = _optionalDate(body['targetDate'], 'targetDate', issues);
  issues.throwIfAny();

  final goal = req.db.insert(MockDb.goals, {
    'familyId': me['familyId'],
    'title': title,
    'description': description,
    'targetMinor': target,
    'savedMinor': 0,
    'targetDate': targetDate,
    'status': 'active',
    'createdById': me['id'],
    'achievedAt': null,
  });
  return MockResponse.created(mockGoalJson(goal));
}

MockResponse _updateGoal(MockRequest req) {
  req.requireAdmin();
  final id = _pathId(req);
  final body = req.body;
  final issues = _Issues();
  final patch = <String, dynamic>{};

  if (body.containsKey('title')) {
    patch['title'] = _goalTitle(body['title'], issues);
  }
  if (body.containsKey('description')) {
    patch['description'] = _optionalText(
      body['description'],
      'description',
      _goalDescriptionMax,
      issues,
    );
  }
  if (body.containsKey('targetAmount')) {
    patch['targetMinor'] = _amountMinor(
      body['targetAmount'],
      'targetAmount',
      issues,
    );
  }
  if (body.containsKey('targetDate')) {
    patch['targetDate'] = _optionalDate(
      body['targetDate'],
      'targetDate',
      issues,
    );
  }
  if (body.containsKey('status')) {
    final status = body['status'];
    if (status is! String || !_goalStatuses.contains(status)) {
      issues.add(
        'status',
        'Status must be one of: ${_goalStatuses.join(', ')}',
      );
    } else {
      patch['status'] = status;
    }
  }
  issues.throwIfAny();

  final goal = req.findInFamily(MockDb.goals, id);
  // `achieved` follows the saved amount: restoring / changing the target
  // re-derives it (an admin cannot mark an unfinished goal achieved).
  final next = {...goal, ...patch};
  final now = req.db.nowIso();
  final updated = req.db.update(MockDb.goals, goal['id'] as String, {
    ...patch,
    ..._deriveStatus(next, now),
  })!;
  return MockResponse.ok(mockGoalJson(updated));
}

MockResponse _deleteGoal(MockRequest req) {
  req.requireAdmin();
  final goal = req.findInFamily(MockDb.goals, _pathId(req));
  final id = goal['id'] as String;
  req.db.remove(MockDb.goals, id);
  // Linked entries stay in the ledger, detached from the goal.
  req.db.updateWhere(MockDb.ledgerEntries, (e) => e['goalId'] == id, {
    'goalId': null,
  });
  return const MockResponse.ok();
}

MockResponse _contribute(MockRequest req) {
  final me = req.requireMember();
  final id = _pathId(req);
  final body = req.body;

  final format = _Issues();
  final amount = _amountMinor(body['amount'], 'amount', format);
  final note = _optionalText(body['note'], 'note', _noteMax, format);
  final rawDate = body['date'];
  final hasDate = rawDate != null && !(rawDate is String && rawDate.isEmpty);
  final date = hasDate ? _businessDate(rawDate, 'date', format) : null;
  format.throwIfAny();

  final goal = req.findInFamily(MockDb.goals, id);
  if (goal['status'] == 'archived') {
    // Contract: "409 CONFLICT-style VALIDATION_ERROR" (backend
    // `goalArchivedError`).
    throw const MockException(409, 'VALIDATION_ERROR', 'Goal is archived', {
      'goalId': 'This goal is archived',
    });
  }
  final issues = _Issues();
  final storedDate = date == null
      ? MockDb.iso(DateTime.now().startOfDay)
      : _entryDateInWindow(date, 'date', issues);
  issues.throwIfAny();

  final entry = req.db.insert(MockDb.ledgerEntries, {
    'familyId': me['familyId'],
    'type': 'expense',
    'amountMinor': amount,
    'category': 'savings',
    'note': note,
    'date': storedDate,
    'memberId': me['id'],
    'memberName': me['name'],
    'createdById': me['id'],
    'goalId': goal['id'],
  });

  final saved = asInt(goal['savedMinor']) + amount!;
  final next = {...goal, 'savedMinor': saved};
  final updated = req.db.update(MockDb.goals, goal['id'] as String, {
    'savedMinor': saved,
    ..._deriveStatus(next, req.db.nowIso()),
  })!;
  return MockResponse.created({
    'goal': mockGoalJson(updated),
    'entry': mockEntryJson(entry, db: req.db),
  });
}

// ── Seed ─────────────────────────────────────────────────────────────────────

/// Seeds realistic INR entries for the previous and the current month and
/// the "Goa vacation" goal (target ₹60,000, ₹12,500 saved through two
/// linked contributions) for the demo "Sharma Family". No-op for databases
/// without the demo family. [now] is injectable for tests.
void seedLedgerMockData(MockDb db, {DateTime? now}) {
  final hasDemoFamily = db.findById(MockDb.families, MockSeed.familyId) != null;
  final clock = (now ?? DateTime.now()).toLocal();
  final seed = hasDemoFamily ? _buildSeed(clock) : null;
  db.seedOnce(MockDb.goals, () => seed?.goals ?? const []);
  db.seedOnce(MockDb.ledgerEntries, () => seed?.entries ?? const []);
}

class _Seed {
  const _Seed(this.entries, this.goals);

  final List<Map<String, dynamic>> entries;
  final List<Map<String, dynamic>> goals;
}

_Seed _buildSeed(DateTime now) {
  const amit = MockSeed.amitMemberId;
  const priya = MockSeed.priyaMemberId;
  const aarav = MockSeed.aaravMemberId;
  const anaya = MockSeed.anayaMemberId;
  const kamla = MockSeed.kamlaMemberId;
  const names = {
    amit: 'Amit',
    priya: 'Priya',
    aarav: 'Aarav',
    anaya: 'Anaya',
    kamla: 'Kamla',
  };

  final entries = <Map<String, dynamic>>[];
  var sequence = 0;

  /// [monthOffset] 0 = current month, -1 = previous; days of the current
  /// month are clamped to today so nothing lies in the future.
  void add(
    int monthOffset,
    int day,
    String type,
    String category,
    num amount, {
    required String member,
    String? createdBy,
    String? note,
    String? goalId,
  }) {
    final first = DateTime(now.year, now.month).addMonths(monthOffset);
    final lastDay = monthOffset == 0
        ? now.day
        : DateTime(first.year, first.month + 1, 0).day;
    final date = DateTime(
      first.year,
      first.month,
      day > lastDay ? lastDay : day,
    );
    sequence++;
    var created = date.add(Duration(hours: 9, minutes: sequence * 7 % 60));
    if (created.isAfter(now)) {
      created = now.subtract(Duration(minutes: 90 - sequence));
    }
    final createdIso = MockDb.iso(created);
    entries.add({
      'familyId': MockSeed.familyId,
      'type': type,
      'amountMinor': (amount * 100).round(),
      'category': category,
      'note': note,
      'date': MockDb.iso(date),
      'memberId': member,
      'memberName': names[member],
      'createdById': createdBy ?? member,
      'goalId': goalId,
      'createdAt': createdIso,
      'updatedAt': createdIso,
    });
  }

  // Previous month — a complete month.
  add(-1, 1, 'income', 'salary', 120000, member: amit, note: 'Monthly salary');
  add(-1, 1, 'income', 'salary', 85000, member: priya, note: 'Monthly salary');
  add(-1, 2, 'expense', 'rent', 28000, member: amit, note: 'House rent');
  add(
    -1,
    3,
    'expense',
    'household_help',
    6000,
    member: priya,
    note: 'Sunita didi – cleaning',
  );
  add(
    -1,
    3,
    'expense',
    'household_help',
    5000,
    member: priya,
    note: 'Cook – monthly',
  );
  add(
    -1,
    5,
    'expense',
    'groceries',
    3240,
    member: priya,
    note: 'Online grocery order',
  );
  add(
    -1,
    5,
    'expense',
    'education',
    18500,
    member: amit,
    note: "Aarav's school fees – term 2",
  );
  add(
    -1,
    7,
    'expense',
    'utilities',
    2340,
    member: amit,
    note: 'Electricity bill',
  );
  add(-1, 8, 'expense', 'utilities', 999, member: amit, note: 'Broadband');
  add(
    -1,
    10,
    'income',
    'allowance',
    1000,
    member: aarav,
    createdBy: amit,
    note: 'Pocket money',
  );
  add(
    -1,
    12,
    'expense',
    'groceries',
    2450,
    member: priya,
    note: 'Vegetables & fruits',
  );
  add(-1, 12, 'expense', 'transport', 3500, member: amit, note: 'Petrol');
  add(
    -1,
    14,
    'expense',
    'health',
    850,
    member: kamla,
    createdBy: priya,
    note: "Kamla ji's medicines",
  );
  add(
    -1,
    15,
    'expense',
    'savings',
    7500,
    member: amit,
    note: 'Goa trip – first saving',
    goalId: mockGoaGoalId,
  );
  add(
    -1,
    18,
    'expense',
    'dining',
    1850,
    member: priya,
    note: 'Family dinner out',
  );
  add(
    -1,
    20,
    'expense',
    'groceries',
    1875,
    member: priya,
    note: 'Monthly ration',
  );
  add(-1, 21, 'income', 'interest', 1240, member: amit, note: 'FD interest');
  add(
    -1,
    22,
    'expense',
    'entertainment',
    649,
    member: amit,
    note: 'Streaming subscription',
  );
  add(
    -1,
    24,
    'expense',
    'shopping',
    4999,
    member: priya,
    note: "Anaya's school shoes & bag",
  );
  add(
    -1,
    26,
    'expense',
    'utilities',
    599,
    member: priya,
    note: 'Mobile recharge',
  );
  add(
    -1,
    27,
    'income',
    'gift',
    2000,
    member: anaya,
    createdBy: priya,
    note: 'Gift from Nani',
  );
  add(
    -1,
    28,
    'expense',
    'groceries',
    2210,
    member: priya,
    note: 'Weekly groceries',
  );

  // Current month — up to today.
  add(0, 1, 'income', 'salary', 120000, member: amit, note: 'Monthly salary');
  add(0, 1, 'income', 'salary', 85000, member: priya, note: 'Monthly salary');
  add(0, 2, 'expense', 'rent', 28000, member: amit, note: 'House rent');
  add(
    0,
    3,
    'expense',
    'household_help',
    6000,
    member: priya,
    note: 'Sunita didi – cleaning',
  );
  add(
    0,
    3,
    'expense',
    'household_help',
    5000,
    member: priya,
    note: 'Cook – monthly',
  );
  add(
    0,
    4,
    'expense',
    'groceries',
    2980,
    member: priya,
    note: 'Online grocery order',
  );
  add(
    0,
    5,
    'expense',
    'utilities',
    2515,
    member: amit,
    note: 'Electricity bill',
  );
  add(
    0,
    6,
    'expense',
    'education',
    3200,
    member: amit,
    note: "Aarav's maths tuition",
  );
  add(0, 8, 'expense', 'transport', 3200, member: amit, note: 'Petrol');
  add(
    0,
    9,
    'income',
    'allowance',
    1000,
    member: aarav,
    createdBy: amit,
    note: 'Pocket money',
  );
  add(
    0,
    10,
    'expense',
    'savings',
    5000,
    member: priya,
    note: 'Goa trip',
    goalId: mockGoaGoalId,
  );
  add(
    0,
    11,
    'expense',
    'groceries',
    1640,
    member: priya,
    note: 'Vegetables & fruits',
  );
  add(
    0,
    13,
    'expense',
    'health',
    1200,
    member: kamla,
    createdBy: priya,
    note: 'Kamla ji – check-up',
  );
  add(0, 15, 'expense', 'dining', 980, member: amit, note: 'Weekend chaat');
  add(
    0,
    16,
    'income',
    'business',
    12000,
    member: priya,
    note: 'Home bakery orders',
  );
  add(
    0,
    18,
    'expense',
    'groceries',
    2320,
    member: priya,
    note: 'Weekly groceries',
  );
  add(
    0,
    20,
    'expense',
    'entertainment',
    450,
    member: aarav,
    createdBy: amit,
    note: 'Movie with friends',
  );
  add(0, 22, 'expense', 'utilities', 999, member: amit, note: 'Broadband');
  add(
    0,
    24,
    'expense',
    'shopping',
    3499,
    member: amit,
    note: 'Festival decorations',
  );

  final savedMinor = entries
      .where((e) => e['goalId'] == mockGoaGoalId)
      .fold<int>(0, (sum, e) => sum + asInt(e['amountMinor']));
  final created = MockDb.iso(
    DateTime(
      now.year,
      now.month,
    ).addMonths(-1).add(const Duration(days: 13, hours: 10)),
  );
  final goals = [
    {
      'id': mockGoaGoalId,
      'familyId': MockSeed.familyId,
      'title': 'Goa vacation',
      'description': 'Family trip to Goa during the winter holidays.',
      'targetMinor': 6000000,
      'savedMinor': savedMinor,
      'targetDate': MockDb.iso(DateTime(now.year, now.month + 5, 15)),
      'status': 'active',
      'createdById': amit,
      'achievedAt': null,
      'createdAt': created,
      'updatedAt': created,
    },
  ];
  return _Seed(entries, goals);
}
