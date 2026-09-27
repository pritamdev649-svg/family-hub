import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/storage/local_cache.dart';
import 'package:family_hub/core/utils/url_actions.dart';
import 'package:family_hub/features/emergency_card/application/emergency_card_providers.dart';
import 'package:family_hub/features/emergency_card/data/emergency_card_offline_store.dart';
import 'package:family_hub/features/emergency_card/presentation/screens/emergency_card_responder_screen.dart';
import 'package:family_hub/shared/models/member.dart';

import 'emergency_card_test_utils.dart';

void main() {
  late FakeEmergencyCardRepository repo;
  late InMemorySecureStore secure;
  late List<Uri> launched;

  setUp(() {
    repo = FakeEmergencyCardRepository();
    secure = InMemorySecureStore();
    launched = [];
    UrlActions.launcherOverride = (uri, mode) async {
      launched.add(uri);
      return true;
    };
  });

  tearDown(() => UrlActions.launcherOverride = null);

  /// The editor panel of emergency contact [number] in the form.
  Finder contactEditor(int number) =>
      find.byKey(ValueKey('emergencyContactEditor-$number'));

  /// A tall surface so whole cards / forms are built without scrolling.
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pump(
    WidgetTester tester,
    String location, {
    Member? me,
    Duration fallbackDelay = const Duration(seconds: 3),
  }) async {
    await pumpEmergencyApp(
      tester,
      location: location,
      overrides: emergencyOverrides(
        prefs: await mockPrefs(),
        repository: repo,
        secure: secure,
        me: me,
        fallbackDelay: fallbackDelay,
      ),
    );
  }

  group('EmergencyCardsScreen', () {
    testWidgets('lists members with blood group and completeness', (
      tester,
    ) async {
      tallSurface(tester);
      repo.cards[kamla.id] = fullCard(kamla.id);
      repo.cards[amit.id] = EmergencyCard(
        memberId: amit.id,
        bloodGroup: BloodGroup.bPositive,
        allergies: const ['Peanuts'],
        updatedAt: DateTime.utc(2026, 9),
      );
      await pump(tester, '/emergency-cards');

      expect(find.text('Emergency cards'), findsOneWidget);
      expect(find.text('In danger? Call 112'), findsOneWidget);
      for (final m in testMembers) {
        expect(find.text(m.name), findsOneWidget);
      }
      expect(find.text('Me'), findsOneWidget); // Amit is signed in
      expect(find.text('B+'), findsOneWidget);
      expect(find.text('O+'), findsOneWidget);
      expect(find.text('All key details added'), findsOneWidget);
      expect(find.text('1 of 4 key details'), findsOneWidget);
      expect(find.text('Not filled in yet'), findsOneWidget); // Aarav

      await tester.tap(find.text('In danger? Call 112'));
      await tester.pump();
      expect(launched.single.toString(), 'tel:112');

      await tester.tap(find.text('Kamla'));
      await tester.pumpAndSettle();
      expect(find.text('Show to responder'), findsOneWidget);
    });

    testWidgets('members error shows retry', (tester) async {
      await pumpEmergencyApp(
        tester,
        location: '/emergency-cards',
        overrides: emergencyOverrides(
          prefs: await mockPrefs(),
          repository: repo,
          secure: secure,
          membersError: notFoundError,
        ),
      );
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('EmergencyCardScreen', () {
    testWidgets('shows every section with call and copy actions', (
      tester,
    ) async {
      tallSurface(tester);
      repo.cards[kamla.id] = fullCard(kamla.id);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final semantics = tester.ensureSemantics();
      await pump(tester, '/emergency-cards/${kamla.id}');

      expect(find.text('Kamla'), findsWidgets);
      expect(find.text('O+'), findsOneWidget);
      expect(find.bySemanticsLabel('Allergy: Penicillin'), findsOneWidget);
      expect(find.text('Metformin 500 mg'), findsOneWidget);
      expect(find.text('Type 2 diabetes'), findsOneWidget);
      expect(find.text('Dr. Rao'), findsOneWidget);
      expect(find.text('Star Health'), findsOneWidget);
      expect(find.text('SH-1'), findsOneWidget);
      expect(find.text('Glucose tablets in handbag'), findsOneWidget);
      expect(find.textContaining('Last updated'), findsOneWidget);
      expect(find.textContaining('not medical advice'), findsOneWidget);
      // Admin → edit action.
      expect(find.byTooltip('Edit card'), findsOneWidget);

      await tester.tap(find.byTooltip('Call Dr. Rao'));
      await tester.pump();
      expect(launched.last, Uri(scheme: 'tel', path: '+911123456789'));

      await tester.tap(find.byTooltip('Copy policy number'));
      await tester.pumpAndSettle();
      expect(copied, ['SH-1']);
      expect(find.text('Policy number copied'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('no edit action for other members\' cards', (tester) async {
      repo.cards[kamla.id] = fullCard(kamla.id);
      await pump(tester, '/emergency-cards/${kamla.id}', me: aarav);
      expect(find.text('O+'), findsOneWidget);
      expect(find.byTooltip('Edit card'), findsNothing);
    });

    testWidgets('empty own card invites to fill it in', (tester) async {
      await pump(tester, '/emergency-cards/${aarav.id}', me: aarav);
      expect(find.text('No emergency details yet'), findsOneWidget);
      expect(find.text('Show to responder'), findsNothing);
      await tester.tap(find.text('Fill in card'));
      await tester.pumpAndSettle();
      expect(find.text('Edit emergency card'), findsOneWidget);
    });

    testWidgets('offline: shows the saved copy with a hint', (tester) async {
      final prefs = await mockPrefs();
      await EmergencyCardOfflineStore(
        cache: LocalCache(prefs),
        secure: secure,
      ).save(testUserId, fullCard(kamla.id));
      repo.getError = networkError;

      await pumpEmergencyApp(
        tester,
        location: '/emergency-cards/${kamla.id}',
        overrides: emergencyOverrides(
          prefs: prefs,
          repository: repo,
          secure: secure,
        ),
      );

      expect(find.text('O+'), findsOneWidget);
      expect(find.textContaining('Offline copy from'), findsOneWidget);
    });

    testWidgets('responder view: large, high contrast, closable', (
      tester,
    ) async {
      tallSurface(tester);
      repo.cards[kamla.id] = fullCard(kamla.id);
      await pump(tester, '/emergency-cards/${kamla.id}');

      await tester.tap(find.text('Show to responder'));
      await tester.pumpAndSettle();
      expect(find.byType(EmergencyCardResponderScreen), findsOneWidget);
      expect(find.text('Emergency medical information'), findsOneWidget);

      final badge = tester.widget<Text>(
        find.descendant(
          of: find.byType(EmergencyCardResponderScreen),
          matching: find.text('O+'),
        ),
      );
      final display = Theme.of(
        tester.element(find.byType(EmergencyCardResponderScreen)),
      ).textTheme.displayLarge!;
      expect(badge.style!.fontSize, display.fontSize);

      await tester.tap(find.text('Call Amit'));
      await tester.pump();
      expect(launched.last.path, '+919876543210');

      await tester.tap(find.byTooltip('Close responder view'));
      await tester.pumpAndSettle();
      expect(find.byType(EmergencyCardResponderScreen), findsNothing);
    });

    testWidgets('large text + RTL lay out without overflow', (tester) async {
      tallSurface(tester);
      repo.cards[kamla.id] = fullCard(kamla.id);
      await pumpEmergencyApp(
        tester,
        location: '/emergency-cards/${kamla.id}',
        overrides: emergencyOverrides(
          prefs: await mockPrefs(),
          repository: repo,
          secure: secure,
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
      expect(tester.takeException(), isNull);
      expect(find.text('Dr. Rao'), findsOneWidget);

      await tester.tap(find.text('Show to responder'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close responder view'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit card'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Edit emergency card'), findsOneWidget);
    });
  });

  group('EmergencyCardFormScreen', () {
    testWidgets('edits lists, doctor and contacts, then saves and pops', (
      tester,
    ) async {
      tallSurface(tester);
      repo.cards[kamla.id] = fullCard(kamla.id);
      await pump(tester, '/emergency-cards/${kamla.id}');
      await tester.tap(find.byTooltip('Edit card'));
      await tester.pumpAndSettle();

      expect(find.text('Edit emergency card'), findsOneWidget);
      expect(find.textContaining('not medical advice'), findsOneWidget);
      expect(find.text('Penicillin'), findsOneWidget);

      // Add an allergy with the add button, one typed but not added.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Add an allergy'),
        'Latex',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Add Latex'));
      await tester.pump();
      expect(find.text('Latex'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Add a condition'),
        'Asthma',
      );
      // Remove a medication.
      await tester.tap(find.byTooltip('Remove Metformin 500 mg'));
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(TextFormField, "Doctor's name"),
        'Dr. Iyer',
      );
      await tester.tap(find.text('Add contact'));
      await tester.pump();
      final contactFields = find.descendant(
        of: contactEditor(2),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(contactFields.at(0), 'Priya');
      await tester.enterText(contactFields.at(1), '+91 98765 43211');
      await tester.enterText(contactFields.at(2), 'Daughter-in-law');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final (memberId, sent) = repo.saveCalls.single;
      expect(memberId, kamla.id);
      expect(sent.allergies, ['Penicillin', 'Latex']);
      expect(sent.medications, isEmpty);
      expect(sent.conditions, ['Type 2 diabetes', 'Asthma']);
      expect(sent.doctorName, 'Dr. Iyer');
      expect(
        sent.emergencyContacts.last,
        const EmergencyContact(
          name: 'Priya',
          phone: '+919876543211',
          relation: 'Daughter-in-law',
        ),
      );

      // Back on the card, refreshed with the saved data.
      expect(find.text('Edit emergency card'), findsNothing);
      expect(find.text('Emergency card saved'), findsOneWidget);
      expect(find.text('Dr. Iyer'), findsOneWidget);
    });

    testWidgets('invalid fields block saving', (tester) async {
      tallSurface(tester);
      await pump(tester, '/emergency-cards/${amit.id}/edit');

      await tester.enterText(
        find.widgetWithText(TextFormField, "Doctor's phone"),
        'call me',
      );
      await tester.tap(find.text('Add contact'));
      await tester.pump();
      final contactFields = find.descendant(
        of: contactEditor(1),
        matching: find.byType(TextFormField),
      );
      // A phone without a name.
      await tester.enterText(contactFields.at(1), '+919800000000');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.saveCalls, isEmpty);
      expect(find.text('Please check the highlighted fields.'), findsOneWidget);
      expect(find.textContaining('Enter a valid phone number'), findsOneWidget);
      expect(find.text('This field is required'), findsOneWidget);
    });

    testWidgets('server errors are shown and the form stays open', (
      tester,
    ) async {
      tallSurface(tester);
      repo.saveError = const ApiException(
        code: ApiErrorCode.forbidden,
        statusCode: 403,
      );
      await pump(tester, '/emergency-cards/${amit.id}/edit');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.saveCalls, hasLength(1));
      expect(find.text('Edit emergency card'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('leaving with unsaved changes asks first', (tester) async {
      tallSurface(tester);
      await pump(tester, '/emergency-cards/${amit.id}/edit');
      await tester.enterText(find.widgetWithText(TextFormField, 'Notes'), 'x');
      await tester.pump();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Edit emergency card'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Edit emergency card'), findsNothing);
      expect(repo.saveCalls, isEmpty);
    });

    testWidgets('members cannot edit someone else\'s card', (tester) async {
      await pump(tester, '/emergency-cards/${kamla.id}/edit', me: aarav);
      expect(
        find.text('Only this member or a family admin can edit this card.'),
        findsOneWidget,
      );
      expect(find.text('Save'), findsNothing);
    });
  });
}
