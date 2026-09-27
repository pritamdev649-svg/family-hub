import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/shared/providers/data_refresh.dart';

void main() {
  test('every scope starts at 0 and only marked scopes are bumped', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final initial = c.read(dataRefreshProvider);
    expect(initial.keys.toSet(), DataScope.values.toSet());
    expect(initial.values.every((v) => v == 0), isTrue);

    final seen = <int?>[];
    c.listen(
      dataRefreshProvider.select((m) => m[DataScope.tasks]),
      (_, next) => seen.add(next),
    );

    c.read(dataRefreshProvider.notifier).markChanged({DataScope.ledger});
    expect(seen, isEmpty, reason: 'tasks watchers are not notified');

    c.read(dataRefreshProvider.notifier).markChanged({
      DataScope.tasks,
      DataScope.ledger,
    });
    expect(seen, [1]);
    expect(c.read(dataRefreshProvider)[DataScope.ledger], 2);

    c.read(dataRefreshProvider.notifier).markChanged(const {});
    expect(c.read(dataRefreshProvider)[DataScope.ledger], 2);

    c.read(dataRefreshProvider.notifier).markAllChanged();
    expect(c.read(dataRefreshProvider)[DataScope.sos], 1);
    expect(seen, [1, 2]);
  });

  test('markChanged(Ref, …) helper works from providers', () {
    final bump = Provider<void Function()>(
      (ref) =>
          () => markChanged(ref, {DataScope.notices}),
    );
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(bump)();
    expect(c.read(dataRefreshProvider)[DataScope.notices], 1);
  });
}
