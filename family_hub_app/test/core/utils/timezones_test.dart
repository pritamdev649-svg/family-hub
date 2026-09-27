import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/core/config/timezones.dart';

void main() {
  group('Timezones', () {
    test('every country has zones and a default', () {
      for (final c in Countries.all) {
        final zones = Timezones.forCountry(c.code);
        expect(zones, isNotEmpty, reason: c.code);
        expect(Timezones.defaultFor(c.code), zones.first);
        for (final z in zones) {
          expect(Timezones.all, contains(z), reason: '$z missing from all');
        }
      }
    });

    test('examples and fallbacks', () {
      expect(Timezones.defaultFor('IN'), 'Asia/Kolkata');
      expect(
        Timezones.forCountry('us'),
        containsAll([
          'America/New_York',
          'America/Chicago',
          'America/Denver',
          'America/Los_Angeles',
          'America/Anchorage',
          'Pacific/Honolulu',
        ]),
      );
      expect(Timezones.forCountry('ZZ'), ['UTC']);
      expect(Timezones.defaultFor(null), 'UTC');
      expect(
        Timezones.normalizeFor('US', 'America/Chicago'),
        'America/Chicago',
      );
      expect(Timezones.normalizeFor('US', 'Asia/Kolkata'), 'America/New_York');
      expect(Timezones.cityName('America/Los_Angeles'), 'Los Angeles');
      expect(Timezones.isKnown('Asia/Kolkata'), isTrue);
      expect(Timezones.isKnown('Mars/Base'), isFalse);
    });

    test('all is sorted and unique', () {
      final sorted = [...Timezones.all]..sort();
      expect(Timezones.all, sorted);
      expect(Timezones.all.toSet().length, Timezones.all.length);
    });
  });
}
