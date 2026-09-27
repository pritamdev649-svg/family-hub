import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/widgets/widgets.dart';

import 'widget_test_harness.dart';

void main() {
  group('AppButton', () {
    testWidgets('calls onPressed when enabled', (tester) async {
      var taps = 0;
      await pumpHarness(
        tester,
        AppButton(label: 'Save', onPressed: () => taps++),
      );
      await tester.tap(find.text('Save'));
      expect(taps, 1);
    });

    testWidgets('shows a spinner and ignores taps while loading', (
      tester,
    ) async {
      var taps = 0;
      await pumpHarness(
        tester,
        AppButton(label: 'Save', isLoading: true, onPressed: () => taps++),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Save'), warnIfMissed: false);
      expect(taps, 0);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('variants map to Material buttons', (tester) async {
      await pumpHarness(
        tester,
        Column(
          children: [
            AppButton(
              label: 'a',
              onPressed: () {},
              variant: AppButtonVariant.secondary,
            ),
            AppButton(
              label: 'b',
              onPressed: () {},
              variant: AppButtonVariant.text,
            ),
            AppButton(
              label: 'c',
              onPressed: () {},
              variant: AppButtonVariant.danger,
            ),
          ],
        ),
      );
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });

  group('AppTextField', () {
    testWidgets('obscured field toggles visibility', (tester) async {
      await pumpHarness(
        tester,
        const AppTextField(label: 'Password', obscure: true),
      );
      EditableText editable() =>
          tester.widget<EditableText>(find.byType(EditableText));
      expect(editable().obscureText, isTrue);
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(editable().obscureText, isFalse);
    });

    testWidgets('uses initialValue when no controller is given', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        const AppTextField(label: 'Name', initialValue: 'Amit'),
      );
      expect(find.text('Amit'), findsOneWidget);
    });
  });

  group('MemberAvatar', () {
    test('initials support multiple words and scripts', () {
      expect(MemberAvatar.initialsOf('Amit Sharma'), 'AS');
      expect(MemberAvatar.initialsOf('  priya  '), 'P');
      expect(MemberAvatar.initialsOf('Amit Kumar Sharma'), 'AS');
      expect(MemberAvatar.initialsOf(''), '');
      expect(MemberAvatar.initialsOf(null), '');
      // Devanagari conjunct stays one grapheme cluster.
      expect(MemberAvatar.initialsOf('प्रिया'), 'प्रि');
    });

    test('colours are deterministic per name', () {
      final a = MemberAvatar.colorsFor('Aarav', Brightness.light);
      final b = MemberAvatar.colorsFor('aarav ', Brightness.light);
      expect(a, b);
    });

    testWidgets('renders initials with the name as semantics label', (
      tester,
    ) async {
      await pumpHarness(tester, const MemberAvatar(name: 'Kamla Devi'));
      expect(find.text('KD'), findsOneWidget);
      expect(find.bySemanticsLabel('Kamla Devi'), findsOneWidget);
    });

    testWidgets('shows a person icon without a name', (tester) async {
      await pumpHarness(tester, const MemberAvatar());
      expect(find.byIcon(AppIcons.member), findsOneWidget);
    });
  });

  group('AppNetworkImage', () {
    test('classifies image references', () {
      expect(
        appImageKind('https://res.cloudinary.com/x.jpg'),
        AppImageKind.network,
      );
      expect(appImageKind('/data/user/0/cache/pic.jpg'), AppImageKind.file);
      expect(appImageKind('file:///tmp/pic.jpg'), AppImageKind.file);
      expect(appImageKind(''), AppImageKind.none);
      expect(appImageKind(null), AppImageKind.none);
      expect(appImageKind('ftp://example.com/x.jpg'), AppImageKind.none);
    });

    testWidgets('empty url renders the placeholder', (tester) async {
      await pumpHarness(
        tester,
        const AppNetworkImage(url: '', width: 40, height: 40),
      );
      expect(find.byIcon(AppIcons.brokenImage), findsOneWidget);
    });
  });

  group('MoneyText', () {
    testWidgets('income is signed and green, expense signed and red', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        const Column(
          children: [
            MoneyText(1250.5, flow: LedgerFlow.income),
            MoneyText(300, flow: LedgerFlow.expense),
            MoneyText(-42),
          ],
        ),
      );
      final income = tester.widget<Text>(find.textContaining('1,250.50'));
      expect(income.data, startsWith('+'));
      expect(income.style?.color, AppSemanticColors.light.income);

      final expense = tester.widget<Text>(find.textContaining('300'));
      expect(expense.data, startsWith('−'));
      expect(expense.style?.color, AppSemanticColors.light.expense);

      final neutral = tester.widget<Text>(find.textContaining('42'));
      expect(neutral.data, startsWith('−'));
      expect(neutral.style?.color, isNull);
    });

    testWidgets('zero never gets a sign; NaN renders as zero', (tester) async {
      await pumpHarness(
        tester,
        const Column(
          children: [
            MoneyText(0, flow: LedgerFlow.income),
            MoneyText(double.nan, flow: LedgerFlow.expense),
          ],
        ),
      );
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.data, isNot(startsWith('+')));
        expect(t.data, isNot(startsWith('−')));
      }
    });
  });

  group('StatusChip / AppProgressBar / SectionHeader', () {
    testWidgets('StatusChip shows label and icon', (tester) async {
      await pumpHarness(
        tester,
        const StatusChip(label: 'Overdue', icon: AppIcons.overdue),
      );
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.byIcon(AppIcons.overdue), findsOneWidget);
    });

    testWidgets('AppProgressBar clamps its value', (tester) async {
      await pumpHarness(tester, const AppProgressBar(value: 3));
      await tester.pumpAndSettle();
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 1.0);
      expect(bar.semanticsValue, contains('100'));
    });

    testWidgets('AppProgressBar treats NaN as empty', (tester) async {
      await pumpHarness(tester, const AppProgressBar(value: double.nan));
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.0);
    });

    testWidgets(
      'SectionHeader action only when both label and callback exist',
      (tester) async {
        var taps = 0;
        await pumpHarness(
          tester,
          Column(
            children: [
              SectionHeader(
                title: 'Tasks',
                actionLabel: 'See all',
                onAction: () => taps++,
              ),
              const SectionHeader(title: 'Goals', actionLabel: 'Hidden'),
            ],
          ),
        );
        await tester.tap(find.text('See all'));
        expect(taps, 1);
        expect(find.text('Hidden'), findsNothing);
      },
    );
  });

  group('AppCard / ResponsiveCenter', () {
    testWidgets('AppCard is tappable when onTap is set', (tester) async {
      var taps = 0;
      await pumpHarness(
        tester,
        AppCard(onTap: () => taps++, child: const Text('Card')),
      );
      await tester.tap(find.text('Card'));
      expect(taps, 1);
    });

    testWidgets('ResponsiveCenter caps the width', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const key = Key('content');
      await pumpHarness(
        tester,
        const ResponsiveCenter(child: SizedBox(key: key, height: 10)),
      );
      expect(tester.getSize(find.byKey(key)).width, AppSizes.maxContentWidth);
    });
  });
}
