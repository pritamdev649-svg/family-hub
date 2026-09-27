import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/shared/json.dart';
import 'package:family_hub/shared/models/member.dart';

enum _Cat { groceries, otherIncome, householdHelp }

void main() {
  group('parseDate', () {
    test('parses ISO strings as UTC', () {
      final d = parseDate('2026-09-26T10:15:00.000Z')!;
      expect(d.isUtc, isTrue);
      expect(d, DateTime.utc(2026, 9, 26, 10, 15));
    });

    test('accepts DateTime and epoch millis', () {
      final now = DateTime.utc(2026, 1, 2);
      expect(parseDate(now), same(now));
      expect(parseDate(now.millisecondsSinceEpoch), now);
      expect(parseDate(now.millisecondsSinceEpoch.toDouble()), now);
    });

    test('returns null for junk', () {
      for (final v in [
        null,
        '',
        '   ',
        'not a date',
        true,
        {},
        [],
        double.nan,
      ]) {
        expect(parseDate(v), isNull, reason: '$v');
      }
    });

    test('parseDateOr falls back', () {
      final fb = DateTime.utc(2000);
      expect(parseDateOr(null, fb), fb);
      expect(parseDateOr('x', fb), fb);
    });
  });

  group('scalars', () {
    test('asString', () {
      expect(asString('a'), 'a');
      expect(asString(''), '');
      expect(asString(12), '12');
      expect(asString(true), 'true');
      expect(asString(null), isNull);
      expect(asString({'a': 1}), isNull);
      expect(asString([1]), isNull);
      expect(asStringOr(null, 'fb'), 'fb');
    });

    test('asNonEmptyString drops blanks', () {
      expect(asNonEmptyString(''), isNull);
      expect(asNonEmptyString('  '), isNull);
      expect(asNonEmptyString(' x '), ' x ');
    });

    test('asDouble', () {
      expect(asDouble(1), 1.0);
      expect(asDouble(1.5), 1.5);
      expect(asDouble('2.25'), 2.25);
      expect(asDouble('abc'), 0);
      expect(asDouble(null, 7), 7);
      expect(asDouble(double.infinity, 3), 3);
      expect(asDoubleOrNull(null), isNull);
    });

    test('asInt', () {
      expect(asInt(3), 3);
      expect(asInt(2.6), 3);
      expect(asInt('42'), 42);
      expect(asInt('4.4'), 4);
      expect(asInt('x', 9), 9);
      expect(asInt(double.nan, 1), 1);
    });

    test('asBool', () {
      expect(asBool(true), isTrue);
      expect(asBool('true'), isTrue);
      expect(asBool('YES'), isTrue);
      expect(asBool('0', true), isFalse);
      expect(asBool(1), isTrue);
      expect(asBool(0, true), isFalse);
      expect(asBool('maybe', true), isTrue);
      expect(asBool(null), isFalse);
    });
  });

  group('collections', () {
    test('asList maps lists and ignores non-lists', () {
      expect(asList<int>([1, '2', 3.2], (e) => asInt(e)), [1, 2, 3]);
      expect(asList<int>('nope', (e) => asInt(e)), isEmpty);
      expect(asList<int>(null, (e) => asInt(e)), isEmpty);
    });

    test('asMapList skips non-object entries', () {
      final out = asMapList<String>([
        {'id': 'a'},
        null,
        3,
        'x',
        {'id': 'b'},
      ], (m) => m['id'] as String);
      expect(out, ['a', 'b']);
    });

    test('asStringList drops nulls, blanks and objects', () {
      expect(
        asStringList([
          'a',
          null,
          '',
          2,
          {'x': 1},
          ' b',
        ]),
        ['a', '2', ' b'],
      );
      expect(asStringList({'a': 1}), isEmpty);
    });

    test('asMap converts key types and rejects non-maps', () {
      expect(asMap({'a': 1}), {'a': 1});
      expect(asMap({1: 'x'}), {'1': 'x'});
      expect(asMap(null), isEmpty);
      expect(asMap([1]), isEmpty);
    });
  });

  group('enums', () {
    test('enumByName accepts dart names, snake_case and any case', () {
      expect(
        enumByName(
          LocationSharingMode.values,
          'sos_only',
          LocationSharingMode.never,
        ),
        LocationSharingMode.sosOnly,
      );
      expect(
        enumByName(
          LocationSharingMode.values,
          'sosOnly',
          LocationSharingMode.never,
        ),
        LocationSharingMode.sosOnly,
      );
      expect(
        enumByName(
          LocationSharingMode.values,
          'SOS-ONLY',
          LocationSharingMode.never,
        ),
        LocationSharingMode.sosOnly,
      );
      expect(
        enumByName(_Cat.values, 'other_income', _Cat.groceries),
        _Cat.otherIncome,
      );
      expect(
        enumByName(_Cat.values, 'household_help', _Cat.groceries),
        _Cat.householdHelp,
      );
    });

    test('enumByName falls back on unknown / missing', () {
      expect(
        enumByName(MemberRole.values, 'owner', MemberRole.member),
        MemberRole.member,
      );
      expect(
        enumByName(MemberRole.values, null, MemberRole.member),
        MemberRole.member,
      );
      expect(
        enumByName(MemberRole.values, 3, MemberRole.member),
        MemberRole.member,
      );
      expect(enumByNameOrNull(Gender.values, ''), isNull);
      expect(enumByNameOrNull(Gender.values, MemberRole.admin), isNull);
      expect(enumByNameOrNull(Gender.values, Gender.female), Gender.female);
    });

    test('enumWireName produces snake_case', () {
      expect(enumWireName(LocationSharingMode.sosOnly), 'sos_only');
      expect(enumWireName(LocationSharingMode.always), 'always');
      expect(enumWireName(_Cat.otherIncome), 'other_income');
    });
  });

  group('dates for the API', () {
    test('isoOrNull converts to UTC ISO', () {
      expect(isoOrNull(null), isNull);
      expect(
        isoOrNull(DateTime.utc(2026, 9, 26, 10, 15)),
        '2026-09-26T10:15:00.000Z',
      );
      final local = DateTime(2026, 9, 26);
      expect(isoOrNull(local), local.toUtc().toIso8601String());
      expect(isoOrNull(local)!.endsWith('Z'), isTrue);
    });

    test('calendarDate recovers the intended day for any viewer', () {
      // Server seed: UTC midnight.
      expect(calendarDate(DateTime.utc(2010, 5, 14)), DateTime(2010, 5, 14));
      // Sent from India (UTC+5:30): local midnight → previous day 18:30Z.
      expect(
        calendarDate(DateTime.utc(2010, 5, 13, 18, 30)),
        DateTime(2010, 5, 14),
      );
      // Sent from New York (UTC-5): local midnight → 05:00Z same day.
      expect(calendarDate(DateTime.utc(2010, 5, 14, 5)), DateTime(2010, 5, 14));
      // A local midnight value on this device.
      expect(calendarDate(DateTime(2010, 5, 14)), DateTime(2010, 5, 14));
      expect(calendarDate(null), isNull);
    });
  });
}
