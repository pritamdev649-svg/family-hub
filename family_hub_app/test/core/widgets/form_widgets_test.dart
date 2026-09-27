import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/widgets/widgets.dart';

import 'widget_test_harness.dart';

enum _Priority { low, medium, high }

void main() {
  group('AppDropdownField', () {
    testWidgets(
      'a value missing from items renders empty instead of crashing',
      (tester) async {
        await pumpHarness(
          tester,
          AppDropdownField<_Priority>(
            label: 'Priority',
            value: _Priority.high,
            items: const [_Priority.low, _Priority.medium],
            itemLabel: (p) => p.name,
            onChanged: (_) {},
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Priority'), findsOneWidget);
      },
    );

    testWidgets('selecting an item reports it', (tester) async {
      _Priority? picked;
      await pumpHarness(
        tester,
        AppDropdownField<_Priority>(
          label: 'Priority',
          items: _Priority.values,
          itemLabel: (p) => p.name,
          onChanged: (p) => picked = p,
        ),
      );
      await tester.tap(find.text('Priority'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('medium').last);
      await tester.pumpAndSettle();
      expect(picked, _Priority.medium);
    });
  });

  group('ChoiceChipsField', () {
    testWidgets('marks the selected option and reports taps', (tester) async {
      _Priority? picked;
      await pumpHarness(
        tester,
        ChoiceChipsField<_Priority>(
          options: _Priority.values,
          selected: _Priority.low,
          label: (p) => p.name,
          icon: (_) => AppIcons.priority,
          onSelected: (p) => picked = p,
        ),
      );
      final chips = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .toList();
      expect(chips, hasLength(3));
      expect(chips.first.selected, isTrue);
      await tester.tap(find.text('high'));
      expect(picked, _Priority.high);
    });
  });

  group('DatePickerField', () {
    testWidgets('shows the formatted date, clears and validates', (
      tester,
    ) async {
      DateTime? value = DateTime(2026, 9, 26);
      final formKey = GlobalKey<FormState>();
      await pumpHarness(
        tester,
        StatefulBuilder(
          builder: (context, setState) => Form(
            key: formKey,
            child: DatePickerField(
              label: 'Due date',
              value: value,
              onChanged: (d) => setState(() => value = d),
              validator: (d) => d == null ? 'Required' : null,
            ),
          ),
        ),
      );
      expect(find.text(testFmt().date(DateTime(2026, 9, 26))), findsOneWidget);

      await tester.tap(find.byIcon(AppIcons.clear));
      await tester.pump();
      expect(value, isNull);

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('opens the date picker and returns the chosen date', (
      tester,
    ) async {
      DateTime? value = DateTime(2026, 9, 10);
      await pumpHarness(
        tester,
        StatefulBuilder(
          builder: (context, setState) => DatePickerField(
            label: 'Due date',
            value: value,
            firstDate: DateTime(2026),
            lastDate: DateTime(2026, 12, 31),
            onChanged: (d) => setState(() => value = d),
          ),
        ),
      );
      await tester.tap(find.byIcon(AppIcons.calendar));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(value, DateTime(2026, 9, 20));
    });
  });

  group('PaginatedListView', () {
    testWidgets('renders header, items and a load-more button', (tester) async {
      var loads = 0;
      await pumpHarness(
        tester,
        PaginatedListView<int>(
          items: const [1, 2, 3],
          hasMore: true,
          isLoadingMore: false,
          onLoadMore: () => loads++,
          header: const Text('Header'),
          itemBuilder: (_, i) => Text('item $i'),
        ),
      );
      expect(find.text('Header'), findsOneWidget);
      expect(find.text('item 3'), findsOneWidget);
      await tester.tap(find.text('Load more'));
      expect(loads, 1);
    });

    testWidgets('shows a spinner while loading more and nothing when done', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        PaginatedListView<int>(
          items: const [1],
          hasMore: true,
          isLoadingMore: true,
          onLoadMore: () {},
          itemBuilder: (_, i) => Text('item $i'),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await pumpHarness(
        tester,
        PaginatedListView<int>(
          items: const [1],
          hasMore: false,
          isLoadingMore: false,
          onLoadMore: () {},
          itemBuilder: (_, i) => Text('item $i'),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('auto-loads once when scrolled near the end', (tester) async {
      var loads = 0;
      await pumpHarness(
        tester,
        PaginatedListView<int>(
          items: List.generate(60, (i) => i),
          hasMore: true,
          isLoadingMore: false,
          onLoadMore: () => loads++,
          itemBuilder: (_, i) => SizedBox(height: 60, child: Text('item $i')),
        ),
      );
      expect(loads, 0);
      await tester.fling(find.byType(ListView), const Offset(0, -20000), 5000);
      await tester.pumpAndSettle();
      expect(loads, 1);
    });
  });
}
