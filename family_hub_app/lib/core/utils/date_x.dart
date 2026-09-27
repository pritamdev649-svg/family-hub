/// Calendar helpers. All operate in the zone of the receiver (call
/// `.toLocal()` on API timestamps first — or use `Fmt`, which does).
extension DateX on DateTime {
  /// Midnight of the same calendar day (keeps UTC-ness).
  DateTime get startOfDay =>
      isUtc ? DateTime.utc(year, month, day) : DateTime(year, month, day);

  /// Last microsecond of the same calendar day.
  DateTime get endOfDay => startOfDay
      .add(const Duration(days: 1))
      .subtract(const Duration(microseconds: 1));

  /// Same calendar day. When one side is UTC and the other local, both are
  /// compared in local time.
  bool isSameDay(DateTime other) {
    final a = isUtc == other.isUtc ? this : toLocal();
    final b = isUtc == other.isUtc ? other : other.toLocal();
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool get isToday =>
      isSameDay(isUtc ? DateTime.now().toUtc() : DateTime.now());

  /// Strictly before today's midnight (e.g. an overdue due date).
  bool get isBeforeToday {
    final now = isUtc ? DateTime.now().toUtc() : DateTime.now();
    return isBefore(now.startOfDay);
  }

  /// `YYYY-MM` — the `month` query value of the ledger endpoints.
  String get monthKey =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  /// First day of the month, midnight (keeps UTC-ness).
  DateTime get startOfMonth =>
      isUtc ? DateTime.utc(year, month) : DateTime(year, month);

  /// Adds [n] calendar months (negative to go back), clamping the day to
  /// the target month's length: Jan 31 + 1 → Feb 28/29. Time is preserved.
  DateTime addMonths(int n) {
    final total = year * 12 + (month - 1) + n;
    final y = total ~/ 12;
    final m = total % 12 + 1;
    final lastDay = _daysInMonth(y, m);
    final d = day > lastDay ? lastDay : day;
    return isUtc
        ? DateTime.utc(y, m, d, hour, minute, second, millisecond, microsecond)
        : DateTime(y, m, d, hour, minute, second, millisecond, microsecond);
  }

  /// Local midnight of this calendar day as the UTC ISO string the API
  /// expects for date-only fields (`dueDate`, `date`, `dateOfBirth`…).
  String toApiDate() => DateTime(year, month, day).toUtc().toIso8601String();

  static int _daysInMonth(int y, int m) =>
      DateTime.utc(y, m + 1, 0).day; // day 0 of next month = last day
}

/// Parses a `YYYY-MM` month key to the first day of that month (local), or
/// null when malformed.
DateTime? parseMonthKey(String? key) {
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(key?.trim() ?? '');
  if (m == null) return null;
  final month = int.parse(m.group(2)!);
  if (month < 1 || month > 12) return null;
  return DateTime(int.parse(m.group(1)!), month);
}

/// Age in whole years on [now] (default: today), from a date of birth as
/// sent by the API. Null when [dob] is null or in the future.
int? ageFrom(DateTime? dob, {DateTime? now}) {
  if (dob == null) return null;
  final birth = dob.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  if (birth.isAfter(today)) return null;
  var age = today.year - birth.year;
  final hadBirthday =
      today.month > birth.month ||
      (today.month == birth.month && today.day >= birth.day);
  if (!hadBirthday) age--;
  return age < 0 ? null : age;
}
