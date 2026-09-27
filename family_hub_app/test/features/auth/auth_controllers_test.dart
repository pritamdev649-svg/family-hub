// Auth application layer with the real SessionController on top of fake
// repositories: cooldowns, AuthActions bookkeeping, the forgot-password
// controller and the session-expired notice.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/features/auth/application/auth_actions.dart';
import 'package:family_hub/features/auth/application/auth_cooldown.dart';
import 'package:family_hub/features/auth/application/forgot_password_controller.dart';
import 'package:family_hub/features/auth/application/session_expired_notice.dart';
import 'package:family_hub/shared/data/auth_repository.dart';
import 'package:family_hub/shared/data/family_repository.dart';
import 'package:family_hub/shared/models/models.dart';
import 'package:family_hub/shared/session/session_controller.dart';

import 'auth_test_utils.dart';

ApiException _tooMany(int? seconds) => ApiException(
  code: ApiErrorCode.tooManyRequests,
  statusCode: 429,
  details: seconds == null ? null : {'retryAfterSeconds': seconds},
);

const _registerRequest = RegisterRequest.join(
  name: 'Neha',
  email: 'neha@example.com',
  password: 'secret123',
  locale: 'hi',
  consentAccepted: true,
  inviteCode: 'DEMO2345',
);

void main() {
  group('AuthCooldown', () {
    test('counts down with the clock and clears itself', () async {
      final clock = TestClock();
      final c = await createAuthContainer(clock: clock);
      final key = AuthCooldownKeys.verifyEmail('u1');
      final cooldown = c.read(authCooldownProvider(key).notifier);

      expect(cooldown.isActive, isFalse);
      cooldown.start(60);
      expect(
        c.read(authCooldownProvider(key)),
        clock.now.add(const Duration(seconds: 60)),
      );
      expect(cooldown.secondsLeft, 60);

      clock.advance(const Duration(seconds: 59, milliseconds: 500));
      expect(cooldown.secondsLeft, 1);
      clock.advance(const Duration(milliseconds: 500));
      expect(cooldown.isActive, isFalse);

      cooldown.start(10);
      cooldown.start(0); // non-positive → cleared
      expect(c.read(authCooldownProvider(key)), isNull);
    });

    test(
      'a running cooldown stays alive unwatched; idle keys are released',
      () async {
        final clock = TestClock();
        final c = await createAuthContainer(clock: clock);
        final running = AuthCooldownKeys.login('a@x.co');
        final idle = AuthCooldownKeys.login('b@x.co');

        c.read(authCooldownProvider(running).notifier).start(30);
        c.read(authCooldownProvider(idle));
        await pumpEventQueue();

        expect(c.exists(authCooldownProvider(running)), isTrue);
        expect(c.read(authCooldownProvider(running)), isNotNull);
        expect(c.exists(authCooldownProvider(idle)), isFalse);

        // Seen expired → it lets go.
        clock.advance(const Duration(seconds: 31));
        expect(c.read(authCooldownProvider(running).notifier).secondsLeft, 0);
        await pumpEventQueue();
        expect(c.exists(authCooldownProvider(running)), isFalse);
      },
    );

    test('extendUntil only ever lengthens the wait', () async {
      final clock = TestClock();
      final c = await createAuthContainer(clock: clock);
      final key = AuthCooldownKeys.passwordReset('amit@example.com');
      final cooldown = c.read(authCooldownProvider(key).notifier)..start(60);

      cooldown.extendUntil(clock.now.add(const Duration(seconds: 30)));
      expect(cooldown.secondsLeft, 60);
      cooldown.extendUntil(clock.now.add(const Duration(minutes: 3)));
      expect(cooldown.secondsLeft, 180);
      cooldown.extendUntil(clock.now.subtract(const Duration(seconds: 1)));
      expect(cooldown.secondsLeft, 180);
      // Kept alive while it runs, although nobody watches it.
      await pumpEventQueue();
      expect(c.read(authCooldownProvider(key).notifier).secondsLeft, 180);
    });

    test('keys are independent per purpose and subject', () async {
      final c = await createAuthContainer(clock: TestClock());
      c
          .read(authCooldownProvider(AuthCooldownKeys.login('a@x.co')).notifier)
          .start(30);
      expect(
        c.read(authCooldownProvider(AuthCooldownKeys.login('b@x.co'))),
        isNull,
      );
      expect(
        c.read(authCooldownProvider(AuthCooldownKeys.passwordReset('a@x.co'))),
        isNull,
      );
      expect(
        c.read(authCooldownProvider(AuthCooldownKeys.login(' A@X.co '))),
        isNotNull,
      );
    });
  });

  group('AuthActions', () {
    test('login signs in and clears an old lockout', () async {
      final auth = FakeAuthRepository();
      final clock = TestClock();
      final c = await createAuthContainer(auth: auth, clock: clock);
      await c.read(sessionControllerProvider.future);
      final actions = c.read(authActionsProvider);
      c
          .read(
            authCooldownProvider(
              AuthCooldownKeys.login('amit@example.com'),
            ).notifier,
          )
          .start(5);

      await actions.login(email: 'amit@example.com', password: 'secret123');

      expect(c.read(sessionUserIdProvider), 'u1');
      expect(c.read(sessionControllerProvider).value?.isComplete, isTrue);
      expect(actions.loginLockSeconds('amit@example.com'), 0);
      // Login returns no member / family → the session loaded /auth/me.
      expect(auth.calls, ['login', 'me']);
    });

    test('429 starts the lockout for that email only (server wait)', () async {
      final auth = FakeAuthRepository()..failNext('login', _tooMany(900));
      final c = await createAuthContainer(auth: auth, clock: TestClock());
      await c.read(sessionControllerProvider.future);
      final actions = c.read(authActionsProvider);

      await expectLater(
        actions.login(email: 'Amit@Example.com', password: 'x'),
        throwsA(isA<ApiException>()),
      );

      expect(actions.loginLockSeconds('amit@example.com'), 900);
      expect(actions.loginLockSeconds('other@example.com'), 0);
      expect(c.read(sessionUserIdProvider), isNull);
    });

    test('429 without retryAfterSeconds uses the default wait', () async {
      final auth = FakeAuthRepository()..failNext('login', _tooMany(null));
      final c = await createAuthContainer(auth: auth, clock: TestClock());
      await c.read(sessionControllerProvider.future);
      final actions = c.read(authActionsProvider);
      await expectLater(
        actions.login(email: 'a@x.co', password: 'x'),
        throwsA(isA<ApiException>()),
      );
      expect(
        actions.loginLockSeconds('a@x.co'),
        AuthCooldownDefaults.tooManyRequestsSeconds,
      );
    });

    test('invalid credentials do not lock', () async {
      final auth = FakeAuthRepository()
        ..failNext(
          'login',
          const ApiException(
            code: ApiErrorCode.invalidCredentials,
            statusCode: 401,
          ),
        );
      final c = await createAuthContainer(auth: auth, clock: TestClock());
      await c.read(sessionControllerProvider.future);
      final actions = c.read(authActionsProvider);
      await expectLater(
        actions.login(email: 'a@x.co', password: 'x'),
        throwsA(isA<ApiException>()),
      );
      expect(actions.loginLockSeconds('a@x.co'), 0);
    });

    test('register signs in, starts the resend cooldown and marks data '
        'changed', () async {
      final auth = FakeAuthRepository(
        account: completeSession(verified: false),
      );
      final c = await createAuthContainer(auth: auth, clock: TestClock());
      await c.read(sessionControllerProvider.future);
      final before = c.read(dataRefreshProvider);

      await c.read(authActionsProvider).register(_registerRequest);

      expect(auth.lastRegister, _registerRequest);
      expect(
        c.read(sessionControllerProvider).value?.needsEmailVerification,
        isTrue,
      );
      expect(
        c.read(authActionsProvider).verificationCooldownSeconds(),
        AuthCooldownDefaults.resendSeconds,
      );
      final after = c.read(dataRefreshProvider);
      expect(after[DataScope.family], before[DataScope.family]! + 1);
      expect(after[DataScope.members], before[DataScope.members]! + 1);
    });

    test('resendVerification uses the server wait, also on 429', () async {
      final auth = FakeAuthRepository(account: completeSession(verified: false))
        ..resendSeconds = 45;
      final c = await createAuthContainer(auth: auth, clock: TestClock());
      await signIn(c, auth);
      final actions = c.read(authActionsProvider);

      await actions.resendVerification();
      expect(actions.verificationCooldownSeconds(), 45);

      auth.failNext('resendVerification', _tooMany(12));
      await expectLater(
        actions.resendVerification(),
        throwsA(isA<ApiException>()),
      );
      expect(actions.verificationCooldownSeconds(), 12);
    });

    test('resendVerification when already verified: no code, the session '
        'is reloaded', () async {
      final auth = FakeAuthRepository(account: completeSession(verified: false))
        ..resendSeconds = 0; // `{ sent: false, retryAfterSeconds: 0 }`
      final c = await createAuthContainer(auth: auth, clock: TestClock());
      await signIn(c, auth);
      // Meanwhile the code was typed on another device.
      auth.account = completeSession();
      final actions = c.read(authActionsProvider);

      expect(await actions.resendVerification(), isFalse);
      expect(actions.verificationCooldownSeconds(), 0);
      expect(c.read(sessionControllerProvider).value?.isComplete, isTrue);
    });

    test('refreshSession reloads the session and never throws', () async {
      final auth = FakeAuthRepository(
        account: completeSession(verified: false),
      );
      final c = await createAuthContainer(auth: auth);
      await signIn(c, auth);
      final actions = c.read(authActionsProvider);

      auth.failNext('me', const ApiException.network());
      await actions.refreshSession(); // offline: keeps the session
      expect(c.read(sessionUserIdProvider), 'u1');

      auth.account = completeSession();
      await actions.refreshSession();
      expect(c.read(sessionControllerProvider).value?.isComplete, isTrue);
    });

    test('verifyEmail updates the session', () async {
      final auth = FakeAuthRepository(
        account: completeSession(verified: false),
      );
      final c = await createAuthContainer(auth: auth);
      await signIn(c, auth);
      await c.read(authActionsProvider).verifyEmail('123456');
      expect(auth.lastOtp, '123456');
      expect(c.read(sessionControllerProvider).value?.isComplete, isTrue);
    });

    test(
      'createFamily / joinFamily go through the family repository',
      () async {
        final noFamily = SessionState(user: testUser(withFamily: false));
        final auth = FakeAuthRepository(account: noFamily);
        final family = FakeFamilyRepository(completeSession());
        final c = await createAuthContainer(auth: auth, family: family);
        await signIn(c, auth);
        expect(c.read(sessionControllerProvider).value?.needsFamily, isTrue);

        const request = CreateFamilyRequest(
          name: 'Sharma Family',
          country: 'IN',
          currency: 'INR',
          timezone: 'Asia/Kolkata',
        );
        await c.read(authActionsProvider).createFamily(request);
        expect(family.lastCreate, request);
        expect(c.read(sessionControllerProvider).value?.isComplete, isTrue);
      },
    );

    test('ALREADY_IN_FAMILY reloads the session and rethrows', () async {
      final noFamily = SessionState(user: testUser(withFamily: false));
      final auth = FakeAuthRepository(account: noFamily);
      final family = FakeFamilyRepository(completeSession())
        ..failNext(
          'joinFamily',
          const ApiException(
            code: ApiErrorCode.alreadyInFamily,
            statusCode: 409,
          ),
        );
      final c = await createAuthContainer(auth: auth, family: family);
      await signIn(c, auth);
      // Meanwhile the account joined a family on another phone.
      auth.account = completeSession();

      await expectLater(
        c.read(authActionsProvider).joinFamily('K7Q2M9XD'),
        throwsA(isA<ApiException>()),
      );
      await pumpEventQueue();
      expect(auth.count('me'), greaterThanOrEqualTo(1));
      expect(c.read(sessionControllerProvider).value?.isComplete, isTrue);
    });
  });

  group('ForgotPasswordController', () {
    Future<({FakeAuthRepository auth, TestClock clock, ProviderContainer c})>
    setup() async {
      final auth = FakeAuthRepository();
      final clock = TestClock();
      final c = await createAuthContainer(auth: auth, clock: clock);
      // Keep the auto-dispose controller alive.
      c.listen(forgotPasswordControllerProvider, (_, _) {});
      return (auth: auth, clock: clock, c: c);
    }

    test(
      'requestCode moves to the reset step with the normalised email',
      () async {
        final s = await setup();
        final controller = s.c.read(forgotPasswordControllerProvider.notifier);

        await controller.requestCode('  Amit@Example.com ');

        final ForgotPasswordState state = s.c.read(
          forgotPasswordControllerProvider,
        );
        expect(state.step, ForgotPasswordStep.reset);
        expect(state.email, 'amit@example.com');
        expect(state.isBusy, isFalse);
        expect(s.auth.lastForgotEmail, 'amit@example.com');
        expect(
          controller.resendSecondsLeft,
          AuthCooldownDefaults.resendSeconds,
        );
      },
    );

    test('no second request during the cooldown; resend after it', () async {
      final s = await setup();
      final controller = s.c.read(forgotPasswordControllerProvider.notifier);
      await controller.requestCode('amit@example.com');
      controller.changeEmail();
      await controller.requestCode('amit@example.com'); // same email, cooling
      await controller.resendCode();
      expect(s.auth.count('forgotPassword'), 1);
      expect(
        s.c.read(forgotPasswordControllerProvider).step,
        ForgotPasswordStep.reset,
      );

      s.clock.advance(const Duration(seconds: 61));
      await controller.resendCode();
      expect(s.auth.count('forgotPassword'), 2);
    });

    test('double submit sends one request', () async {
      final s = await setup();
      final controller = s.c.read(forgotPasswordControllerProvider.notifier);
      final gate = Completer<void>();
      s.auth.gates['forgotPassword'] = gate;
      final first = controller.requestCode('amit@example.com');
      final second = controller.requestCode('amit@example.com');
      await pumpEventQueue();
      expect(s.c.read(forgotPasswordControllerProvider).isSending, isTrue);
      gate.complete();
      await Future.wait([first, second]);
      expect(s.auth.count('forgotPassword'), 1);
    });

    test('resetPassword sends email, code and password', () async {
      final s = await setup();
      final controller = s.c.read(forgotPasswordControllerProvider.notifier);
      await controller.requestCode('amit@example.com');
      await controller.resetPassword(otp: '123456', newPassword: 'brandnew1');
      expect(s.auth.lastReset, {
        'email': 'amit@example.com',
        'otp': '123456',
        'newPassword': 'brandnew1',
      });
      expect(controller.resendSecondsLeft, 0);
    });

    test('errors are rethrown and the busy flag is released', () async {
      final s = await setup();
      final controller = s.c.read(forgotPasswordControllerProvider.notifier);
      await controller.requestCode('amit@example.com');
      s.auth.failNext(
        'resetPassword',
        const ApiException(code: ApiErrorCode.invalidOtp, statusCode: 400),
      );
      await expectLater(
        controller.resetPassword(otp: '000000', newPassword: 'brandnew1'),
        throwsA(isA<ApiException>()),
      );
      final ForgotPasswordState state = s.c.read(
        forgotPasswordControllerProvider,
      );
      expect(state.isResetting, isFalse);
      expect(state.step, ForgotPasswordStep.reset);
    });

    test('429 on step 1 keeps step 1 and does not pretend a code was '
        'sent', () async {
      final s = await setup();
      final controller = s.c.read(forgotPasswordControllerProvider.notifier);
      s.auth.failNext('forgotPassword', _tooMany(30));
      await expectLater(
        controller.requestCode('amit@example.com'),
        throwsA(isA<ApiException>()),
      );
      final ForgotPasswordState state = s.c.read(
        forgotPasswordControllerProvider,
      );
      expect(state.step, ForgotPasswordStep.email);
      expect(state.isSending, isFalse);
      expect(
        s.c
            .read(
              authCooldownProvider(
                AuthCooldownKeys.passwordReset('amit@example.com'),
              ).notifier,
            )
            .secondsLeft,
        0,
      );

      // Trying again really asks the server (no silent skip to step 2).
      await controller.requestCode('amit@example.com');
      expect(s.auth.count('forgotPassword'), 2);
      expect(
        s.c.read(forgotPasswordControllerProvider).step,
        ForgotPasswordStep.reset,
      );
    });

    test('429 on "Resend code" waits for the server', () async {
      final s = await setup();
      final controller = s.c.read(forgotPasswordControllerProvider.notifier);
      await controller.requestCode('amit@example.com');
      s.clock.advance(const Duration(seconds: 61));
      s.auth.failNext('forgotPassword', _tooMany(90));
      await expectLater(controller.resendCode(), throwsA(isA<ApiException>()));
      expect(controller.resendSecondsLeft, 90);
    });

    test('wrong codes extend the resend wait like the server '
        '(max(60 s, wrong × 3 min) from the send)', () async {
      final s = await setup();
      final controller = s.c.read(forgotPasswordControllerProvider.notifier);
      await controller.requestCode('amit@example.com');
      s.clock.advance(const Duration(seconds: 30));

      Future<void> wrong(String code) async {
        s.auth.failNext(
          'resetPassword',
          ApiException(code: code, statusCode: 400),
        );
        await expectLater(
          controller.resetPassword(otp: '000000', newPassword: 'brandnew1'),
          throwsA(isA<ApiException>()),
        );
      }

      await wrong(ApiErrorCode.invalidOtp);
      expect(controller.resendSecondsLeft, 3 * 60 - 30);
      await wrong(ApiErrorCode.invalidOtp);
      expect(controller.resendSecondsLeft, 6 * 60 - 30);
      // OTP_EXPIRED is not counted by the server either.
      await wrong(ApiErrorCode.otpExpired);
      expect(controller.resendSecondsLeft, 6 * 60 - 30);

      // "Resend code" stays a no-op until then.
      await controller.resendCode();
      expect(s.auth.count('forgotPassword'), 1);
      s.clock.advance(const Duration(minutes: 6));
      await controller.resendCode();
      expect(s.auth.count('forgotPassword'), 2);
      // A new code starts over with the plain 60 s.
      expect(controller.resendSecondsLeft, 60);
    });
  });

  group('SessionExpiredNotice', () {
    test(
      'turns on with AuthEvents.sessionExpired, off after sign-in',
      () async {
        final events = AuthEvents();
        final auth = FakeAuthRepository();
        final c = await createAuthContainer(auth: auth, events: events);
        await c.read(sessionControllerProvider.future);
        expect(c.read(sessionExpiredNoticeProvider), isFalse);

        events.emitSessionExpired();
        await pumpEventQueue();
        expect(c.read(sessionExpiredNoticeProvider), isTrue);

        await c
            .read(authActionsProvider)
            .login(email: 'amit@example.com', password: 'secret123');
        expect(c.read(sessionExpiredNoticeProvider), isFalse);
      },
    );
  });
}
