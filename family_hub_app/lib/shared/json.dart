/// Defensive JSON helpers shared by every model's `fromJson` / `toJson`.
///
/// Rules (docs/05-FLUTTER_GUIDE.md §1.6): parsing never throws on missing,
/// `null`, wrongly-typed or extra fields. Unknown enum values fall back to a
/// caller-supplied default, missing values become `null` or a sensible
/// default. Use these helpers instead of `json['x'] as String` casts.
library;

/// Parses an ISO-8601 string (`2026-09-26T10:15:00.000Z`), a `DateTime`, or
/// an epoch timestamp in **milliseconds** (int/double). Returns `null` for
/// anything else (including empty / malformed strings).
///
/// ISO strings with a `Z` / offset are returned as UTC `DateTime`s; convert
/// with `.toLocal()` before displaying (the `Fmt` helpers do this).
DateTime? parseDate(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is num) {
    if (!v.isFinite) return null;
    return DateTime.fromMillisecondsSinceEpoch(v.round(), isUtc: true);
  }
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
  return null;
}

/// Like [parseDate] but returns [fallback] when the value is missing/invalid.
DateTime parseDateOr(Object? v, DateTime fallback) => parseDate(v) ?? fallback;

/// Returns strings unchanged, stringifies numbers and booleans, and returns
/// `null` for `null`, maps, lists and other objects.
String? asString(Object? v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is num || v is bool) return v.toString();
  return null;
}

/// Like [asString] but returns [fallback] instead of `null`.
String asStringOr(Object? v, String fallback) => asString(v) ?? fallback;

/// Like [asString] but also maps blank strings (`""`, `"   "`) to `null`.
/// Use it for optional free-text fields (phone, email, avatarUrl, …) so the
/// UI can simply test for `null`.
String? asNonEmptyString(Object? v) {
  final s = asString(v);
  if (s == null || s.trim().isEmpty) return null;
  return s;
}

/// Parses numbers and numeric strings. `NaN` / infinity → [fallback].
double asDouble(Object? v, [double fallback = 0]) {
  final d = asDoubleOrNull(v);
  return d ?? fallback;
}

/// Nullable variant of [asDouble] (e.g. an optional GPS `accuracy`).
double? asDoubleOrNull(Object? v) {
  double? d;
  if (v is num) {
    d = v.toDouble();
  } else if (v is String) {
    d = double.tryParse(v.trim());
  }
  if (d == null || !d.isFinite) return null;
  return d;
}

/// Parses ints, whole/rounded doubles and numeric strings.
int asInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is double) return v.isFinite ? v.round() : fallback;
  if (v is String) {
    final s = v.trim();
    final i = int.tryParse(s);
    if (i != null) return i;
    final d = double.tryParse(s);
    if (d != null && d.isFinite) return d.round();
  }
  return fallback;
}

/// Parses booleans, `"true"`/`"false"`/`"1"`/`"0"`/`"yes"`/`"no"` strings and
/// numbers (non-zero = true).
bool asBool(Object? v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    switch (v.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
        return true;
      case 'false':
      case '0':
      case 'no':
        return false;
    }
  }
  return fallback;
}

/// Maps every element of a JSON array with [map]. Anything that is not a list
/// yields an empty list. `null` elements are passed to [map] unchanged so the
/// mapper decides; use [asMapList] / [asStringList] to skip junk entries.
List<T> asList<T>(Object? v, T Function(Object? e) map) {
  if (v is! List) return <T>[];
  return v.map(map).toList(growable: false);
}

/// Maps every **object** element of a JSON array with [map]; non-object
/// entries (null, numbers, strings) are skipped.
List<T> asMapList<T>(Object? v, T Function(Map<String, dynamic> e) map) {
  if (v is! List) return <T>[];
  return [
    for (final e in v)
      if (e is Map) map(asMap(e)),
  ];
}

/// Non-blank strings of a JSON array (numbers are stringified, nulls,
/// objects and blank strings are dropped). Non-lists → empty list.
List<String> asStringList(Object? v) {
  if (v is! List) return const <String>[];
  return [for (final e in v) ?asNonEmptyString(e)];
}

/// Returns a `Map<String, dynamic>` view of a JSON object. Maps with
/// non-string keys are copied with stringified keys; anything else → `{}`.
Map<String, dynamic> asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    return {for (final e in v.entries) e.key.toString(): e.value};
  }
  return <String, dynamic>{};
}

/// Normalises an identifier for loose enum matching: lower-case, without
/// `_`, `-` and spaces. `sos_only`, `SOS-ONLY` and `sosOnly` all become
/// `sosonly`.
String _enumKey(String s) => s.replaceAll(RegExp(r'[_\-\s]'), '').toLowerCase();

/// Resolves an enum from its wire value. Accepts the Dart name (`sosOnly`),
/// snake_case (`sos_only`), kebab-case and any letter case. Unknown / missing
/// values → [fallback]. Passing an instance of the enum returns it.
T enumByName<T extends Enum>(List<T> values, Object? v, T fallback) =>
    enumByNameOrNull(values, v) ?? fallback;

/// Nullable variant of [enumByName] for optional enums (e.g. `gender`).
T? enumByNameOrNull<T extends Enum>(List<T> values, Object? v) {
  if (v is T) return v;
  final s = asString(v);
  if (s == null || s.trim().isEmpty) return null;
  final key = _enumKey(s);
  for (final value in values) {
    if (_enumKey(value.name) == key) return value;
  }
  return null;
}

/// The API's snake_case wire name of an enum value: `sosOnly` → `sos_only`,
/// `admin` → `admin`, `otherIncome` → `other_income`.
String enumWireName(Enum value) => value.name.replaceAllMapped(
  RegExp('[A-Z]'),
  (m) => '_${m[0]!.toLowerCase()}',
);

/// UTC ISO-8601 string for the API (`2026-09-26T10:15:00.000Z`) or `null`.
String? isoOrNull(DateTime? d) => d?.toUtc().toIso8601String();

/// The calendar day of a **date-only** wire value (`dateOfBirth`, `dueDate`,
/// ledger `date`, `targetDate`) as a local `DateTime(y, m, d)` at midnight.
///
/// The app sends "local midnight converted to UTC" and server seeds use UTC
/// midnight, so the stored instant is always within ±12 h of UTC midnight of
/// the intended day. Rounding to the nearest UTC midnight recovers that day
/// independently of the *viewer's* time zone (a birthday entered in India
/// shows the same date on a phone in the US). Only offsets beyond ±12 h
/// (e.g. Kiribati, NZ summer time) can shift by a day.
DateTime? calendarDate(DateTime? d) {
  if (d == null) return null;
  final shifted = d.toUtc().add(const Duration(hours: 12));
  return DateTime(shifted.year, shifted.month, shifted.day);
}
