// The dashboard against the in-memory mock backend with the demo seed and
// the real repositories of every feature (only the session is fixed): all
// sections render from `GET /dashboard`, and completing a task from the
// dashboard refreshes it through the data-change bus.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/network/mock/mock_registry.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/features/dashboard/application/dashboard_providers.dart';
import 'package:family_hub/features/notices/data/notices_mock_handlers.dart';
import 'package:family_hub/features/sos/application/sos_runtime.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_tile.dart';
import 'package:family_hub/shared/models/family.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

import 'dashboard_test_utils.dart';

void main() {
  testWidgets('renders the demo family and refreshes after completing a task', (
    tester,
  ) async {
    useSurface(tester, const Size(420, 5000));
    final backend = MockBackend();
    registerAllMocks(backend);
    final db = backend.db;
    final api = mockApiFor(backend, userId: MockSeed.amitUserId);
    final me = Member.fromJson(
      MockSerializers.member(
        db.findById(MockDb.members, MockSeed.amitMemberId)!,
      ),
    );
    final family = Family.fromJson(
      MockSerializers.family(
        db,
        db.findById(MockDb.families, MockSeed.familyId)!,
        isAdmin: true,
      ),
    );
    final now = DateTime.now();
    final prefs = await mockPrefs();

    await pumpDashboard(
      tester,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        apiClientProvider.overrideWithValue(api),
        sessionUserIdProvider.overrideWithValue(MockSeed.amitUserId),
        currentFamilyProvider.overrideWithValue(family),
        currentMemberProvider.overrideWithValue(me),
        isAdminProvider.overrideWithValue(true),
        fmtProvider.overrideWithValue(dashboardTestFmt()),
        dashboardClockProvider.overrideWithValue(() => now),
        sosClockProvider.overrideWithValue(() => now),
        dashboardLiveSosAlertsProvider.overrideWithValue(null),
        dashboardSessionRefreshProvider.overrideWithValue(() async {}),
      ],
    );

    expect(find.textContaining('Amit'), findsWidgets);
    expect(find.textContaining('Sharma Family'), findsOneWidget);
    // Every demo member on the family board.
    for (final id in MockSeed.memberIds) {
      expect(
        find.byKey(ValueKey('dashboard-member-$id')),
        findsOneWidget,
        reason: id,
      );
    }
    expect(find.text('Goa vacation'), findsOneWidget);
    expect(find.text(mockPinnedNoticeTitle), findsOneWidget);
    expect(tester.takeException(), isNull);

    final pendingBefore = db.count(
      MockDb.tasks,
      (t) =>
          t['assigneeId'] == MockSeed.amitMemberId && t['status'] == 'pending',
    );
    expect(pendingBefore, greaterThan(0), reason: 'demo seed has tasks');
    final tiles = find.byType(TaskTile);
    expect(tiles, findsWidgets);
    final firstTask = tester.widget<TaskTile>(tiles.first).task;

    await tester.tap(
      find.descendant(of: tiles.first, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();

    expect(db.findById(MockDb.tasks, firstTask.id)?['status'], 'done');
    expect(
      find.byKey(ValueKey('dashboard-task-${firstTask.id}')),
      findsNothing,
      reason: 'the dashboard refetched after markChanged({tasks})',
    );
    expect(tester.takeException(), isNull);
  });
}
