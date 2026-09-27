import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/storage/local_cache.dart';
import 'package:family_hub/core/utils/url_actions.dart';
import 'package:family_hub/features/emergency_card/application/emergency_card_providers.dart';
import 'package:family_hub/features/emergency_card/data/emergency_card_offline_store.dart';
import 'package:family_hub/features/emergency_card/presentation/screens/emergency_card_responder_screen.dart';
import 'package:family_hub/features/emergency_card/presentation/screens/emergency_card_screen.dart';
import 'package:family_hub/shared/models/member.dart';

import 'emergency_card_test_utils.dart';

/// Edge cases of the emergency card screens (docs/progress/f-emergency.md,
/// "Hardening"): removed members, stale / offline data replaced while a
/// screen is open, permission revoked mid-edit, deep links, rapid taps,
/// very long content with large text in RTL on a small phone.
void main() {
  late FakeEmergencyCardRepository repo;
  late InMemorySecureStore secure;
  late SessionRefreshSpy spy;

  setUp(() {
    repo = FakeEmergencyCardRepository();
    secure = InMemorySecureStore();
    spy = SessionRefreshSpy();
    UrlActions.launcherOverride = (uri, mode) async => true;
  });

  tearDown(() => UrlActions.launcherOverride = null);

  void surface(
    WidgetTester tester, {
    double width = 800,
    double height = 3200,
  }) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).last));

  Future<GoRouter> pump(
    WidgetTester tester,
    String location, {
    Member? me,
    Duration fallbackDelay = const Duration(seconds: 3),
    bool deepLink = false,
  }) async {
    return pumpEmergencyApp(
      tester,
      location: location,
      deepLink: deepLink,
      overrides: emergencyOverrides(
        prefs: await mockPrefs(),
        repository: repo,
        secure: secure,
        me: me,
        fallbackDelay: fallbackDelay,
        sessionRefresh: spy,
      ),
    );
  }

  /// Keeps an offline copy of [card] like an earlier successful load did.
  Future<List<Override>> withOfflineCopy(
    EmergencyCard card, {
    Duration fallbackDelay = Duration.zero,
  }) async {
    final prefs = await mockPrefs();
    await EmergencyCardOfflineStore(
      cache: LocalCache(prefs),
      secure: secure,
    ).save(testUserId, card);
    return emergencyOverrides(
      prefs: prefs,
      repository: repo,
      secure: secure,
      fallbackDelay: fallbackDelay,
      sessionRefresh: spy,
    );
  }

  group('removed member (NOT_FOUND)', () {
    testWidgets('an old link shows "not available" with a way back', (
      tester,
    ) async {
      repo.getError = notFoundError;
      await pump(tester, '/emergency-cards/${kamla.id}');

      expect(find.text('This card is not available'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.byTooltip('Edit card'), findsNothing);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('without a page underneath it offers the cards list', (
      tester,
    ) async {
      repo.getError = notFoundError;
      await pump(tester, '/emergency-cards/${kamla.id}', deepLink: true);

      await tester.tap(find.text('All emergency cards'));
      await tester.pumpAndSettle();
      expect(find.text('Emergency cards'), findsOneWidget);
    });

    testWidgets('removed while the card is open', (tester) async {
      surface(tester);
      repo.cards[kamla.id] = fullCard(kamla.id);
      await pump(tester, '/emergency-cards/${kamla.id}');
      expect(find.text('Dr. Rao'), findsOneWidget);

      repo.getError = notFoundError;
      containerOf(tester).invalidate(emergencyCardProvider(kamla.id));
      await tester.pumpAndSettle();

      expect(find.text('This card is not available'), findsOneWidget);
      expect(find.text('Dr. Rao'), findsNothing);
    });

    testWidgets('the edit form of a removed member', (tester) async {
      repo.getError = notFoundError;
      await pump(tester, '/emergency-cards/${kamla.id}/edit');
      expect(find.text('This card is not available'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('saving for a member removed meanwhile', (tester) async {
      surface(tester);
      repo.cards[kamla.id] = fullCard(kamla.id);
      await pump(tester, '/emergency-cards/${kamla.id}/edit');
      await tester.enterText(find.widgetWithText(TextFormField, 'Notes'), 'x');

      repo
        ..saveError = notFoundError
        ..getError = notFoundError;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // The refetch (markChanged) finds the member gone: no dead-end form.
      expect(find.text('This card is not available'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('stale data while a screen is open', () {
    testWidgets(
      'the form adopts the fresh card that replaces an offline copy',
      (tester) async {
        surface(tester);
        final overrides = await withOfflineCopy(fullCard(kamla.id));
        final gate = repo.getGate = Completer<void>();
        repo.cards[kamla.id] = fullCard(
          kamla.id,
        ).copyWith(doctorName: () => 'Dr. Fresh');

        await pumpEmergencyApp(
          tester,
          location: '/emergency-cards/${kamla.id}/edit',
          overrides: overrides,
        );
        expect(find.textContaining("You're editing an offline copy"), findsOne);
        expect(find.widgetWithText(TextFormField, 'Dr. Rao'), findsOneWidget);

        gate.complete();
        await tester.pumpAndSettle();
        expect(
          find.textContaining("You're editing an offline copy"),
          findsNothing,
        );
        expect(find.widgetWithText(TextFormField, 'Dr. Fresh'), findsOneWidget);
        expect(
          find.textContaining('updated while you were editing'),
          findsNothing,
        );

        // Nothing was edited: leaving does not ask.
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsNothing);
      },
    );

    testWidgets('edits are kept when someone else saves; a warning says so', (
      tester,
    ) async {
      surface(tester);
      repo.cards[kamla.id] = fullCard(kamla.id);
      await pump(tester, '/emergency-cards/${kamla.id}/edit');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Notes'),
        'My note',
      );
      await tester.pump();

      // Another admin saved a new doctor on their phone.
      repo.cards[kamla.id] = fullCard(
        kamla.id,
      ).copyWith(doctorName: () => 'Dr. Iyer');
      containerOf(tester).invalidate(emergencyCardProvider(kamla.id));
      await tester.pumpAndSettle();

      expect(find.textContaining('updated while you were editing'), findsOne);
      expect(find.widgetWithText(TextFormField, 'My note'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Dr. Rao'), findsOneWidget);
    });

    testWidgets('the responder view switches to the fresh card', (
      tester,
    ) async {
      surface(tester);
      final overrides = await withOfflineCopy(fullCard(kamla.id));
      final gate = repo.getGate = Completer<void>();
      repo.cards[kamla.id] = fullCard(
        kamla.id,
      ).copyWith(notes: () => 'Fresh note');

      await pumpEmergencyApp(
        tester,
        location: '/emergency-cards/${kamla.id}',
        overrides: overrides,
      );
      await tester.tap(find.text('Show to responder'));
      await tester.pumpAndSettle();
      final responder = find.byType(EmergencyCardResponderScreen);
      expect(
        find.descendant(
          of: responder,
          matching: find.textContaining('Offline copy from'),
        ),
        findsOneWidget,
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: responder,
          matching: find.textContaining('Offline copy from'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: responder, matching: find.text('Fresh note')),
        findsOneWidget,
      );
    });

    testWidgets('reopening refreshes a stale card, not a fresh one', (
      tester,
    ) async {
      repo.cards[kamla.id] = fullCard(kamla.id);
      final location = '/emergency-cards/${kamla.id}';
      final router = await pump(tester, location);
      expect(repo.getCalls, [kamla.id]);

      Future<void> reopen() async {
        router.pop();
        await tester.pumpAndSettle();
        unawaited(router.push(location));
        await tester.pumpAndSettle();
      }

      // Reopened right away: served from memory, no second request.
      await reopen();
      expect(repo.getCalls, [kamla.id]);

      // Showing an offline copy: reopening retries the server.
      repo.getError = networkError;
      containerOf(tester).invalidate(emergencyCardProvider(kamla.id));
      await tester.pumpAndSettle();
      expect(find.textContaining('Offline copy from'), findsOneWidget);
      repo.getError = null;
      final calls = repo.getCalls.length;
      await reopen();
      expect(repo.getCalls.length, calls + 1);
      expect(find.textContaining('Offline copy from'), findsNothing);
    });
  });

  group('permissions and navigation', () {
    testWidgets('permission revoked mid-edit: session re-read, form closes', (
      tester,
    ) async {
      surface(tester);
      final meProvider = NotifierProvider<_Me, Member?>(_Me.new);
      late ProviderContainer container;
      spy = SessionRefreshSpy(
        () => container
            .read(meProvider.notifier)
            .set(amit.copyWith(role: MemberRole.member)),
      );
      await pumpEmergencyApp(
        tester,
        location: '/emergency-cards/${kamla.id}/edit',
        overrides: [
          ...emergencyOverrides(
            prefs: await mockPrefs(),
            repository: repo,
            secure: secure,
            sessionRefresh: spy,
            meBuilder: (ref) => ref.watch(meProvider),
          ),
        ],
      );
      container = containerOf(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Notes'), 'x');
      repo.saveError = const ApiException(
        code: ApiErrorCode.forbidden,
        statusCode: 403,
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(spy.calls, 1);
      expect(
        find.text('Only this member or a family admin can edit this card.'),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('a deep-linked form continues to the card after saving', (
      tester,
    ) async {
      surface(tester);
      await pump(tester, '/emergency-cards/${kamla.id}/edit', deepLink: true);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.saveCalls, hasLength(1));
      expect(find.byType(EmergencyCardScreen), findsOneWidget);
      expect(find.text('Edit emergency card'), findsNothing);
    });

    testWidgets('a double tap on a member opens the card once', (tester) async {
      surface(tester);
      repo.cards[kamla.id] = fullCard(kamla.id);
      final router = await pump(tester, '/emergency-cards');

      await tester.tap(find.text('Kamla'));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.text('Kamla'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(EmergencyCardScreen), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(EmergencyCardScreen), findsNothing);
      expect(find.text('Emergency cards'), findsOneWidget);
    });

    testWidgets('rapid taps open the responder view only once', (tester) async {
      surface(tester);
      repo.cards[kamla.id] = fullCard(kamla.id);
      await pump(tester, '/emergency-cards/${kamla.id}');

      await tester.tap(find.text('Show to responder'));
      await tester.tap(find.text('Show to responder'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(EmergencyCardResponderScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Close responder view'));
      await tester.pumpAndSettle();
      expect(find.byType(EmergencyCardResponderScreen), findsNothing);
      // The guard is released: it opens again.
      await tester.tap(find.text('Show to responder'));
      await tester.pumpAndSettle();
      expect(find.byType(EmergencyCardResponderScreen), findsOneWidget);
    });
  });

  group('very long content, 1.4× text, RTL, small phone', () {
    /// [seed] repeated to exactly [length] characters.
    String fill(String seed, int length) =>
        (seed * (length ~/ seed.length + 1)).substring(0, length);
    final longName = fill('Kamaladevi Venkataraman ', 60);
    final unbreakable = 'X' * EmergencyCardLimits.listItemMaxLength;
    EmergencyCard longCard(String memberId) => EmergencyCard(
      memberId: memberId,
      bloodGroup: BloodGroup.abNegative,
      allergies: [
        unbreakable,
        'Penicillin and every other beta-lactam antibiotic, incl. cephalosporins',
        'Peanuts',
      ],
      medications: [
        for (var i = 0; i < 6; i++)
          'Medication number $i, twice a day after food',
      ],
      conditions: [
        'Type 2 diabetes with peripheral neuropathy and hypertension',
      ],
      doctorName: fill('Dr. Ramachandran ', EmergencyCardLimits.textMaxLength),
      doctorPhone: '+911123456789',
      insuranceProvider:
          'The New India Assurance Company Limited, Family Floater',
      insurancePolicyNumber: 'P' * EmergencyCardLimits.textMaxLength,
      emergencyContacts: [
        for (var i = 0; i < EmergencyCardLimits.contactsMax; i++)
          EmergencyContact(
            name: '$i ${fill('Venkatasubramanian ', 97)}',
            phone: '+91987654321$i',
            relation: fill(
              'Brother-in-law ',
              EmergencyCardLimits.relationMaxLength,
            ),
          ),
      ],
      notes: fill('Note text. ', EmergencyCardLimits.notesMaxLength),
      updatedAt: DateTime.utc(2026, 9, 1),
    );

    Future<void> pumpLong(WidgetTester tester, String location) async {
      surface(tester, width: 360, height: 6000);
      final member = kamla.copyWith(
        name: longName,
        designation: () => 'Chief Wisdom Officer and Keeper of Family Recipes',
      );
      repo.cards[kamla.id] = longCard(kamla.id);
      await pumpEmergencyApp(
        tester,
        location: location,
        overrides: emergencyOverrides(
          prefs: await mockPrefs(),
          repository: repo,
          secure: secure,
          sessionRefresh: spy,
          members: [amit, member, aarav],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        ),
      );
    }

    testWidgets('list', (tester) async {
      await pumpLong(tester, '/emergency-cards');
      expect(tester.takeException(), isNull);
      expect(find.text(longName), findsOneWidget);
      expect(find.text('AB-'), findsOneWidget);
    });

    testWidgets('card and responder view', (tester) async {
      await pumpLong(tester, '/emergency-cards/${kamla.id}');
      expect(tester.takeException(), isNull);
      expect(find.text(unbreakable), findsOneWidget);

      await tester.tap(find.text('Show to responder'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('edit form', (tester) async {
      await pumpLong(tester, '/emergency-cards/${kamla.id}/edit');
      expect(tester.takeException(), isNull);
      expect(find.text(unbreakable), findsOneWidget);
      // The five contacts are the maximum: no more can be added.
      expect(find.text('You can add up to 5 contacts.'), findsOneWidget);
    });
  });

  testWidgets('missing key details are listed with the list separator', (
    tester,
  ) async {
    surface(tester);
    repo.cards[amit.id] = EmergencyCard(
      memberId: amit.id,
      bloodGroup: BloodGroup.bPositive,
      emergencyContacts: const [
        EmergencyContact(name: 'Priya', phone: '+919876543211'),
      ],
      updatedAt: DateTime.utc(2026, 9),
    );
    await pump(tester, '/emergency-cards');
    expect(find.text('Missing: Doctor, Health insurance'), findsOneWidget);
  });

  testWidgets('a contact stored without a name is still callable', (
    tester,
  ) async {
    surface(tester);
    repo.cards[kamla.id] = EmergencyCard(
      memberId: kamla.id,
      bloodGroup: BloodGroup.oPositive,
      emergencyContacts: const [
        EmergencyContact(name: ' ', phone: '+919876543211'),
      ],
      updatedAt: DateTime.utc(2026, 9),
    );
    await pump(tester, '/emergency-cards/${kamla.id}');
    expect(find.text('Contact 1'), findsOneWidget);
    expect(find.byTooltip('Call Contact 1'), findsOneWidget);
  });
}

/// The signed-in member, changeable by a test (e.g. demoted).
class _Me extends Notifier<Member?> {
  @override
  Member? build() => amit;

  void set(Member? value) => state = value;
}
