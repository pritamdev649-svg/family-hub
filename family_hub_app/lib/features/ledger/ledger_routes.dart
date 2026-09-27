import 'package:go_router/go_router.dart';

import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/presentation/screens/entries_screen.dart';
import 'package:family_hub/features/ledger/presentation/screens/entry_form_screen.dart';
import 'package:family_hub/features/ledger/presentation/screens/goal_detail_screen.dart';
import 'package:family_hub/features/ledger/presentation/screens/goal_form_screen.dart';

/// Full-screen routes of the Money feature (registered top-level by
/// `goRouterProvider`; the `/money` tab itself is a shell branch).
///
/// Static segments come before parameter segments (`/money/goals/new`
/// before `/money/goals/:id`).
List<RouteBase> get ledgerRoutes => [
  GoRoute(
    path: AppRoutes.ledgerEntries,
    builder: (context, state) => const EntriesScreen(),
  ),
  GoRoute(
    path: AppRoutes.ledgerEntryNewPath,
    builder: (context, state) {
      // Edit mode: the entry travels as `extra` (the contract has no
      // `GET /ledger/entries/:id`, so an edit route could not load it).
      final extra = state.extra;
      final entry = extra is LedgerEntry ? extra : null;
      return EntryFormScreen(
        entry: entry,
        initialType: LedgerType.tryFromWire(
          state.uri.queryParameters[AppRoutes.typeQuery],
        ),
      );
    },
  ),
  GoRoute(
    path: AppRoutes.goalNew,
    builder: (context, state) => const GoalFormScreen(),
  ),
  GoRoute(
    path: AppRoutes.goalDetailPath,
    builder: (context, state) =>
        GoalDetailScreen(goalId: state.pathParameters[AppRoutes.idParam] ?? ''),
  ),
  GoRoute(
    path: AppRoutes.goalEditPath,
    builder: (context, state) =>
        GoalFormScreen(goalId: state.pathParameters[AppRoutes.idParam] ?? ''),
  ),
];
