/// Part of the day used for the dashboard greeting ("Good morning, Amit").
///
/// Boundaries (device local time): morning 05:00–11:59, afternoon
/// 12:00–16:59, evening 17:00–21:59, night 22:00–04:59. There is no "good
/// night" greeting (in many languages it means goodbye) — the night period
/// greets with a neutral "Hello".
enum GreetingPeriod {
  morning,
  afternoon,
  evening,
  night;

  /// Local hours at which a period starts, in day order.
  static const List<int> _startHours = [5, 12, 17, 22];

  static GreetingPeriod of(DateTime time) {
    final hour = time.toLocal().hour;
    if (hour >= 5 && hour < 12) return morning;
    if (hour >= 12 && hour < 17) return afternoon;
    if (hour >= 17 && hour < 22) return evening;
    return night;
  }

  /// The next local time after [time] at which the dashboard's
  /// time-dependent parts change: the start of a greeting period (05:00,
  /// 12:00, 17:00, 22:00) or midnight (the date, "today" and "this week"
  /// move on).
  static DateTime nextChangeAfter(DateTime time) {
    final t = time.toLocal();
    for (final hour in _startHours) {
      final start = DateTime(t.year, t.month, t.day, hour);
      if (start.isAfter(t)) return start;
    }
    // `DateTime` normalises day 32 etc., so this also rolls over months and
    // years.
    return DateTime(t.year, t.month, t.day + 1);
  }

  /// Whether [a] and [b] show the same greeting on the same local date.
  static bool sameSlot(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year &&
        la.month == lb.month &&
        la.day == lb.day &&
        of(la) == of(lb);
  }
}

/// The first word of [name] ("Amit Sharma" → "Amit"), or an empty string
/// for blank names. Whitespace of any script (incl. no-break / ideographic
/// spaces) separates words.
String firstNameOf(String? name) {
  final words = (name ?? '')
      .trim()
      .split(RegExp(r'[\s\u00A0\u3000]+'))
      .where((w) => w.isNotEmpty);
  return words.isEmpty ? '' : words.first;
}
