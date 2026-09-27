import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/design/app_icons.dart';

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/core/widgets/widgets.dart';

import 'widget_test_harness.dart';

void main() {
  group('AsyncValueView', () {
    testWidgets('loading → LoadingView', (tester) async {
      await pumpHarness(
        tester,
        AsyncValueView<int>(
          value: const AsyncLoading(),
          data: (v) => Text('v$v'),
        ),
      );
      expect(find.byType(LoadingView), findsOneWidget);
    });

    testWidgets('error without data → ErrorView with working retry', (
      tester,
    ) async {
      var retries = 0;
      await pumpHarness(
        tester,
        AsyncValueView<int>(
          value: const AsyncError(ApiException.timeout(), StackTrace.empty),
          onRetry: () => retries++,
          data: (v) => Text('v$v'),
        ),
      );
      expect(find.byType(ErrorView), findsOneWidget);
      await tester.tap(find.byType(OutlinedButton));
      expect(retries, 1);
    });

    testWidgets('empty data → EmptyState (default or custom)', (tester) async {
      await pumpHarness(
        tester,
        AsyncValueView<List<int>>(
          value: const AsyncData([]),
          isEmpty: (l) => l.isEmpty,
          data: (l) => Text('items ${l.length}'),
        ),
      );
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.textContaining('items'), findsNothing);
    });

    testWidgets('data → builder', (tester) async {
      await pumpHarness(
        tester,
        AsyncValueView<int>(
          value: const AsyncData(7),
          data: (v) => Text('v$v'),
        ),
      );
      expect(find.text('v7'), findsOneWidget);
    });

    testWidgets(
      'keeps previous data while refreshing and after a failed refresh',
      (tester) async {
        var calls = 0;
        var gate = Completer<int>();
        final provider = FutureProvider<int>((ref) {
          calls++;
          if (calls == 1) return 1;
          return gate.future;
        });

        await pumpHarness(
          tester,
          Consumer(
            builder: (context, ref, _) => AsyncValueView<int>(
              value: ref.watch(provider),
              onRetry: () => ref.invalidate(provider),
              data: (v) => Text('v$v'),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('v1'), findsOneWidget);

        // Refresh: previous data + thin progress bar, no full-screen spinner.
        final container = ProviderScope.containerOf(
          tester.element(find.text('v1')),
        );
        container.invalidate(provider);
        await tester.pump();
        expect(find.text('v1'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.byType(LoadingView), findsNothing);

        // Refresh fails: previous data + dismissible notice.
        gate.completeError(const ApiException.timeout());
        await tester.pump();
        await tester.pump();
        expect(find.text('v1'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byTooltip('Close'), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await tester.pump();
        expect(find.byTooltip('Close'), findsNothing);

        // Successful refresh shows the new value.
        gate = Completer<int>();
        container.invalidate(provider);
        await tester.pump();
        gate.complete(2);
        await tester.pump();
        await tester.pump();
        expect(find.text('v2'), findsOneWidget);
      },
    );
  });

  group('showConfirmDialog', () {
    Future<Future<bool>> open(WidgetTester tester) async {
      late Future<bool> result;
      await pumpHarness(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showConfirmDialog(
              context,
              title: 'Delete task?',
              message: 'This cannot be undone.',
              destructive: true,
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('confirm resolves true', (tester) async {
      final result = await open(tester);
      expect(find.text('Delete task?'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('cancel resolves false', (tester) async {
      final result = await open(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });
  });

  group('SnackX', () {
    testWidgets(
      'showError shows the localised message; cancellations are silent',
      (tester) async {
        await pumpHarness(
          tester,
          Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () =>
                      context.showError(const ApiException.timeout()),
                  child: const Text('fail'),
                ),
                TextButton(
                  onPressed: () => context.showError(
                    const ApiException(
                      code: ApiErrorCode.cancelled,
                      message: '',
                    ),
                  ),
                  child: const Text('cancel'),
                ),
                TextButton(
                  onPressed: () => context.showSuccess('Saved!'),
                  child: const Text('ok'),
                ),
              ],
            ),
          ),
        );
        await tester.tap(find.text('cancel'));
        await tester.pump();
        expect(find.byType(SnackBar), findsNothing);

        await tester.tap(find.text('fail'));
        await tester.pump();
        expect(find.byType(SnackBar), findsOneWidget);

        await tester.tap(find.text('ok'));
        await tester.pumpAndSettle();
        expect(find.text('Saved!'), findsOneWidget);
      },
    );
  });

  group('OfflineBanner', () {
    testWidgets('appears only while offline', (tester) async {
      await pumpHarness(tester, const OfflineBanner());
      expect(find.byIcon(AppIcons.offline), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(OfflineBanner)),
      );
      container.read(connectivityStatusProvider.notifier).report(false);
      await tester.pumpAndSettle();
      expect(find.byIcon(AppIcons.offline), findsOneWidget);

      container.read(connectivityStatusProvider.notifier).report(true);
      await tester.pumpAndSettle();
      expect(find.byIcon(AppIcons.offline), findsNothing);
    });
  });
}
