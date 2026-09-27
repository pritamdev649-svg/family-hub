import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/utils/date_x.dart';

void main() {
  group('DateX', () {
    test('startOfDay / endOfDay keep the zone', () {
      final d = DateTime(2026, 9, 26, 15, 30, 12);
      expect(d.startOfDay, DateTime(2026, 9, 26));
      expect(d.endOfDay, DateTime(2026, 9, 26, 23, 59, 59, 999, 999));
      final u = DateTime.utc(2026, 9, 26, 15);
      expect(u.startOfDay, DateTime.utc(2026, 9, 26));
      expect(u.startOfDay.isUtc, isTrue);
    });

    test('isSameDay', () {
      expect(
        DateTime(2026, 1, 1, 0, 1).isSameDay(DateTime(2026, 1, 1, 23)),
        isTrue,
      );
      expect(DateTime(2026, 1, 1).isSameDay(DateTime(2026, 1, 2)), isFalse);
      final local = DateTime(2026, 3, 4, 12);
      expect(
        local.toUtc().isSameDay(local),
        isTrue,
        reason: 'mixed zones → local',
      );
      expect(DateTime.now().isToday, isTrue);
    });

    test('isBeforeToday', () {
      expect(
        DateTime.now().subtract(const Duration(days: 1)).isBeforeToday,
        isTrue,
      );
      expect(DateTime.now().isBeforeToday, isFalse);
    });

    test('monthKey / startOfMonth / parseMonthKey', () {
      expect(DateTime(2026, 9, 26).monthKey, '2026-09');
      expect(DateTime(987, 12).monthKey, '0987-12');
      expect(DateTime(2026, 9, 26, 10).startOfMonth, DateTime(2026, 9));
      expect(parseMonthKey('2026-09'), DateTime(2026, 9));
      expect(parseMonthKey('2026-13'), isNull);
      expect(parseMonthKey('2026-9'), isNull);
      expect(parseMonthKey(null), isNull);
    });

    test('addMonths clamps the day and crosses years', () {
      expect(DateTime(2026, 1, 31).addMonths(1), DateTime(2026, 2, 28));
      expect(DateTime(2024, 1, 31).addMonths(1), DateTime(2024, 2, 29));
      expect(DateTime(2026, 3, 31).addMonths(-1), DateTime(2026, 2, 28));
      expect(DateTime(2026, 11, 15).addMonths(3), DateTime(2027, 2, 15));
      expect(DateTime(2026, 1, 15).addMonths(-13), DateTime(2024, 12, 15));
      expect(
        DateTime(2026, 5, 10, 8, 30).addMonths(0),
        DateTime(2026, 5, 10, 8, 30),
      );
      expect(DateTime.utc(2026, 1, 31).addMonths(1).isUtc, isTrue);
    });

    test('toApiDate sends local midnight as UTC ISO', () {
      final iso = DateTime(2026, 9, 26, 18, 45).toApiDate();
      expect(DateTime.parse(iso).toLocal(), DateTime(2026, 9, 26));
      expect(iso, endsWith('Z'));
    });
  });

  group('ageFrom', () {
    final now = DateTime(2026, 9, 26);
    test('birthday boundaries', () {
      expect(ageFrom(DateTime(2010, 9, 26), now: now), 16);
      expect(ageFrom(DateTime(2010, 9, 27), now: now), 15);
      expect(ageFrom(DateTime(2010, 9, 25), now: now), 16);
      expect(ageFrom(DateTime(2000, 2, 29), now: DateTime(2026, 2, 28)), 25);
      expect(ageFrom(DateTime(2000, 2, 29), now: DateTime(2026, 3, 1)), 26);
    });
    test('null / future', () {
      expect(ageFrom(null), isNull);
      expect(ageFrom(DateTime(2030), now: now), isNull);
      expect(ageFrom(now, now: now), 0);
    });
    test('API UTC timestamps are read in local time', () {
      final dob = DateTime(2010, 5, 14).toUtc();
      expect(ageFrom(dob, now: DateTime(2026, 5, 14)), 16);
      expect(ageFrom(dob, now: DateTime(2026, 5, 13)), 15);
    });
  });
}
