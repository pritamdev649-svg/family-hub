import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/widgets/colorful.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/features/dashboard/application/dashboard_providers.dart';
import 'package:family_hub/features/dashboard/data/dashboard_cache.dart';
import 'package:family_hub/features/dashboard/presentation/widgets/dashboard_getting_started.dart';
import 'package:family_hub/features/dashboard/presentation/widgets/dashboard_offline_notice.dart';
import 'package:family_hub/features/dashboard/presentation/widgets/dashboard_skeleton.dart';
import 'package:family_hub/features/ledger/presentation/widgets/goal_progress_card.dart';
import 'package:family_hub/features/ledger/presentation/widgets/month_summary_card.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_card.dart';
import 'package:family_hub/features/sos/domain/sos_alert.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_alert_tile.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_tile.dart';

import 'dashboard_test_utils.dart';

void main() {
  late FakeDashboardRepository repository;

  Future<void> pump(
    WidgetTester tester, {
    List<Object>? responses,
    List<SosAlert>? liveSos,
    Size size = const Size(400, 3200),
    TextDirection? textDirection,
    double? textScale,
    bool settle = true,
    Future<void> Function(DashboardCache cache)? seedCache,
  }) async {
    useSurface(tester, size);
    repository = FakeDashboardRepository(responses);
    final prefs = await mockPrefs();
    if (seedCache != null) await seedCache(DashboardCache(LocalCache(prefs)));
    await pumpDashboard(
      tester,
      overrides: dashboardOverrides(
        repository: repository,
        prefs: prefs,
        liveSos: liveSos,
      ),
      textDirection: textDirection,
      textScale: textScale,
      settle: settle,
    );
  }

  testWidgets('shows every section of a populated dashboard', (tester) async {
    await pump(tester);

    // Greeting (09:30 → morning) with the first name, family + designation.
    expect(find.text('Good morning, Amit'), findsOneWidget);
    expect(find.text('Sharma Family · Head of Family'), findsOneWidget);

    // Quick actions.
    for (final label in [
      'Add task',
      'Add expense',
      'Post notice',
      'Emergency cards',
    ]) {
      expect(find.widgetWithText(ActionTile, label), findsOneWidget);
    }

    // My tasks (reusing TaskTile).
    expect(find.text('My tasks'), findsOneWidget);
    expect(find.byType(TaskTile), findsNWidgets(2));
    expect(find.text('Pay electricity bill'), findsOneWidget);

    // Family board with counters.
    expect(find.text('Family board'), findsOneWidget);
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('Chief Study Officer'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('2 pending'), findsOneWidget);
    expect(find.text('1 overdue'), findsOneWidget);
    expect(find.text('3 done this week'), findsOneWidget);
    expect(find.text('All clear'), findsOneWidget, reason: 'Aarav');

    // Goals, month, notices (reusing the feature widgets).
    expect(find.byType(GoalProgressCard), findsOneWidget);
    expect(find.text('Goa vacation'), findsOneWidget);
    expect(find.byType(MonthSummaryCard), findsOneWidget);
    expect(find.byType(NoticeCard), findsOneWidget);
    expect(find.text('Family meeting Sunday 7pm'), findsOneWidget);

    // Not shown: SOS section, getting-started card, offline notice.
    expect(find.text('Needs help now'), findsNothing);
    expect(find.byType(DashboardGettingStarted), findsNothing);
    expect(find.byType(DashboardOfflineNotice), findsNothing);
    expect(repository.calls, 1);
  });

  testWidgets('active SOS alerts come first', (tester) async {
    await pump(
      tester,
      responses: [
        dashboardData(dashboardJson(activeSos: [sosJson()])),
      ],
    );
    expect(find.text('Needs help now'), findsOneWidget);
    expect(find.byType(SosAlertTile), findsOneWidget);
    expect(find.text('Priya needs help'), findsOneWidget);

    final sosY = tester.getTopLeft(find.byType(SosAlertTile)).dy;
    final actionsY = tester.getTopLeft(find.text('Add task')).dy;
    final tasksY = tester.getTopLeft(find.text('My tasks')).dy;
    expect(sosY, lessThan(actionsY));
    expect(sosY, lessThan(tasksY));
  });

  testWidgets('the live SOS list wins over the dashboard snapshot', (
    tester,
  ) async {
    await pump(
      tester,
      responses: [
        dashboardData(dashboardJson(activeSos: [sosJson()])),
      ],
      liveSos: const [],
    );
    expect(find.byType(SosAlertTile), findsNothing);
  });

  testWidgets('new family: getting-started checklist and empty sections', (
    tester,
  ) async {
    await pump(
      tester,
      responses: [
        dashboardData(
          dashboardJson(
            members: [statsJson(memberJson())],
            myTasks: const [],
            goals: const [],
            notices: const [],
          ),
        ),
      ],
    );

    expect(find.byType(DashboardGettingStarted), findsOneWidget);
    expect(find.text('Add your family members'), findsOneWidget);
    expect(find.text('Set a savings goal'), findsOneWidget);
    expect(find.text("You're all caught up"), findsOneWidget);
    expect(find.text('No active goals'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'New goal'), findsOneWidget);
    expect(find.text('No notices yet'), findsOneWidget);

    await tester.tap(find.text('Add your family members'));
    await tester.pumpAndSettle();
    expect(find.text('route:/members/new'), findsOneWidget);
  });

  testWidgets('members see no admin-only actions', (tester) async {
    await pump(
      tester,
      responses: [
        dashboardData(
          dashboardJson(
            me: memberJson(role: 'member', designation: null),
            members: [
              statsJson(memberJson(role: 'member', designation: null)),
              statsJson(memberJson(id: 'm-2', userId: 'u-2', name: 'Priya')),
            ],
            myTasks: const [],
            goals: const [],
            notices: const [],
            monthSummary: summaryJson(scope: 'personal'),
          ),
        ),
      ],
    );

    expect(find.text('Sharma Family · Member'), findsOneWidget);
    expect(find.text('Set a savings goal'), findsNothing);
    expect(find.text('Add your family members'), findsNothing);
    expect(find.text('Create the first task'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'New goal'), findsNothing);
    expect(
      find.text('When a family admin sets a savings goal, it shows up here.'),
      findsOneWidget,
    );
    expect(find.text('Personal'), findsOneWidget);
  });

  testWidgets('shows the skeleton while loading', (tester) async {
    final gate = Completer<DashboardData>();
    await pump(tester, responses: [gate], settle: false);
    await tester.pump();
    expect(find.byType(DashboardSkeleton), findsOneWidget);
    expect(
      find.bySemanticsLabel('Loading your family dashboard…'),
      findsOneWidget,
    );

    gate.complete(dashboardData());
    await tester.pumpAndSettle();
    expect(find.byType(DashboardSkeleton), findsNothing);
    expect(find.text('Good morning, Amit'), findsOneWidget);
  });

  testWidgets('an error offers retry', (tester) async {
    await pump(
      tester,
      responses: [
        const ApiException(code: ApiErrorCode.forbidden, statusCode: 403),
        dashboardData(),
      ],
    );
    expect(find.text('Something went wrong'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Good morning, Amit'), findsOneWidget);
    expect(repository.calls, 2);
  });

  testWidgets('offline start shows the saved copy with a notice', (
    tester,
  ) async {
    await pump(
      tester,
      responses: [const ApiException.network(), dashboardData()],
      seedCache: (cache) => cache.write(testUserId, dashboardData()),
    );

    expect(find.byType(DashboardOfflineNotice), findsOneWidget);
    expect(find.text('Showing saved data'), findsOneWidget);
    expect(find.textContaining('Pull down to refresh'), findsOneWidget);
    expect(find.text('Good morning, Amit'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(DashboardOfflineNotice),
        matching: find.text('Retry'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DashboardOfflineNotice), findsNothing);
    expect(repository.calls, 2);
  });

  testWidgets('pull to refresh reloads the dashboard', (tester) async {
    // A phone-sized viewport: the pull distance is relative to its height.
    await pump(tester, size: const Size(400, 800));
    expect(repository.calls, 1);

    await tester.fling(
      find.text('Good morning, Amit'),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
  });

  group('navigation', () {
    Future<void> tapAndExpect(
      WidgetTester tester,
      Finder target,
      String location,
    ) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('route:$location'), findsOneWidget);
    }

    testWidgets('quick action: add task', (tester) async {
      await pump(tester);
      await tapAndExpect(tester, find.text('Add task'), '/tasks/new');
    });

    testWidgets('quick action: add expense', (tester) async {
      await pump(tester);
      await tapAndExpect(
        tester,
        find.text('Add expense'),
        '/money/entries/new?type=expense',
      );
    });

    testWidgets('quick action: emergency cards', (tester) async {
      await pump(tester);
      await tapAndExpect(
        tester,
        find.text('Emergency cards'),
        '/emergency-cards',
      );
    });

    testWidgets('my tasks "See all" opens the Tasks tab', (tester) async {
      await pump(tester);
      await tapAndExpect(tester, find.text('See all').first, '/tasks');
    });

    testWidgets('a member card opens the member', (tester) async {
      await pump(tester);
      await tapAndExpect(tester, find.text('Priya Sharma'), '/members/m-priya');
    });

    testWidgets('notices "See all" opens the notice board', (tester) async {
      await pump(tester);
      await tapAndExpect(tester, find.text('See all').last, '/notices');
    });

    testWidgets('more pending tasks than shown link to the Tasks tab', (
      tester,
    ) async {
      await pump(
        tester,
        responses: [
          dashboardData(
            dashboardJson(
              members: [statsJson(memberJson(), pending: 8)],
              myTasks: [
                for (var i = 0; i < 5; i++)
                  taskJson(id: 't$i', title: 'Task $i'),
              ],
            ),
          ),
        ],
      );
      expect(find.byType(TaskTile), findsNWidgets(5));
      await tapAndExpect(tester, find.text('3 more pending tasks'), '/tasks');
    });
  });

  group('responsive layout', () {
    double memberTop(WidgetTester tester, String id) =>
        tester.getTopLeft(find.byKey(ValueKey('dashboard-member-$id'))).dy;

    testWidgets('one column on phones', (tester) async {
      await pump(tester, size: const Size(360, 3200));
      expect(
        memberTop(tester, 'm-priya'),
        greaterThan(memberTop(tester, testMemberId)),
      );
    });

    testWidgets('two columns on wide screens', (tester) async {
      await pump(tester, size: const Size(1024, 3200));
      expect(memberTop(tester, 'm-priya'), memberTop(tester, testMemberId));
      expect(
        memberTop(tester, 'm-aarav'),
        greaterThan(memberTop(tester, testMemberId)),
      );
      // Quick actions in one row of four.
      double buttonTop(String label) =>
          tester.getTopLeft(find.widgetWithText(ActionTile, label)).dy;
      expect(buttonTop('Emergency cards'), buttonTop('Add task'));
    });

    testWidgets('large text keeps a single column', (tester) async {
      await pump(tester, size: const Size(700, 4000), textScale: 1.6);
      expect(
        memberTop(tester, 'm-priya'),
        greaterThan(memberTop(tester, testMemberId)),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('RTL + large text on a small phone lays out without overflow', (
      tester,
    ) async {
      await pump(
        tester,
        size: const Size(320, 5000),
        textDirection: TextDirection.rtl,
        textScale: 1.6,
        responses: [
          dashboardData(dashboardJson(activeSos: [sosJson()])),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Good morning, Amit'), findsOneWidget);
    });
  });
}
