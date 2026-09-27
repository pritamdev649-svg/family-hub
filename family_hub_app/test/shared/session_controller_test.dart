import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/storage/local_cache.dart';
import 'package:family_hub/shared/data/auth_repository.dart';
import 'package:family_hub/shared/data/family_repository.dart';
import 'package:family_hub/shared/models/models.dart';
import 'package:family_hub/shared/session/session_controller.dart';

import 'models_test.dart' show familyJson, memberJson, userJson;
import 'shared_fakes.dart';

const _tokens = AuthTokens(accessToken: 'acc', refreshToken: 'ref');

Map<String, dynamic> _tokensJson() => {
  'accessToken': 'acc2',
  'refreshToken': 'ref2',
  'expiresIn': 900,
};

Map<String, dynamic> _meJson({
  Map<String, dynamic> user = const {},
  Map<String, dynamic> member = const {},
  bool withFamily = true,
}) => {
  'user': userJson({'memberId': 'm1', 'familyId': 'f1', ...user}),
  'member': withFamily
      ? memberJson({'id': 'm1', 'familyId': 'f1', 'role': 'admin', ...member})
      : null,
  'family': withFamily ? familyJson() : null,
};

/// A `session.last` entry in LocalCache's on-disk format (`{t, v}`).
String _cachedSessionPref(Map<String, dynamic> session) => jsonEncode({
  't': DateTime.now().toUtc().toIso8601String(),
  'v': SessionState.fromJson(session).toJson(),
});

void main() {
  late SessionHarness h;

  tearDown(() => h.dispose());

  group('restore (build)', () {
    test('no tokens → signed out without calling the API', () async {
      h = await SessionHarness.create();
      final s = await h.container.read(sessionControllerProvider.future);
      expect(s, SessionState.signedOut);
      expect(h.api.calls, isEmpty);
      expect(h.container.read(sessionUserIdProvider), isNull);
    });

    test('tokens → GET /auth/me, caches the session, registers push', () async {
      h = await SessionHarness.create(
        tokens: _tokens,
        handlers: {'GET /auth/me': (_) => _meJson()},
      );
      final s = await h.container.read(sessionControllerProvider.future);
      expect(s.isComplete, isTrue);
      expect(s.member?.id, 'm1');
      await settle();
      expect(h.push.registrations, 1);
      final cached = h.cache.readMap(SessionController.cacheKey);
      expect(cached, isNotNull);
      // The member's live location is never written to disk.
      expect((cached!['member'] as Map)['lastLocation'], isNull);
      expect(h.container.read(isAdminProvider), isTrue);
      expect(h.container.read(currentCountryProvider).code, 'IN');
      expect(h.container.read(currentFamilyProvider)?.name, 'Sharma Family');
    });

    test('network error → last cached session (offline start)', () async {
      h = await SessionHarness.create(
        tokens: _tokens,
        prefs: {
          '${LocalCache.prefix}${SessionController.cacheKey}':
              _cachedSessionPref(_meJson()),
        },
        handlers: {'GET /auth/me': (_) => throw const ApiException.network()},
      );
      final s = await h.container.read(sessionControllerProvider.future);
      expect(s.isComplete, isTrue);
      expect(s.user?.id, 'u1');
      await settle();
      expect(h.push.registrations, 0, reason: 'only after an online restore');
      expect(h.tokens.tokens, isNotNull);
    });

    test(
      'offline start, then refreshMe online updates and registers push',
      () async {
        var online = false;
        h = await SessionHarness.create(
          tokens: _tokens,
          prefs: {
            '${LocalCache.prefix}${SessionController.cacheKey}':
                _cachedSessionPref(_meJson()),
          },
          handlers: {
            'GET /auth/me': (_) => online
                ? _meJson(member: {'designation': 'CEO'})
                : throw const ApiException.network(),
          },
        );
        await h.container.read(sessionControllerProvider.future);
        final notifier = h.container.read(sessionControllerProvider.notifier);
        await expectLater(notifier.refreshMe(), throwsA(isA<ApiException>()));
        expect(
          h.container.read(sessionControllerProvider).value?.isSignedIn,
          isTrue,
          reason: 'a failed refresh keeps the session',
        );

        online = true;
        await notifier.refreshMe();
        await settle();
        expect(h.container.read(currentMemberProvider)?.designation, 'CEO');
        expect(h.push.registrations, 1);
        await notifier.refreshMe();
        await settle();
        expect(h.push.registrations, 1, reason: 'once per session');
      },
    );

    test('401 → signed out, tokens and cache cleared', () async {
      h = await SessionHarness.create(
        tokens: _tokens,
        prefs: {
          '${LocalCache.prefix}${SessionController.cacheKey}':
              _cachedSessionPref(_meJson()),
        },
        handlers: {
          'GET /auth/me': (_) => throw const ApiException(
            code: ApiErrorCode.unauthorized,
            statusCode: 401,
          ),
        },
      );
      final s = await h.container.read(sessionControllerProvider.future);
      expect(s, SessionState.signedOut);
      expect(h.tokens.tokens, isNull);
      expect(h.cache.contains(SessionController.cacheKey), isFalse);
    });

    test(
      'non-transient error without cache → AsyncError (no retry loop)',
      () async {
        h = await SessionHarness.create(
          tokens: _tokens,
          handlers: {
            'GET /auth/me': (_) => throw const ApiException(
              code: ApiErrorCode.forbidden,
              statusCode: 403,
            ),
          },
        );
        await expectLater(
          h.container.read(sessionControllerProvider.future),
          throwsA(isA<ApiException>()),
        );
        expect(h.container.read(sessionControllerProvider).hasError, isTrue);
        expect(h.api.callsTo('GET /auth/me').length, 1);
      },
    );
  });

  group('login / register', () {
    test(
      'login fetches member + family and never emits AsyncLoading',
      () async {
        h = await SessionHarness.create(
          handlers: {
            'POST /auth/login': (_) => {
              'user': userJson(),
              'tokens': _tokensJson(),
            },
            'GET /auth/me': (_) => _meJson(),
          },
        );
        await h.container.read(sessionControllerProvider.future);
        final states = <AsyncValue<SessionState>>[];
        h.container.listen(
          sessionControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: false,
        );

        await h.container
            .read(sessionControllerProvider.notifier)
            .login(email: ' Amit@Example.com ', password: 'demo1234');

        expect(states, isNotEmpty);
        expect(states.any((s) => s.isLoading), isFalse);
        final s = h.container.read(sessionControllerProvider).value!;
        expect(s.isComplete, isTrue);
        expect(h.tokens.tokens?.accessToken, 'acc2');
        final login = h.api.callsTo('POST /auth/login').single;
        expect(login.json['email'], 'amit@example.com');
        expect(login.json['password'], 'demo1234');
        await settle();
        expect(h.push.registrations, 1);
      },
    );

    test('login of a user without family skips /auth/me', () async {
      h = await SessionHarness.create(
        handlers: {
          'POST /auth/login': (_) => {
            'user': userJson({
              'familyId': null,
              'memberId': null,
              'role': null,
            }),
            'tokens': _tokensJson(),
          },
        },
      );
      await h.container.read(sessionControllerProvider.future);
      await h.container
          .read(sessionControllerProvider.notifier)
          .login(email: 'a@b.co', password: 'x');
      final s = h.container.read(sessionControllerProvider).value!;
      expect(s.needsFamily, isTrue);
      expect(h.api.callsTo('GET /auth/me'), isEmpty);
    });

    test('failed login rethrows and keeps signed out', () async {
      h = await SessionHarness.create(
        handlers: {
          'POST /auth/login': (_) => throw const ApiException(
            code: ApiErrorCode.invalidCredentials,
            statusCode: 401,
          ),
        },
      );
      await h.container.read(sessionControllerProvider.future);
      await expectLater(
        h.container
            .read(sessionControllerProvider.notifier)
            .login(email: 'a@b.co', password: 'bad'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.invalidCredentials,
          ),
        ),
      );
      expect(
        h.container.read(sessionControllerProvider).value,
        SessionState.signedOut,
      );
      expect(h.tokens.tokens, isNull);
    });

    test('login whose /auth/me fails drops the tokens', () async {
      h = await SessionHarness.create(
        handlers: {
          'POST /auth/login': (_) => {
            'user': userJson(),
            'tokens': _tokensJson(),
          },
          'GET /auth/me': (_) => throw const ApiException.network(),
        },
      );
      await h.container.read(sessionControllerProvider.future);
      await expectLater(
        h.container
            .read(sessionControllerProvider.notifier)
            .login(email: 'a@b.co', password: 'x'),
        throwsA(isA<ApiException>()),
      );
      expect(h.tokens.tokens, isNull);
      expect(
        h.container.read(sessionControllerProvider).value?.isSignedIn,
        isFalse,
      );
    });

    test('register (create) sends the contract body and signs in', () async {
      h = await SessionHarness.create(
        handlers: {
          'POST /auth/register': (_) => {
            ..._meJson(user: {'emailVerified': false}),
            'tokens': _tokensJson(),
          },
        },
      );
      await h.container.read(sessionControllerProvider.future);
      await h.container
          .read(sessionControllerProvider.notifier)
          .register(
            const RegisterRequest.create(
              name: ' Amit Sharma ',
              email: 'AMIT@example.com',
              password: 'Secret123',
              locale: 'hi',
              consentAccepted: true,
              family: CreateFamilyRequest(
                name: 'Sharma Family',
                country: 'in',
                currency: 'inr',
                timezone: 'Asia/Kolkata',
              ),
            ),
          );
      final body = h.api.callsTo('POST /auth/register').single.json;
      expect(body['mode'], 'create');
      expect(body['name'], 'Amit Sharma');
      expect(body['email'], 'amit@example.com');
      expect(body['consentAccepted'], isTrue);
      expect(body['inviteCode'], isNull);
      expect(body['family'], {
        'name': 'Sharma Family',
        'country': 'IN',
        'currency': 'INR',
        'timezone': 'Asia/Kolkata',
      });
      final s = h.container.read(sessionControllerProvider).value!;
      expect(s.needsEmailVerification, isTrue);
      expect(s.family?.id, 'f1');
      expect(h.api.callsTo('GET /auth/me'), isEmpty);
    });

    test('verifyEmail updates the user', () async {
      h = await SessionHarness.create(
        tokens: _tokens,
        handlers: {
          'GET /auth/me': (_) => _meJson(user: {'emailVerified': false}),
          'POST /auth/verify-email': (c) {
            expect(c.json['otp'], '123456');
            return {
              'user': userJson({'memberId': 'm1'}),
            };
          },
        },
      );
      final before = await h.container.read(sessionControllerProvider.future);
      expect(before.needsEmailVerification, isTrue);
      await h.container
          .read(sessionControllerProvider.notifier)
          .verifyEmail('123 456');
      final s = h.container.read(sessionControllerProvider).value!;
      expect(s.needsEmailVerification, isFalse);
      expect(s.isComplete, isTrue);
    });
  });

  group('sign out', () {
    test(
      'logout: unregister push → POST /auth/logout → clear tokens',
      () async {
        h = await SessionHarness.create(
          tokens: _tokens,
          handlers: {
            'GET /auth/me': (_) => _meJson(),
            'POST /auth/logout': (_) => null,
          },
        );
        await h.container.read(sessionControllerProvider.future);
        await settle();
        h.log.clear();

        await h.container.read(sessionControllerProvider.notifier).logout();

        expect(h.log, [
          'push unregister',
          'api POST /auth/logout',
          'tokens cleared',
        ]);
        expect(
          h.api.callsTo('POST /auth/logout').single.json['refreshToken'],
          'ref',
        );
        expect(
          h.container.read(sessionControllerProvider).value,
          SessionState.signedOut,
        );
        expect(h.cache.contains(SessionController.cacheKey), isFalse);
        expect(h.container.read(sessionUserIdProvider), isNull);
      },
    );

    test('logout still signs out when the server is unreachable', () async {
      h = await SessionHarness.create(
        tokens: _tokens,
        handlers: {
          'GET /auth/me': (_) => _meJson(),
          'POST /auth/logout': (_) => throw const ApiException.network(),
        },
      );
      await h.container.read(sessionControllerProvider.future);
      await h.container.read(sessionControllerProvider.notifier).logout();
      expect(h.tokens.tokens, isNull);
      expect(
        h.container.read(sessionControllerProvider).value,
        SessionState.signedOut,
      );
    });

    test('AuthEvents.sessionExpired signs out', () async {
      h = await SessionHarness.create(
        tokens: _tokens,
        handlers: {'GET /auth/me': (_) => _meJson()},
      );
      await h.container.read(sessionControllerProvider.future);
      h.events.emitSessionExpired();
      await settle();
      expect(
        h.container.read(sessionControllerProvider).value,
        SessionState.signedOut,
      );
      expect(h.cache.contains(SessionController.cacheKey), isFalse);
      expect(h.push.unregistrations, 1);
    });

    test('refreshMe with 401 signs out', () async {
      var calls = 0;
      h = await SessionHarness.create(
        tokens: _tokens,
        handlers: {
          'GET /auth/me': (_) {
            if (calls++ == 0) return _meJson();
            throw const ApiException(
              code: ApiErrorCode.unauthorized,
              statusCode: 401,
            );
          },
        },
      );
      await h.container.read(sessionControllerProvider.future);
      await h.container.read(sessionControllerProvider.notifier).refreshMe();
      expect(
        h.container.read(sessionControllerProvider).value,
        SessionState.signedOut,
      );
    });
  });

  group('session updates', () {
    test('applyMe merges own records, ignores others, bumps scopes', () async {
      h = await SessionHarness.create(
        tokens: _tokens,
        handlers: {'GET /auth/me': (_) => _meJson()},
      );
      final s = await h.container.read(sessionControllerProvider.future);
      final before = h.container.read(dataRefreshProvider);
      final notifier = h.container.read(sessionControllerProvider.notifier);

      await notifier.applyMe(null, s.member!.copyWith(id: 'someone-else'));
      expect(h.container.read(sessionControllerProvider).value, s);
      expect(h.container.read(dataRefreshProvider), before);

      final renamed = s.member!.copyWith(name: 'Amit S');
      await notifier.applyMe(null, renamed);
      expect(h.container.read(currentMemberProvider)?.name, 'Amit S');
      expect(
        h.container.read(dataRefreshProvider)[DataScope.members],
        before[DataScope.members]! + 1,
      );

      final fam = s.family!.copyWith(name: 'The Sharmas');
      await notifier.applyMe(null, null, fam);
      expect(h.container.read(currentFamilyProvider)?.name, 'The Sharmas');
      expect(
        h.container.read(dataRefreshProvider)[DataScope.family],
        before[DataScope.family]! + 1,
      );

      final cached = h.cache.read(
        SessionController.cacheKey,
        (j) => SessionState.fromJson(Map<String, dynamic>.from(j as Map)),
      );
      expect(cached?.family?.name, 'The Sharmas');
    });

    test('createFamily switches the session and resets every scope', () async {
      h = await SessionHarness.create(
        tokens: _tokens,
        handlers: {
          'GET /auth/me': (_) => _meJson(
            withFamily: false,
            user: {'familyId': null, 'memberId': null, 'role': null},
          ),
          'POST /family': (c) {
            expect(c.json['country'], 'DE');
            return _meJson();
          },
        },
      );
      final s0 = await h.container.read(sessionControllerProvider.future);
      expect(s0.needsFamily, isTrue);
      final before = h.container.read(dataRefreshProvider);
      await h.container
          .read(sessionControllerProvider.notifier)
          .createFamily(
            const CreateFamilyRequest(
              name: 'X',
              country: 'de',
              currency: 'eur',
              timezone: 'Europe/Berlin',
            ),
          );
      expect(
        h.container.read(sessionControllerProvider).value?.isComplete,
        isTrue,
      );
      final after = h.container.read(dataRefreshProvider);
      for (final scope in DataScope.values) {
        expect(after[scope], greaterThan(before[scope]!), reason: '$scope');
      }
    });

    test('joinFamily normalises the invite code', () async {
      h = await SessionHarness.create(
        tokens: _tokens,
        handlers: {
          'GET /auth/me': (_) => _meJson(
            withFamily: false,
            user: {'familyId': null, 'memberId': null, 'role': null},
          ),
          'POST /family/join': (c) {
            expect(c.json['inviteCode'], 'DEMO2345');
            return _meJson(member: {'role': 'member'});
          },
        },
      );
      await h.container.read(sessionControllerProvider.future);
      await h.container
          .read(sessionControllerProvider.notifier)
          .joinFamily(' demo-2345 ');
      expect(h.container.read(isAdminProvider), isFalse);
      expect(h.container.read(currentMemberProvider)?.id, 'm1');
    });

    test('leaveFamily keeps the user without a family', () async {
      h = await SessionHarness.create(
        tokens: _tokens,
        handlers: {
          'GET /auth/me': (_) => _meJson(),
          'POST /me/leave-family': (_) => {
            'user': userJson({
              'familyId': null,
              'memberId': null,
              'role': null,
            }),
          },
        },
      );
      await h.container.read(sessionControllerProvider.future);
      await h.container.read(sessionControllerProvider.notifier).leaveFamily();
      final s = h.container.read(sessionControllerProvider).value!;
      expect(s.needsFamily, isTrue);
      expect(s.member, isNull);
      expect(h.container.read(currentCountryProvider).code, 'IN');
    });
  });

  group('members providers', () {
    test('empty when signed out', () async {
      h = await SessionHarness.create();
      await h.container.read(sessionControllerProvider.future);
      expect(await h.container.read(membersProvider.future), isEmpty);
    });

    test(
      'load, refetch on markChanged, serve memberById from the list',
      () async {
        h = await SessionHarness.create(
          tokens: _tokens,
          handlers: {
            'GET /auth/me': (_) => _meJson(),
            'GET /family/members': (_) => [
              memberJson({'id': 'm1', 'role': 'admin'}),
              memberJson({'id': 'm2', 'name': 'Priya'}),
              {'name': 'no id'},
              'junk',
            ],
            'GET /family/members/m9': (_) =>
                memberJson({'id': 'm9', 'name': 'Kamla'}),
          },
        );
        await h.container.read(sessionControllerProvider.future);
        final sub = h.container.listen(membersProvider, (_, _) {});
        final members = await h.container.read(membersProvider.future);
        expect(members.map((m) => m.id), ['m1', 'm2']);

        final priya = await h.container.read(memberByIdProvider('m2').future);
        expect(priya.name, 'Priya');
        expect(h.api.callsTo('GET /family/members/m2'), isEmpty);

        final kamla = await h.container.read(memberByIdProvider('m9').future);
        expect(kamla.name, 'Kamla');

        h.container.read(dataRefreshProvider.notifier).markChanged({
          DataScope.members,
        });
        await h.container.read(membersProvider.future);
        expect(h.api.callsTo('GET /family/members').length, 2);
        sub.close();
      },
    );

    test('NOT_FOUND surfaces immediately (no retry spinner)', () async {
      h = await SessionHarness.create(
        tokens: _tokens,
        handlers: {
          'GET /auth/me': (_) => _meJson(),
          'GET /family/members': (_) => [
            memberJson({'id': 'm1'}),
          ],
        },
      );
      await h.container.read(sessionControllerProvider.future);
      await expectLater(
        h.container.read(memberByIdProvider('missing').future),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.notFound,
          ),
        ),
      );
      expect(
        h.container.read(memberByIdProvider('missing')).isLoading,
        isFalse,
      );
    });
  });
}
