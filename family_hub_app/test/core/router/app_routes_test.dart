import 'package:family_hub/core/router/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppRoutes builders', () {
    test('path parameters are substituted and encoded', () {
      expect(AppRoutes.taskDetail('abc123'), '/tasks/abc123');
      expect(AppRoutes.taskEdit('abc123'), '/tasks/abc123/edit');
      expect(AppRoutes.goalDetail('g1'), '/money/goals/g1');
      expect(AppRoutes.goalEdit('g1'), '/money/goals/g1/edit');
      expect(AppRoutes.memberDetail('m1'), '/members/m1');
      expect(AppRoutes.memberEdit('m1'), '/members/m1/edit');
      expect(AppRoutes.noticeEdit('n1'), '/notices/n1/edit');
      expect(AppRoutes.emergencyCard('m1'), '/emergency-cards/m1');
      expect(AppRoutes.emergencyCardEdit('m1'), '/emergency-cards/m1/edit');
      expect(AppRoutes.sosAlert('s1'), '/sos/alert/s1');
      // Never produces extra path segments from untrusted ids.
      expect(AppRoutes.taskDetail('a/b c'), '/tasks/a%2Fb%20c');
    });

    test('optional query parameters are only added when set', () {
      expect(AppRoutes.taskNew(), '/tasks/new');
      expect(AppRoutes.taskNew(assigneeId: ''), '/tasks/new');
      expect(AppRoutes.taskNew(assigneeId: 'm1'), '/tasks/new?assigneeId=m1');
      expect(AppRoutes.ledgerEntryNew(), '/money/entries/new');
      expect(
        AppRoutes.ledgerEntryNew(type: 'income'),
        '/money/entries/new?type=income',
      );
      expect(AppRoutes.register(), '/register');
      expect(
        AppRoutes.register(mode: AppRoutes.registerModeJoin, code: 'DEMO2345'),
        '/register?mode=join&code=DEMO2345',
      );
    });

    test('pattern constants use the documented parameter names', () {
      expect(AppRoutes.taskDetailPath, '/tasks/:id');
      expect(AppRoutes.taskEditPath, '/tasks/:id/edit');
      expect(AppRoutes.goalDetailPath, '/money/goals/:id');
      expect(AppRoutes.memberDetailPath, '/members/:id');
      expect(AppRoutes.noticeEditPath, '/notices/:id/edit');
      expect(AppRoutes.emergencyCardPath, '/emergency-cards/:memberId');
      expect(
        AppRoutes.emergencyCardEditPath,
        '/emergency-cards/:memberId/edit',
      );
      expect(AppRoutes.sosAlertPath, '/sos/alert/:id');
    });

    test('every push-notification route from the contract is buildable', () {
      // docs/03-API_CONTRACT.md §13
      expect(AppRoutes.sosAlert('x'), '/sos/alert/x');
      expect(AppRoutes.taskDetail('x'), '/tasks/x');
      expect(AppRoutes.notices, '/notices');
      expect(AppRoutes.money, '/money');
      expect(AppRoutes.memberDetail('x'), '/members/x');
    });
  });

  group('AppRoutes groups', () {
    test('tabs are in navigation-bar order', () {
      expect(AppRoutes.tabs, ['/home', '/tasks', '/sos', '/money', '/more']);
    });

    test('isPublic / isSignedOutPath', () {
      for (final p in [
        '/splash',
        '/welcome',
        '/login',
        '/register',
        '/forgot-password',
        '/verify-email',
        '/family-setup',
      ]) {
        expect(AppRoutes.isPublic(p), isTrue, reason: p);
      }
      expect(AppRoutes.isPublic('/login/'), isTrue);
      expect(AppRoutes.isPublic('/home'), isFalse);
      expect(AppRoutes.isPublic('/tasks/1'), isFalse);

      expect(AppRoutes.isSignedOutPath('/login'), isTrue);
      expect(AppRoutes.isSignedOutPath('/verify-email'), isFalse);
      expect(AppRoutes.isSignedOutPath('/splash'), isFalse);
    });

    test('isTabRoot ignores query and trailing slash', () {
      expect(AppRoutes.isTabRoot('/money'), isTrue);
      expect(AppRoutes.isTabRoot('/money/'), isTrue);
      expect(AppRoutes.isTabRoot('/money?x=1'), isTrue);
      expect(AppRoutes.isTabRoot('/money/entries'), isFalse);
      expect(AppRoutes.isTabRoot('/notices'), isFalse);
    });
  });

  group('AppRoutes.sanitizeLocation', () {
    test('accepts in-app paths (with query) and normalises them', () {
      expect(AppRoutes.sanitizeLocation('/sos/alert/abc'), '/sos/alert/abc');
      expect(AppRoutes.sanitizeLocation('  /notices/ '), '/notices');
      expect(
        AppRoutes.sanitizeLocation('/tasks/new?assigneeId=m1'),
        '/tasks/new?assigneeId=m1',
      );
    });

    test(
      'rejects empty, external, protocol-relative and relative locations',
      () {
        for (final bad in <String?>[
          null,
          '',
          '   ',
          'https://evil.example/tasks',
          'javascript:alert(1)',
          '//evil.example/x',
          'tasks/1',
          '/tasks/../../etc',
          '/./tasks',
        ]) {
          expect(AppRoutes.sanitizeLocation(bad), isNull, reason: '$bad');
        }
      },
    );
  });
}
