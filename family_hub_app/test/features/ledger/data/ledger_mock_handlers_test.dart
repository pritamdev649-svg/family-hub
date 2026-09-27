import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/features/ledger/data/ledger_mock_handlers.dart';
import 'package:family_hub/shared/json.dart';

RequestOptions _req(
  String method,
  String path, {
  Object? data,
  Map<String, dynamic>? query,
  String userId = MockSeed.amitUserId,
}) => RequestOptions(
  method: method,
  baseUrl: MockBackend.baseUrl,
  path: path,
  data: data,
  queryParameters: query,
  headers: {'Authorization': 'Bearer ${MockRequest.accessTokenFor(userId)}'},
);

Future<MockException> _error(Future<Object?> f) async {
  try {
    await f;
  } on MockException catch (e) {
    return e;
  }
  fail('expected a MockException');
}

/// Gives Aarav (a member without an account in the core seed) a login so
/// member-visibility rules can be exercised.
const _aaravUserId = '64f1a0000000000000000199';

void _addAaravAccount(MockDb db) {
  db.insert(MockDb.users, {
    'id': _aaravUserId,
    'email': 'aarav@familyhub.app',
    'password': 'demo1234',
    'name': 'Aarav Sharma',
    'emailVerified': true,
    'familyId': MockSeed.familyId,
    'memberId': MockSeed.aaravMemberId,
  });
  db.update(MockDb.members, MockSeed.aaravMemberId, {'userId': _aaravUserId});
}

String _today() => DateTime.now().startOfDay.toApiDate();

void main() {
  late MockBackend b;

  setUp(() {
    b = MockBackend();
    registerLedgerMocks(b);
    _addAaravAccount(b.db);
  });

  Future<MockResponse> call(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    String userId = MockSeed.amitUserId,
  }) => b.handle(_req(method, path, data: data, query: query, userId: userId));

  group('seed', () {
    test('two months of INR entries and the Goa goal', () async {
      final entries = b.db.col(MockDb.ledgerEntries);
      expect(entries.length, greaterThan(30));
      final months = {
        for (final e in entries)
          calendarDate(MockDb.parse(e['date']))!.monthKey,
      };
      final now = DateTime.now();
      expect(months, {
        now.monthKey,
        DateTime(now.year, now.month).addMonths(-1).monthKey,
      });
      // Nothing lies in the future.
      for (final e in entries) {
        expect(
          calendarDate(MockDb.parse(e['date']))!.isAfter(now),
          isFalse,
          reason: '${e['note']}',
        );
      }

      final goals = (await call('GET', '/goals')).data! as List;
      expect(goals, hasLength(1));
      final goa = goals.single as Map;
      expect(goa['title'], 'Goa vacation');
      expect(goa['targetAmount'], 60000);
      expect(goa['savedAmount'], 12500);
      expect(goa['progress'], 0.2083);
      expect(goa['status'], 'active');
    });

    test('does not seed families other than the demo family', () {
      final empty = MockBackend(MockDb(seedCore: false));
      registerLedgerMocks(empty);
      expect(empty.db.col(MockDb.ledgerEntries), isEmpty);
      expect(empty.db.col(MockDb.goals), isEmpty);
    });
  });

  group('GET /ledger/entries', () {
    test('admin sees every entry, newest date first, paginated', () async {
      final res = await call('GET', '/ledger/entries', query: {'limit': '5'});
      final items = res.data! as List;
      expect(items, hasLength(5));
      expect(res.meta!['hasMore'], isTrue);
      expect(res.meta!['total'], b.db.count(MockDb.ledgerEntries));
      final dates = [for (final e in items) (e as Map)['date'] as String];
      expect([...dates]..sort((a, c) => c.compareTo(a)), dates);
      // Contract shape: major units, no internal fields.
      final first = items.first as Map;
      expect(first.containsKey('amountMinor'), isFalse);
      expect(first.containsKey('familyId'), isFalse);
      expect(first['amount'], isA<num>());
    });

    test('member sees only own or self-created entries', () async {
      // Priya records one for herself and Amit records one for Aarav.
      final res = await call(
        'GET',
        '/ledger/entries',
        query: {'limit': '100'},
        userId: _aaravUserId,
      );
      final items = (res.data! as List).cast<Map>();
      expect(items, isNotEmpty);
      for (final e in items) {
        expect(
          e['memberId'] == MockSeed.aaravMemberId ||
              e['createdById'] == MockSeed.aaravMemberId,
          isTrue,
        );
      }
    });

    test('filters by month, type, member and goal', () async {
      final month = DateTime.now().monthKey;
      final res = await call(
        'GET',
        '/ledger/entries',
        query: {'month': month, 'type': 'income', 'limit': '100'},
      );
      final items = (res.data! as List).cast<Map>();
      expect(items, isNotEmpty);
      expect(items.every((e) => e['type'] == 'income'), isTrue);

      final byGoal = await call(
        'GET',
        '/ledger/entries',
        query: {'goalId': mockGoaGoalId},
      );
      final contributions = (byGoal.data! as List).cast<Map>();
      expect(contributions, hasLength(2));
      expect(contributions.every((e) => e['category'] == 'savings'), isTrue);

      final byMember = await call(
        'GET',
        '/ledger/entries',
        query: {'memberId': MockSeed.kamlaMemberId, 'limit': '100'},
      );
      expect(
        (byMember.data! as List).cast<Map>().every(
          (e) => e['memberId'] == MockSeed.kamlaMemberId,
        ),
        isTrue,
      );
    });

    test('invalid month / type → 422', () async {
      expect(
        (await _error(
          call('GET', '/ledger/entries', query: {'month': '2026-13'}),
        )).code,
        'VALIDATION_ERROR',
      );
      expect(
        (await _error(
          call('GET', '/ledger/entries', query: {'type': 'x'}),
        )).status,
        422,
      );
    });
  });

  group('POST/PATCH/DELETE /ledger/entries', () {
    Map<String, dynamic> body({
      String type = 'expense',
      Object amount = 250.5,
      String category = 'groceries',
      String? date,
      Object? memberId,
    }) => {
      'type': type,
      'amount': amount,
      'category': category,
      'date': date ?? _today(),
      'note': '  Veg  ',
      'memberId': ?memberId,
    };

    test('creates an entry for the caller', () async {
      final res = await call('POST', '/ledger/entries', data: body());
      expect(res.status, 201);
      final e = res.data! as Map;
      expect(e['amount'], 250.5);
      expect(e['note'], 'Veg');
      expect(e['memberId'], MockSeed.amitMemberId);
      expect(e['memberName'], 'Amit');
      expect(e['createdById'], MockSeed.amitMemberId);
      expect(e['goalId'], isNull);
    });

    test('validates type/category, amount and date', () async {
      final e = await _error(
        call(
          'POST',
          '/ledger/entries',
          data: body(
            type: 'income',
            category: 'groceries',
            amount: 0,
            date: DateTime.now().add(const Duration(days: 3)).toApiDate(),
          ),
        ),
      );
      expect(e.status, 422);
      // Like the backend: body-format problems are reported first, the
      // date window (a service rule) only once the body is well-formed.
      expect(e.details!.keys, unorderedEquals(['category', 'amount']));
      expect(
        (await _error(
          call('POST', '/ledger/entries', data: body(amount: 2e12)),
        )).details!['amount'],
        isNotNull,
      );
      final future = await _error(
        call(
          'POST',
          '/ledger/entries',
          data: body(
            date: DateTime.now().add(const Duration(days: 3)).toApiDate(),
          ),
        ),
      );
      expect(future.details!.keys, ['date']);
      final tooOld = await _error(
        call(
          'POST',
          '/ledger/entries',
          data: body(date: DateTime(1999, 12, 31).toApiDate()),
        ),
      );
      expect(tooOld.details!.keys, ['date']);
      final missing = await _error(
        call('POST', '/ledger/entries', data: {'type': 'expense'}),
      );
      expect(
        missing.details!.keys,
        containsAll(['amount', 'category', 'date']),
      );
    });

    test('check order: 403 for a member beats the date window', () async {
      final e = await _error(
        call(
          'POST',
          '/ledger/entries',
          data: body(
            memberId: MockSeed.amitMemberId,
            date: DateTime.now().add(const Duration(days: 5)).toApiDate(),
          ),
          userId: _aaravUserId,
        ),
      );
      expect(e.status, 403);
    });

    test('tomorrow is allowed (clock skew)', () async {
      final tomorrow = DateTime.now().add(const Duration(days: 1)).toApiDate();
      final res = await call(
        'POST',
        '/ledger/entries',
        data: body(date: tomorrow),
      );
      expect(res.status, 201);
    });

    test('admin may record for another member; member only for self', () async {
      final res = await call(
        'POST',
        '/ledger/entries',
        data: body(memberId: MockSeed.kamlaMemberId),
      );
      expect((res.data! as Map)['memberName'], 'Kamla');

      final e = await _error(
        call(
          'POST',
          '/ledger/entries',
          data: body(memberId: MockSeed.amitMemberId),
          userId: _aaravUserId,
        ),
      );
      expect(e.code, 'FORBIDDEN');

      // Unknown / other-family member → 422 details.memberId, never 404
      // (backend: would leak other families' ids).
      final other = await _error(
        call(
          'POST',
          '/ledger/entries',
          data: body(memberId: 'ffffffffffffffffffffffff'),
        ),
      );
      expect(other.status, 422);
      expect(other.details!['memberId'], isNotNull);

      final malformed = await _error(
        call('POST', '/ledger/entries', data: body(memberId: 'nope')),
      );
      expect(malformed.status, 422);
      expect(malformed.details!['memberId'], isNotNull);
    });

    test('memberName is the current name; removed members keep the '
        'snapshot', () async {
      final created = await call(
        'POST',
        '/ledger/entries',
        data: body(memberId: MockSeed.kamlaMemberId),
      );
      final id = (created.data! as Map)['id'];
      b.db.update(MockDb.members, MockSeed.kamlaMemberId, {
        'name': 'Kamla Devi',
      });
      Future<Map> find() async {
        final list =
            (await call(
                  'GET',
                  '/ledger/entries',
                  query: {'memberId': MockSeed.kamlaMemberId},
                )).data!
                as List;
        return list.cast<Map>().firstWhere((e) => e['id'] == id);
      }

      expect((await find())['memberName'], 'Kamla Devi');
      b.db.remove(MockDb.members, MockSeed.kamlaMemberId);
      expect((await find())['memberName'], 'Kamla');
    });

    test('malformed ids are 400; malformed query ids are 422', () async {
      final bad = await _error(call('DELETE', '/ledger/entries/not-an-id'));
      expect(bad.status, 400);
      expect(bad.code, 'BAD_REQUEST');
      final badPatch = await _error(
        call('PATCH', '/ledger/entries/123', data: {'note': 'x'}),
      );
      expect(badPatch.status, 400);
      final badGoal = await _error(
        call('POST', '/goals/xyz/contributions', data: {'amount': 1}),
      );
      expect(badGoal.status, 400);
      final badQuery = await _error(
        call('GET', '/ledger/entries', query: {'memberId': 'x', 'goalId': 'y'}),
      );
      expect(badQuery.status, 422);
      expect(badQuery.details!.keys, containsAll(['memberId', 'goalId']));
    });

    test('PATCH: bad body is 422 before 404; unknown member is 422', () async {
      final e = await _error(
        call(
          'PATCH',
          '/ledger/entries/ffffffffffffffffffffffff',
          data: {'amount': -5},
        ),
      );
      expect(e.status, 422);

      final created = await call('POST', '/ledger/entries', data: body());
      final id = (created.data! as Map)['id'];
      final gone = await _error(
        call(
          'PATCH',
          '/ledger/entries/$id',
          data: {'memberId': 'ffffffffffffffffffffffff'},
        ),
      );
      expect(gone.status, 422);
      expect(gone.details!['memberId'], isNotNull);
      final nullMember = await _error(
        call('PATCH', '/ledger/entries/$id', data: {'memberId': null}),
      );
      expect(nullMember.status, 422);
    });

    test('PATCH: admin or creator; hidden entries are 404', () async {
      final created = await call('POST', '/ledger/entries', data: body());
      final id = (created.data! as Map)['id'] as String;

      final updated = await call(
        'PATCH',
        '/ledger/entries/$id',
        data: {'amount': 300, 'note': null, 'category': 'dining'},
      );
      final e = updated.data! as Map;
      expect(e['amount'], 300);
      expect(e['note'], isNull);
      expect(e['category'], 'dining');

      // Aarav cannot see Amit's own entry → 404 (never leak it).
      final hidden = await _error(
        call(
          'PATCH',
          '/ledger/entries/$id',
          data: {'amount': 1},
          userId: _aaravUserId,
        ),
      );
      expect(hidden.status, 404);

      // Aarav sees an entry that is his but created by Amit → 403.
      final forAarav = await call(
        'POST',
        '/ledger/entries',
        data: body(memberId: MockSeed.aaravMemberId),
      );
      final forbidden = await _error(
        call(
          'DELETE',
          '/ledger/entries/${(forAarav.data! as Map)['id']}',
          userId: _aaravUserId,
        ),
      );
      expect(forbidden.status, 403);

      // Changing the type requires a category valid for it.
      final mismatch = await _error(
        call('PATCH', '/ledger/entries/$id', data: {'type': 'income'}),
      );
      expect(mismatch.details!['category'], isNotNull);
    });

    test('goal-linked amount cannot change; other fields can', () async {
      final linked =
          (await call(
                'GET',
                '/ledger/entries',
                query: {'goalId': mockGoaGoalId},
              )).data!
              as List;
      final entry = linked.first as Map;
      final e = await _error(
        call('PATCH', '/ledger/entries/${entry['id']}', data: {'amount': 1}),
      );
      expect(e.details!['amount'], isNotNull);

      final ok = await call(
        'PATCH',
        '/ledger/entries/${entry['id']}',
        data: {'amount': entry['amount'], 'note': 'Renamed'},
      );
      expect((ok.data! as Map)['note'], 'Renamed');

      // Type and category are locked too (a contribution stays
      // expense/savings), like the backend.
      final retyped = await _error(
        call(
          'PATCH',
          '/ledger/entries/${entry['id']}',
          data: {'type': 'income', 'category': 'gift'},
        ),
      );
      expect(retyped.details!.keys, containsAll(['type', 'category']));
      final recategorised = await _error(
        call(
          'PATCH',
          '/ledger/entries/${entry['id']}',
          data: {'category': 'groceries'},
        ),
      );
      expect(recategorised.details!['category'], isNotNull);
    });

    test('deleting a contribution lowers the goal and reopens it', () async {
      // Complete the goal first.
      final res = await call(
        'POST',
        '/goals/$mockGoaGoalId/contributions',
        data: {'amount': 47500},
      );
      expect(((res.data! as Map)['goal'] as Map)['status'], 'achieved');
      final entryId = ((res.data! as Map)['entry'] as Map)['id'];

      await call('DELETE', '/ledger/entries/$entryId');
      final goal = (await call('GET', '/goals')).data! as List;
      final g = goal.single as Map;
      expect(g['savedAmount'], 12500);
      expect(g['status'], 'active');
    });

    test('other family ids are 404', () async {
      final e = await _error(
        call('DELETE', '/ledger/entries/ffffffffffffffffffffffff'),
      );
      expect(e.code, 'NOT_FOUND');
    });
  });

  group('GET /ledger/summary', () {
    test('admin gets the family scope with category totals', () async {
      final month = DateTime.now().monthKey;
      final s =
          (await call('GET', '/ledger/summary', query: {'month': month})).data!
              as Map;
      expect(s['month'], month);
      expect(s['currency'], 'INR');
      expect(s['scope'], 'family');
      expect(s['income'], greaterThanOrEqualTo(205000));
      expect(
        s['net'],
        closeTo((s['income'] as num) - (s['expense'] as num), 0.001),
      );
      final cats = (s['byCategory'] as List).cast<Map>();
      final amounts = [for (final c in cats) c['amount'] as num];
      expect([...amounts]..sort((a, c) => c.compareTo(a)), amounts);
      final expenseSum = cats
          .where((c) => c['type'] == 'expense')
          .fold<num>(0, (sum, c) => sum + (c['amount'] as num));
      expect(expenseSum, closeTo(s['expense'] as num, 0.001));
    });

    test('member gets the personal scope', () async {
      final s =
          (await call('GET', '/ledger/summary', userId: _aaravUserId)).data!
              as Map;
      expect(s['scope'], 'personal');
      // Aarav's own entries only: pocket money (+ a movie if already seeded).
      expect(s['income'], 1000);
    });

    test('defaults to the current month; rejects bad months', () async {
      final s = (await call('GET', '/ledger/summary')).data! as Map;
      expect(s['month'], DateTime.now().monthKey);
      for (final bad in ['sept', '2026-13', '2026-9']) {
        expect(
          (await _error(
            call('GET', '/ledger/summary', query: {'month': bad}),
          )).status,
          422,
          reason: bad,
        );
      }
    });

    test('equal category totals: income first, then by category', () async {
      final month = DateTime(2020, 5).monthKey;
      final date = DateTime(2020, 5, 10).toApiDate();
      for (final (type, category) in [
        ('expense', 'rent'),
        ('income', 'salary'),
        ('expense', 'dining'),
      ]) {
        await call(
          'POST',
          '/ledger/entries',
          data: {
            'type': type,
            'amount': 500,
            'category': category,
            'date': date,
          },
        );
      }
      final s =
          (await call('GET', '/ledger/summary', query: {'month': month})).data!
              as Map;
      expect(
        [for (final c in (s['byCategory'] as List).cast<Map>()) c['category']],
        ['salary', 'dining', 'rent'],
      );
    });

    test('an empty month is all zeros', () async {
      final s =
          (await call(
                'GET',
                '/ledger/summary',
                query: {'month': '2001-01'},
              )).data!
              as Map;
      expect(s['income'], 0);
      expect(s['expense'], 0);
      expect(s['net'], 0);
      expect(s['byCategory'], isEmpty);
    });
  });

  group('/goals', () {
    test('admin creates, edits and deletes; members may not', () async {
      final created = await call(
        'POST',
        '/goals',
        data: {'title': ' Laptop for Aarav ', 'targetAmount': 55000},
      );
      expect(created.status, 201);
      final goal = created.data! as Map;
      expect(goal['title'], 'Laptop for Aarav');
      expect(goal['savedAmount'], 0);
      expect(goal['progress'], 0);

      final forbidden = await _error(
        call(
          'POST',
          '/goals',
          data: {'title': 'x', 'targetAmount': 1},
          userId: _aaravUserId,
        ),
      );
      expect(forbidden.code, 'FORBIDDEN');

      final invalid = await _error(
        call('POST', '/goals', data: {'title': '', 'targetAmount': -1}),
      );
      expect(invalid.details!.keys, containsAll(['title', 'targetAmount']));

      final patched = await call(
        'PATCH',
        '/goals/${goal['id']}',
        data: {'targetAmount': 50000, 'targetDate': null},
      );
      expect((patched.data! as Map)['targetAmount'], 50000);

      await call('DELETE', '/goals/${goal['id']}');
      final list = (await call('GET', '/goals')).data! as List;
      expect(list.map((g) => (g as Map)['id']), isNot(contains(goal['id'])));
    });

    test('status filter and ordering (active first)', () async {
      final created = await call(
        'POST',
        '/goals',
        data: {'title': 'Old fund', 'targetAmount': 1000},
      );
      final id = (created.data! as Map)['id'];
      await call('PATCH', '/goals/$id', data: {'status': 'archived'});

      final all = (await call('GET', '/goals')).data! as List;
      expect(all.map((g) => (g as Map)['status']), ['active', 'archived']);
      final archived =
          (await call('GET', '/goals', query: {'status': 'archived'})).data!
              as List;
      expect(archived, hasLength(1));
      expect(
        (await _error(call('GET', '/goals', query: {'status': 'done'}))).status,
        422,
      );
    });

    test(
      'contribution creates a savings expense and achieves the goal',
      () async {
        final res = await call(
          'POST',
          '/goals/$mockGoaGoalId/contributions',
          data: {'amount': 50000, 'note': 'Diwali bonus'},
          userId: _aaravUserId,
        );
        expect(res.status, 201);
        final data = res.data! as Map;
        final entry = data['entry'] as Map;
        expect(entry['type'], 'expense');
        expect(entry['category'], 'savings');
        expect(entry['goalId'], mockGoaGoalId);
        expect(entry['memberId'], MockSeed.aaravMemberId);
        final goal = data['goal'] as Map;
        expect(goal['savedAmount'], 62500);
        expect(goal['status'], 'achieved');
        expect(goal['progress'], 1);
      },
    );

    test(
      'archived goals reject contributions; restoring re-derives status',
      () async {
        await call(
          'PATCH',
          '/goals/$mockGoaGoalId',
          data: {'status': 'archived'},
        );
        final e = await _error(
          call(
            'POST',
            '/goals/$mockGoaGoalId/contributions',
            data: {'amount': 10},
          ),
        );
        expect(e.status, 409);
        expect(e.code, 'VALIDATION_ERROR');

        final restored = await call(
          'PATCH',
          '/goals/$mockGoaGoalId',
          data: {'status': 'active', 'targetAmount': 10000},
        );
        // Saved 12,500 ≥ new target → achieved.
        expect((restored.data! as Map)['status'], 'achieved');
      },
    );

    test(
      'goal writes: admin check, then 400 id, then 422 body, then 404',
      () async {
        // A member is refused before anything else is looked at.
        final member = await _error(
          call(
            'PATCH',
            '/goals/bad-id',
            data: {'title': ''},
            userId: _aaravUserId,
          ),
        );
        expect(member.status, 403);
        expect(
          (await _error(
            call('PATCH', '/goals/bad-id', data: {'title': 'x'}),
          )).status,
          400,
        );
        final invalid = await _error(
          call(
            'PATCH',
            '/goals/ffffffffffffffffffffffff',
            data: {'title': null, 'status': 'done'},
          ),
        );
        expect(invalid.status, 422);
        expect(invalid.details!.keys, containsAll(['title', 'status']));
        expect(
          (await _error(
            call(
              'PATCH',
              '/goals/ffffffffffffffffffffffff',
              data: {'title': 'x'},
            ),
          )).status,
          404,
        );
        expect(
          (await _error(
            call('DELETE', '/goals/ffffffffffffffffffffffff'),
          )).code,
          'NOT_FOUND',
        );
      },
    );

    test('contributions: 422 body before 404; date window applies', () async {
      final bad = await _error(
        call(
          'POST',
          '/goals/ffffffffffffffffffffffff/contributions',
          data: {'amount': 0},
        ),
      );
      expect(bad.status, 422);
      expect(
        (await _error(
          call(
            'POST',
            '/goals/ffffffffffffffffffffffff/contributions',
            data: {'amount': 5},
          ),
        )).status,
        404,
      );
      final future = await _error(
        call(
          'POST',
          '/goals/$mockGoaGoalId/contributions',
          data: {
            'amount': 5,
            'date': DateTime.now().add(const Duration(days: 4)).toApiDate(),
          },
        ),
      );
      expect(future.details!.keys, ['date']);
      // Members contribute too; the entry is theirs.
      final res = await call(
        'POST',
        '/goals/$mockGoaGoalId/contributions',
        data: {'amount': 5, 'note': '  Pocket money  '},
        userId: _aaravUserId,
      );
      final entry = (res.data! as Map)['entry'] as Map;
      expect(entry['memberId'], MockSeed.aaravMemberId);
      expect(entry['note'], 'Pocket money');
      expect(entry['category'], 'savings');
    });

    test('deleting a goal keeps its entries, detached', () async {
      await call('DELETE', '/goals/$mockGoaGoalId');
      final linked = b.db.where(
        MockDb.ledgerEntries,
        (e) => e['category'] == 'savings',
      );
      expect(linked, hasLength(2));
      expect(linked.every((e) => e['goalId'] == null), isTrue);
    });
  });
}
