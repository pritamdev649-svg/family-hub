import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/features/sos/application/sos_controller.dart';
import 'package:family_hub/features/sos/application/sos_providers.dart';
import 'package:family_hub/features/sos/application/sos_runtime.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/models/session_state.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

import 'sos_test_utils.dart';

const _second = Duration(seconds: 1);

/// Reads the controller state.
SosState _state(ProviderContainer c) => c.read(sosControllerProvider);

/// Disposes the container and lets the last zero-delay futures run, so no
/// timer outlives the test.
Future<void> finish(WidgetTester tester, ProviderContainer c) async {
  c.dispose();
  await settle(tester);
}

int _sosChanges(ProviderContainer c) =>
    c.read(dataRefreshProvider)[DataScope.sos] ?? 0;

Future<SosLocationChoice?> _notAsked() async {
  fail('the location question must not be asked');
}

/// Starts the flow and runs the countdown to the end.
Future<Future<SosSendOutcome>> _startAndCount(
  WidgetTester tester,
  SosHarness h,
  ProviderContainer c, {
  SosLocationChoiceAsker ask = _notAsked,
}) async {
  final outcome = c
      .read(sosControllerProvider.notifier)
      .start(askLocationChoice: ask);
  for (var i = 0; i < 3; i++) {
    await advance(tester, h.clock, _second);
  }
  await settle(tester, 10);
  return outcome;
}

void main() {
  group('outgoing SOS', () {
    testWidgets('counts down 3..1, sends with location and tracks', (
      tester,
    ) async {
      final h = SosHarness(fix: fixAt(testNow));
      final c = await h.container();
      c.listen(sosControllerProvider, (_, _) {});
      final before = _sosChanges(c);

      final flow = c
          .read(sosControllerProvider.notifier)
          .start(askLocationChoice: _notAsked);
      expect(_state(c).phase, SosPhase.countdown);
      expect(_state(c).secondsLeft, 3);
      await advance(tester, h.clock, _second);
      expect(_state(c).secondsLeft, 2);
      await advance(tester, h.clock, _second);
      expect(_state(c).secondsLeft, 1);
      expect(h.repository.createCalls, isEmpty, reason: 'still cancellable');
      await advance(tester, h.clock, _second);
      await settle(tester, 10);

      final outcome = await flow;
      expect(outcome.result, SosSendResult.sent);
      expect(outcome.note, SosLocationNote.none);
      expect(h.repository.createCalls.single?.lat, 28.61);
      expect(h.location.prompts, 1, reason: 'permission asked when sending');

      final state = _state(c);
      expect(state.phase, SosPhase.active);
      expect(state.alert?.id, outcome.alert?.id);
      expect(state.sharing, SosSharing.live);
      expect(state.lastSentAt, h.clock.now, reason: 'sent with POST /sos');
      expect(h.location.tracks, 1);
      expect(h.location.isTracking, isTrue);
      expect(_sosChanges(c), greaterThan(before));

      // Live fixes go out at most every 5 s.
      h.location.emit(fixAt(h.clock.now, lat: 28.62));
      await settle(tester);
      expect(h.repository.locationCalls, isEmpty);
      await advance(tester, h.clock, const Duration(seconds: 5));
      await settle(tester);
      expect(h.repository.locationCalls.single.$2.lat, 28.62);
      expect(_state(c).lastSentAt, h.clock.now);

      await finish(tester, c);
    });

    testWidgets('cancel during the countdown sends nothing', (tester) async {
      final h = SosHarness();
      final c = await h.container();
      final flow = c
          .read(sosControllerProvider.notifier)
          .start(askLocationChoice: _notAsked);
      await advance(tester, h.clock, _second);
      c.read(sosControllerProvider.notifier).cancelCountdown();
      await settle(tester);
      expect((await flow).result, SosSendResult.cancelled);
      expect(_state(c).phase, SosPhase.idle);
      await advance(tester, h.clock, const Duration(seconds: 5));
      expect(h.repository.createCalls, isEmpty);
      expect(h.location.prompts, 0);
      await finish(tester, c);
    });

    testWidgets('a second start while running is ignored', (tester) async {
      final h = SosHarness();
      final c = await h.container();
      final notifier = c.read(sosControllerProvider.notifier);
      final first = notifier.start(askLocationChoice: _notAsked);
      final second = await notifier.start(askLocationChoice: _notAsked);
      expect(second.result, SosSendResult.ignored);
      notifier.cancelCountdown();
      await settle(tester);
      expect((await first).result, SosSendResult.cancelled);
      await finish(tester, c);
    });

    testWidgets('sharing "never" + "send without location"', (tester) async {
      final h = SosHarness(
        member: amit.copyWith(locationSharing: LocationSharingMode.never),
        fix: fixAt(testNow),
      );
      final c = await h.container();
      var asked = 0;
      final flow = await _startAndCount(
        tester,
        h,
        c,
        ask: () async {
          asked++;
          return SosLocationChoice.sendWithout;
        },
      );
      final outcome = await flow;
      expect(asked, 1);
      expect(outcome.result, SosSendResult.sent);
      expect(outcome.note, SosLocationNote.sharingOff);
      expect(h.repository.createCalls.single, isNull);
      expect(h.location.prompts, 0, reason: 'no permission prompt');
      expect(h.me.calls, isEmpty);
      expect(_state(c).sharing, SosSharing.off);
      expect(h.location.tracks, 0);
      await finish(tester, c);
    });

    testWidgets('sharing "never" + "share for SOS only" switches the mode', (
      tester,
    ) async {
      final never = amit.copyWith(locationSharing: LocationSharingMode.never);
      final h = SosHarness(member: never, fix: fixAt(testNow));
      final c = await h.container();
      final flow = await _startAndCount(
        tester,
        h,
        c,
        ask: () async {
          // The server sees the new mode once PATCH /me went through.
          h.repository.me = amit;
          return SosLocationChoice.shareDuringSos;
        },
      );
      final outcome = await flow;
      expect(h.me.calls.single.fields, {'locationSharing': 'sos_only'});
      expect(h.session.applyMeCalls, 1);
      expect(
        c.read(currentMemberProvider)?.locationSharing,
        LocationSharingMode.sosOnly,
      );
      expect(outcome.note, SosLocationNote.none);
      expect(h.repository.createCalls.single, isNotNull);
      expect(_state(c).sharing, SosSharing.live);
      await finish(tester, c);
    });

    testWidgets('a failed mode switch still sends, without location', (
      tester,
    ) async {
      final never = amit.copyWith(locationSharing: LocationSharingMode.never);
      final h = SosHarness(member: never);
      h.me.error = networkError;
      final c = await h.container();
      final flow = await _startAndCount(
        tester,
        h,
        c,
        ask: () async => SosLocationChoice.shareDuringSos,
      );
      final outcome = await flow;
      expect(outcome.result, SosSendResult.sent);
      expect(outcome.note, SosLocationNote.sharingUpdateFailed);
      expect(h.repository.createCalls.single, isNull);
      await finish(tester, c);
    });

    testWidgets('permission denied: sent without location, user is told', (
      tester,
    ) async {
      final h = SosHarness(permission: LocationPermissionState.deniedForever);
      final c = await h.container();
      final outcome = await (await _startAndCount(tester, h, c));
      expect(outcome.result, SosSendResult.sent);
      expect(outcome.note, SosLocationNote.permissionMissing);
      expect(outcome.permission, LocationPermissionState.deniedForever);
      expect(h.repository.createCalls.single, isNull);
      expect(h.location.fixes, 0);
      expect(_state(c).sharing, SosSharing.unavailable);
      expect(_state(c).permission, LocationPermissionState.deniedForever);
      expect(h.location.tracks, 0);

      // Granted later ("Allow location"): tracking starts.
      h.location.afterPrompt = LocationPermissionState.granted;
      final result = c.read(sosControllerProvider.notifier).retryLocation();
      await settle(tester);
      expect(await result, LocationPermissionState.granted);
      expect(_state(c).sharing, SosSharing.live);
      expect(h.location.tracks, 1);
      await finish(tester, c);
    });

    testWidgets('transient failures are retried, then reported', (
      tester,
    ) async {
      final h = SosHarness();
      h.repository.createErrors.addAll([
        networkError,
        networkError,
        networkError,
      ]);
      final c = await h.container();
      final flow = c
          .read(sosControllerProvider.notifier)
          .start(askLocationChoice: _notAsked, skipCountdown: true);
      await settle(tester);
      expect(h.repository.createCalls, hasLength(1));
      await advance(tester, h.clock, _second);
      await settle(tester);
      expect(h.repository.createCalls, hasLength(2));
      await advance(tester, h.clock, const Duration(seconds: 2));
      await settle(tester);
      expect(h.repository.createCalls, hasLength(3));

      final outcome = await flow;
      expect(outcome.result, SosSendResult.failed);
      expect(outcome.error, networkError);
      expect(_state(c).phase, SosPhase.idle);
      expect(_state(c).sendError, networkError);
      c.read(sosControllerProvider.notifier).clearSendError();
      expect(_state(c).sendError, isNull);
      await finish(tester, c);
    });

    testWidgets('a retry that succeeds sends the alert once', (tester) async {
      final h = SosHarness();
      h.repository.createErrors.add(networkError);
      final c = await h.container();
      final flow = c
          .read(sosControllerProvider.notifier)
          .start(askLocationChoice: _notAsked, skipCountdown: true);
      await settle(tester);
      await advance(tester, h.clock, _second);
      await settle(tester, 10);
      expect((await flow).result, SosSendResult.sent);
      expect(h.repository.alerts, hasLength(1));
      await finish(tester, c);
    });
  });

  group('active alert', () {
    /// Sends an SOS without countdown and returns the container.
    Future<ProviderContainer> sent(WidgetTester tester, SosHarness h) async {
      final c = await h.container();
      final flow = c
          .read(sosControllerProvider.notifier)
          .start(askLocationChoice: _notAsked, skipCountdown: true);
      await settle(tester, 10);
      expect((await flow).result, SosSendResult.sent);
      return c;
    }

    testWidgets('"I am okay" resolves, stops tracking, announces', (
      tester,
    ) async {
      final h = SosHarness(fix: fixAt(testNow));
      final c = await sent(tester, h);
      final id = _state(c).alert!.id;
      final before = _sosChanges(c);

      final resolving = c
          .read(sosControllerProvider.notifier)
          .resolve(SosResolution.safe);
      expect(_state(c).resolving, SosResolution.safe);
      expect(
        await c
            .read(sosControllerProvider.notifier)
            .resolve(SosResolution.falseAlarm),
        isNull,
        reason: 'double submit ignored',
      );
      await settle(tester);
      final resolved = await resolving;
      expect(resolved?.resolution, SosResolution.safe);
      expect(h.repository.resolveCalls, [(id, SosResolution.safe)]);
      expect(_state(c).phase, SosPhase.idle);
      expect(h.location.isTracking, isFalse);
      expect(_sosChanges(c), greaterThan(before));
      await finish(tester, c);
    });

    testWidgets('a failed resolve keeps the alert active', (tester) async {
      final h = SosHarness(fix: fixAt(testNow));
      final c = await sent(tester, h);
      h.repository.resolveError = networkError;
      final resolving = expectLater(
        c
            .read(sosControllerProvider.notifier)
            .resolve(SosResolution.falseAlarm),
        throwsA(networkError),
      );
      await settle(tester);
      await resolving;
      expect(_state(c).phase, SosPhase.active);
      expect(_state(c).resolving, isNull);
      expect(h.location.isTracking, isTrue);
      await finish(tester, c);
    });

    testWidgets('409 SOS_NOT_ACTIVE on a location update ends tracking', (
      tester,
    ) async {
      final h = SosHarness(fix: fixAt(testNow));
      final c = await sent(tester, h);
      // The server ended it (e.g. expired early by its clock).
      final id = _state(c).alert!.id;
      h.repository.alerts[id] = h.repository.alerts[id]!.copyWith(
        status: SosStatus.expired,
      );
      await advance(tester, h.clock, const Duration(seconds: 5));
      h.location.emit(fixAt(h.clock.now));
      await settle(tester);
      expect(h.repository.locationCalls, hasLength(1));
      expect(_state(c).phase, SosPhase.idle);
      expect(h.location.isTracking, isFalse);
      await finish(tester, c);
    });

    testWidgets('stops at expiresAt', (tester) async {
      final h = SosHarness(fix: fixAt(testNow));
      final c = await sent(tester, h);
      await advance(tester, h.clock, const Duration(minutes: 14, seconds: 59));
      await settle(tester);
      expect(_state(c).phase, SosPhase.active);
      await advance(tester, h.clock, _second);
      await settle(tester);
      expect(_state(c).phase, SosPhase.idle);
      expect(h.location.isTracking, isFalse);
      await finish(tester, c);
    });

    testWidgets('an alert resolved elsewhere is noticed via the active list', (
      tester,
    ) async {
      final h = SosHarness(fix: fixAt(testNow));
      final c = await sent(tester, h);
      final id = _state(c).alert!.id;
      // An admin resolved it on another phone.
      h.repository.alerts[id] = h.repository.alerts[id]!.copyWith(
        status: SosStatus.resolved,
        resolution: () => SosResolution.helped,
      );
      final polls = h.repository.activeCalls;
      await advance(tester, h.clock, const Duration(seconds: 15));
      await settle(tester, 10);
      expect(h.repository.activeCalls, greaterThan(polls));
      expect(h.repository.getCalls, contains(id), reason: 'verified first');
      expect(_state(c).phase, SosPhase.idle);
      expect(h.location.isTracking, isFalse);
      await finish(tester, c);
    });

    testWidgets('switching to "never" stops tracking, keeps the alert', (
      tester,
    ) async {
      final h = SosHarness(fix: fixAt(testNow));
      final c = await sent(tester, h);
      h.session.setMember(
        amit.copyWith(locationSharing: LocationSharingMode.never),
      );
      await settle(tester);
      expect(_state(c).phase, SosPhase.active);
      expect(_state(c).sharing, SosSharing.off);
      expect(h.location.isTracking, isFalse);
      await finish(tester, c);
    });

    testWidgets('logout resets the controller and stops tracking', (
      tester,
    ) async {
      final h = SosHarness(fix: fixAt(testNow));
      final c = await sent(tester, h);
      expect(h.location.isTracking, isTrue);
      h.session.state = const AsyncData(SessionState.signedOut);
      await settle(tester);
      expect(_state(c).phase, SosPhase.idle);
      expect(h.location.isTracking, isFalse);
      await finish(tester, c);
    });
  });

  group('resume', () {
    testWidgets('an active alert of mine is adopted without prompting', (
      tester,
    ) async {
      final h = SosHarness();
      final mine = alertFor(amit, id: 'mine');
      h.repository.alerts['mine'] = mine;
      h.repository.alerts['other'] = alertFor(priya, id: 'other');
      final c = await h.container();
      c.listen(sosControllerProvider, (_, _) {});
      await settle(tester, 10);

      expect(_state(c).phase, SosPhase.active);
      expect(_state(c).alert?.id, 'mine');
      expect(_state(c).sharing, SosSharing.live);
      expect(h.location.prompts, 0);
      expect(h.location.checks, greaterThan(0));
      expect(h.location.tracks, 1);
      expect(c.read(myActiveSosAlertProvider)?.id, 'mine');
      expect(c.read(otherActiveSosAlertsProvider).value?.map((a) => a.id), [
        'other',
      ]);
      await finish(tester, c);
    });

    testWidgets('an expired alert of mine is not adopted', (tester) async {
      final h = SosHarness();
      h.repository.alerts['old'] = alertFor(
        amit,
        id: 'old',
        startedAt: testNow.subtract(const Duration(minutes: 16)),
      );
      final c = await h.container();
      c.listen(sosControllerProvider, (_, _) {});
      await settle(tester, 10);
      expect(_state(c).phase, SosPhase.idle);
      expect(h.location.tracks, 0);
      await finish(tester, c);
    });

    testWidgets('the active list polls every 15 s only in the foreground', (
      tester,
    ) async {
      final h = SosHarness();
      final c = await h.container();
      c.listen(activeSosAlertsProvider, (_, _) {});
      await settle(tester);
      expect(h.repository.activeCalls, 1);
      await advance(tester, h.clock, const Duration(seconds: 15));
      await settle(tester);
      expect(h.repository.activeCalls, 2);

      final foreground =
          c.read(sosAppForegroundProvider.notifier) as FakeForeground;
      foreground.set(false);
      await advance(tester, h.clock, const Duration(seconds: 45));
      await settle(tester);
      expect(h.repository.activeCalls, 2, reason: 'paused in background');

      foreground.set(true);
      await settle(tester);
      expect(h.repository.activeCalls, 3, reason: 'catch-up on resume');
      await finish(tester, c);
    });
  });
}
