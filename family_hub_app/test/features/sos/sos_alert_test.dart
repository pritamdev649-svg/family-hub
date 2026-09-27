import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/features/sos/domain/sos_alert.dart';

void main() {
  final full = <String, dynamic>{
    'id': 'a1',
    'memberId': 'm1',
    'memberName': ' Priya ',
    'memberPhone': '+919876543211',
    'memberAvatarUrl': '',
    'status': 'active',
    'message': 'Car broke down',
    'locationShared': true,
    'lastLocation': {
      'lat': 28.6,
      'lng': 77.2,
      'accuracy': 10,
      'recordedAt': '2026-09-27T10:01:00.000Z',
    },
    'trail': [
      {'lat': 28.5, 'lng': 77.1, 'recordedAt': '2026-09-27T10:00:00.000Z'},
      {'lat': 'x', 'lng': 77.1},
      null,
      {'lat': 95, 'lng': 0},
      {'lat': 28.6, 'lng': 77.2, 'accuracy': 10},
    ],
    'startedAt': '2026-09-27T10:00:00.000Z',
    'expiresAt': '2026-09-27T10:15:00.000Z',
    'resolvedAt': null,
    'resolvedById': null,
    'resolution': null,
    'extra': 'ignored',
  };

  group('SosAlert.fromJson', () {
    test('parses the contract shape', () {
      final a = SosAlert.fromJson(full);
      expect(a.id, 'a1');
      expect(a.memberId, 'm1');
      expect(a.memberName, 'Priya');
      expect(a.memberPhone, '+919876543211');
      expect(a.memberAvatarUrl, isNull, reason: 'blank → null');
      expect(a.status, SosStatus.active);
      expect(a.message, 'Car broke down');
      expect(a.locationShared, isTrue);
      expect(a.lastLocation?.lat, 28.6);
      expect(a.lastLocation?.accuracy, 10);
      expect(a.startedAt, DateTime.utc(2026, 9, 27, 10));
      expect(a.expiresAt, DateTime.utc(2026, 9, 27, 10, 15));
      expect(a.resolution, isNull);
      expect(a.hasLocation, isTrue);
    });

    test('drops invalid trail points', () {
      final a = SosAlert.fromJson(full);
      expect(a.trail, hasLength(2));
      expect(a.trail.first.lat, 28.5);
    });

    test('is lenient with missing / unknown fields', () {
      final a = SosAlert.fromJson(const {
        'id': 'a2',
        'status': 'escalated',
        'resolution': 'who-knows',
      });
      expect(a.memberId, '');
      expect(a.memberName, isNull);
      expect(a.status, SosStatus.expired, reason: 'unknown → not active');
      expect(a.resolution, isNull);
      expect(a.locationShared, isFalse);
      expect(a.trail, isEmpty);
      expect(a.startedAt, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      expect(
        a.expiresAt,
        a.startedAt.add(const Duration(minutes: 15)),
        reason: 'missing expiresAt → startedAt + 15 min',
      );
    });

    test('maps snake_case resolutions', () {
      for (final (wire, value) in [
        ('safe', SosResolution.safe),
        ('false_alarm', SosResolution.falseAlarm),
        ('helped', SosResolution.helped),
      ]) {
        final a = SosAlert.fromJson({
          ...full,
          'status': 'resolved',
          'resolution': wire,
        });
        expect(a.resolution, value);
        expect(a.resolution?.wireName, wire);
      }
    });

    test('round-trips through toJson', () {
      final a = SosAlert.fromJson(full);
      final b = SosAlert.fromJson(a.toJson());
      expect(b, a);
      expect(b.hashCode, a.hashCode);
    });
  });

  group('status at a time', () {
    final a = SosAlert.fromJson(full);
    final start = DateTime.utc(2026, 9, 27, 10);

    test('active inside the window', () {
      final now = start.add(const Duration(minutes: 5));
      expect(a.isActiveAt(now), isTrue);
      expect(a.effectiveStatusAt(now), SosStatus.active);
      expect(a.remainingAt(now), const Duration(minutes: 10));
      expect(a.endedAtAsOf(now), isNull);
    });

    test('expired once expiresAt passed (lazy expiry)', () {
      final now = start.add(const Duration(minutes: 15));
      expect(a.isActiveAt(now), isFalse);
      expect(a.effectiveStatusAt(now), SosStatus.expired);
      expect(a.remainingAt(now), Duration.zero);
      expect(a.endedAtAsOf(now), a.expiresAt);
    });

    test('resolved alerts are never active', () {
      final resolvedAt = start.add(const Duration(minutes: 2));
      final r = a.copyWith(
        status: SosStatus.resolved,
        resolvedAt: () => resolvedAt,
        resolution: () => SosResolution.safe,
      );
      expect(r.isActiveAt(start), isFalse);
      expect(r.effectiveStatusAt(start), SosStatus.resolved);
      expect(r.endedAtAsOf(start), resolvedAt);
    });

    test('ownership and ordering', () {
      expect(a.isOwnedBy('m1'), isTrue);
      expect(a.isOwnedBy('m2'), isFalse);
      expect(a.isOwnedBy(null), isFalse);
      final older = a.copyWith(
        id: 'a0',
        startedAt: start.subtract(const Duration(days: 1)),
      );
      final list = [older, a]..sort(SosAlert.compareNewestFirst);
      expect(list.map((e) => e.id), ['a1', 'a0']);
    });
  });
}
