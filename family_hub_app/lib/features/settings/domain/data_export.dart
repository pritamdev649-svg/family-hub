import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:family_hub/shared/json.dart';

/// Known top-level sections of `GET /me/export` (docs/03-API_CONTRACT.md §5,
/// plus the family, push devices and sign-in sessions the backend also
/// exports as personal data).
enum DataExportSection {
  user('user'),
  member('member'),
  family('family'),
  tasks('tasks'),
  ledgerEntries('ledgerEntries'),
  notices('notices'),
  emergencyCard('emergencyCard'),
  sosAlerts('sosAlerts'),
  devices('devices'),
  sessions('sessions');

  const DataExportSection(this.key);

  /// JSON key in the export.
  final String key;
}

/// Size of one export section: a list (`count` items) or a single record.
@immutable
class DataExportSectionSummary {
  const DataExportSectionSummary({
    required this.section,
    required this.isList,
    required this.count,
  });

  final DataExportSection section;

  /// `true` for list sections (tasks, ledger entries …).
  final bool isList;

  /// Items in a list section; `1` / `0` for a present / absent record.
  final int count;

  bool get isEmpty => count == 0;

  @override
  bool operator ==(Object other) =>
      other is DataExportSectionSummary &&
      other.section == section &&
      other.isList == isList &&
      other.count == count;

  @override
  int get hashCode => Object.hash(section, isList, count);

  @override
  String toString() => 'DataExportSectionSummary(${section.key}: $count)';
}

/// The caller's personal data export (right of access / portability).
///
/// Parsing is lenient: unknown sections are kept in [data] (and the pretty
/// JSON) but not summarised; missing sections count as empty.
@immutable
class DataExport {
  DataExport._(this.data, this.exportedAt, this.sections);

  /// [receivedAt] is used when the server does not send `exportedAt`.
  factory DataExport.fromJson(
    Map<String, dynamic> json, {
    DateTime? receivedAt,
  }) {
    final data = Map<String, dynamic>.unmodifiable(json);
    final sections = <DataExportSectionSummary>[
      for (final s in DataExportSection.values)
        if (data.containsKey(s.key)) _summarise(s, data[s.key]),
    ];
    return DataExport._(
      data,
      parseDate(data['exportedAt']) ?? receivedAt,
      List.unmodifiable(sections),
    );
  }

  static DataExportSectionSummary _summarise(
    DataExportSection section,
    Object? value,
  ) {
    if (value is List) {
      return DataExportSectionSummary(
        section: section,
        isList: true,
        count: value.length,
      );
    }
    final present = value is Map ? value.isNotEmpty : value != null;
    return DataExportSectionSummary(
      section: section,
      isList: false,
      count: present ? 1 : 0,
    );
  }

  /// The raw export (unmodifiable).
  final Map<String, dynamic> data;

  /// When the export was generated (server time or time of receipt).
  final DateTime? exportedAt;

  /// Summaries of the known sections present in the export, in
  /// [DataExportSection] order.
  final List<DataExportSectionSummary> sections;

  /// No data at all (the export object is empty).
  bool get isEmpty => data.isEmpty;

  static const _encoder = JsonEncoder.withIndent('  ');

  /// Human-readable, 2-space indented JSON of the whole export. Non-JSON
  /// values (never sent by the API) are stringified instead of throwing.
  late final String prettyJson = _encode(data);

  /// [prettyJson] split into lines, for lazily built lists (an export of a
  /// busy family can have tens of thousands of lines).
  late final List<String> prettyJsonLines = List.unmodifiable(
    const LineSplitter().convert(prettyJson),
  );

  static String _encode(Object? value) {
    try {
      return _encoder.convert(value);
    } on JsonUnsupportedObjectError {
      return const JsonEncoder.withIndent('  ', _toEncodable).convert(value);
    }
  }

  static Object? _toEncodable(Object? value) => value.toString();

  @override
  String toString() =>
      'DataExport(${data.keys.join(', ')}, exportedAt: $exportedAt)';
}
