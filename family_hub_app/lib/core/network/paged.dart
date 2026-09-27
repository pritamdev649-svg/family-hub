import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// One page of a paginated list endpoint (`meta` in the envelope).
@immutable
class Paged<T> {
  const Paged({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasMore,
  });

  /// An empty first page (nothing loaded yet / nothing to load).
  const Paged.empty({this.limit = 20})
    : items = const [],
      page = 0,
      total = 0,
      hasMore = false;

  final List<T> items;

  /// 1-based page number of the *last* loaded page (0 for [Paged.empty]).
  final int page;
  final int limit;

  /// Total number of items on the server.
  final int total;
  final bool hasMore;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  int get length => items.length;

  /// Page to request next for "load more".
  int get nextPage => page + 1;

  /// Returns a list with [next]'s items appended and [next]'s paging info.
  /// Items with an identical `id`-equality already present are not
  /// duplicated when [identity] is given (useful when new items were
  /// created between two page loads and shifted the offsets).
  Paged<T> append(Paged<T> next, {Object? Function(T item)? identity}) {
    final List<T> merged;
    if (identity == null) {
      merged = [...items, ...next.items];
    } else {
      final seen = {for (final i in items) identity(i)};
      merged = [
        ...items,
        for (final i in next.items)
          if (seen.add(identity(i))) i,
      ];
    }
    return Paged<T>(
      items: List.unmodifiable(merged),
      page: next.page,
      limit: next.limit,
      total: next.total,
      hasMore: next.hasMore,
    );
  }

  Paged<R> map<R>(R Function(T item) convert) => Paged<R>(
    items: List.unmodifiable(items.map(convert)),
    page: page,
    limit: limit,
    total: total,
    hasMore: hasMore,
  );

  /// Copy with items removed/replaced locally (e.g. after a delete) while
  /// keeping paging info consistent.
  Paged<T> copyWith({List<T>? items, int? total, bool? hasMore}) {
    final newItems = items ?? this.items;
    return Paged<T>(
      items: List.unmodifiable(newItems),
      page: page,
      limit: limit,
      total:
          total ??
          math.max(0, this.total - (this.items.length - newItems.length)),
      hasMore: hasMore ?? this.hasMore,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Paged<T> &&
      other.page == page &&
      other.limit == limit &&
      other.total == total &&
      other.hasMore == hasMore &&
      listEquals(other.items, items);

  @override
  int get hashCode =>
      Object.hash(page, limit, total, hasMore, Object.hashAll(items));

  @override
  String toString() =>
      'Paged<$T>(page: $page, limit: $limit, total: $total, hasMore: $hasMore, items: ${items.length})';
}
