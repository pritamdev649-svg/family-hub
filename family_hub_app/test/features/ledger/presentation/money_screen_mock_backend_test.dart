import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/features/ledger/presentation/screens/money_screen.dart';
import 'package:family_hub/features/ledger/presentation/widgets/goal_progress_card.dart';
import 'package:family_hub/features/ledger/presentation/widgets/ledger_entry_tile.dart';
import 'package:family_hub/features/ledger/presentation/widgets/money_header.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

import '../ledger_test_utils.dart';

/// The Money tab end to end: real repositories → ApiClient → envelope →
/// in-memory mock backend with the seeded demo ledger.
void main() {
  testWidgets('shows the seeded demo month for the admin', (tester) async {
    useTallSurface(tester);
    final mock = mockLedgerApi();
    final amit = testMember(id: MockSeed.amitMemberId, name: 'Amit');

    await pumpLedgerApp(
      tester,
      const MoneyScreen(),
      overrides: [
        fmtProvider.overrideWithValue(ledgerTestFmt()),
        apiClientProvider.overrideWithValue(mock.api),
        sessionUserIdProvider.overrideWithValue(MockSeed.amitUserId),
        currentMemberProvider.overrideWithValue(amit),
        isAdminProvider.overrideWithValue(true),
        membersProvider.overrideWith((ref) async => <Member>[amit]),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.byType(MoneyHeader), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    // Expense bars are shown first (income needs the toggle).
    expect(find.text('Salary'), findsNothing);
    expect(find.text('Household help'), findsOneWidget);

    expect(find.byType(GoalProgressCard), findsOneWidget);
    expect(find.text('Goa vacation'), findsOneWidget);
    final fmt = ledgerTestFmt();
    expect(
      find.text('${fmt.money(12500)} of ${fmt.money(60000)}'),
      findsOneWidget,
    );

    expect(find.byType(LedgerEntryTile), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
