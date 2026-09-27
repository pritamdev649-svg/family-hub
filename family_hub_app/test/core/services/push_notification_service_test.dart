import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/services/push_notification_service.dart';
import 'package:family_hub/core/services/push_platform.dart';
import 'package:family_hub/shared/data/me_repository.dart' show DevicePlatform;
import 'package:family_hub/shared/providers/data_refresh.dart';

class _FakeMessaging implements PushMessaging {
  bool available = true;
  String? token = 'token-1';
  bool? autoInit;
  int permissionRequests = 0;
  int deleteCount = 0;
  BackgroundMessageHandler? backgroundHandler;
  bool foregroundPresentation = false;
  RemoteMessage? initialMessage;

  final onMessageController = StreamController<RemoteMessage>.broadcast();
  final openedController = StreamController<RemoteMessage>.broadcast();
  final tokenRefreshController = StreamController<String>.broadcast();

  @override
  bool get isAvailable => available;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> setAutoInitEnabled(bool enabled) async => autoInit = enabled;

  @override
  Future<String?> getToken() async => token;

  @override
  Future<void> deleteToken() async {
    deleteCount++;
    token = null;
  }

  @override
  Stream<String> get onTokenRefresh => tokenRefreshController.stream;

  @override
  Stream<RemoteMessage> get onMessage => onMessageController.stream;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => openedController.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async => initialMessage;

  @override
  Future<void> enableForegroundPresentation() async =>
      foregroundPresentation = true;

  @override
  void setBackgroundHandler(BackgroundMessageHandler handler) =>
      backgroundHandler = handler;
}

class _Shown {
  _Shown(this.id, this.channelId, this.title, this.body, this.payload);
  final int id;
  final String channelId;
  final String? title;
  final String? body;
  final String? payload;
}

class _FakeNotifier implements LocalNotifier {
  void Function(String? payload)? onTap;
  String? launch;
  final channelLabels = <PushChannelLabels>[];
  final shown = <_Shown>[];

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async => this.onTap = onTap;

  @override
  Future<String?> launchPayload() async => launch;

  @override
  Future<void> createChannels(PushChannelLabels labels) async =>
      channelLabels.add(labels);

  @override
  Future<void> show({
    required int id,
    required String channelId,
    required PushChannelLabels labels,
    String? title,
    String? body,
    String? payload,
  }) async => shown.add(_Shown(id, channelId, title, body, payload));
}

class _Registration {
  _Registration(this.token, this.platform, this.locale);
  final String token;
  final DevicePlatform platform;
  final String? locale;
}

class _FakeDeviceApi implements PushDeviceApi {
  final registered = <_Registration>[];
  final unregistered = <String>[];
  Object? error;

  @override
  Future<void> register({
    required String token,
    required DevicePlatform platform,
    String? locale,
  }) async {
    if (error != null) throw error!;
    registered.add(_Registration(token, platform, locale));
  }

  @override
  Future<void> unregister(String token) async {
    if (error != null) throw error!;
    unregistered.add(token);
  }
}

RemoteMessage _message(
  Map<String, dynamic> data, {
  String? title = 'Title',
  String? body = 'Body',
  String? messageId = 'm1',
}) => RemoteMessage(
  messageId: messageId,
  data: data,
  notification: title == null && body == null
      ? null
      : RemoteNotification(title: title, body: body),
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _FakeMessaging messaging;
  late _FakeNotifier notifier;
  late _FakeDeviceApi deviceApi;
  late List<String> receivedTypes;
  late String? appLocale;
  late PushNotificationService service;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messaging = _FakeMessaging();
    notifier = _FakeNotifier();
    deviceApi = _FakeDeviceApi();
    receivedTypes = [];
    appLocale = 'hi';
    service = PushNotificationService(
      deviceApi: deviceApi,
      messaging: messaging,
      localNotifier: notifier,
      onMessageReceived: receivedTypes.add,
      localeResolver: () => appLocale,
      networkTimeout: const Duration(seconds: 1),
    );
  });

  tearDown(() async {
    await service.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  group('without Firebase', () {
    setUp(() => messaging.available = false);

    test('every method is a safe no-op', () async {
      await service.init();
      await service.registerDevice();
      await service.unregisterDevice();
      expect(await service.currentToken(), isNull);
      expect(service.isAvailable, isFalse);
      expect(notifier.onTap, isNull);
      expect(messaging.backgroundHandler, isNull);
      expect(messaging.permissionRequests, 0);
      expect(deviceApi.registered, isEmpty);
      expect(deviceApi.unregistered, isEmpty);
    });
  });

  group('init', () {
    test('Android: channels, background handler, idempotent', () async {
      await service.init();
      await service.init();
      expect(messaging.backgroundHandler, isNotNull);
      expect(notifier.onTap, isNotNull);
      expect(notifier.channelLabels, hasLength(1));
      // Labels come from the app language (resolver -> hi); only the
      // English template exists in tests, which is the fallback.
      expect(notifier.channelLabels.single.sosName, isNotEmpty);
      expect(messaging.foregroundPresentation, isFalse);
    });

    test(
      'iOS uses foreground presentation instead of local notifications',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        await service.init();
        expect(messaging.foregroundPresentation, isTrue);
        expect(notifier.onTap, isNull);
      },
    );
  });

  group('messages', () {
    test(
      'foreground SOS is shown on the sos_alerts channel with its route',
      () async {
        await service.init();
        messaging.onMessageController.add(
          _message({'type': 'sos', 'id': 'a1', 'route': '/sos/alert/a1'}),
        );
        await _settle();
        expect(notifier.shown, hasLength(1));
        final shown = notifier.shown.single;
        expect(shown.channelId, PushChannelIds.sos);
        expect(shown.payload, '/sos/alert/a1');
        expect(shown.title, 'Title');
        expect(receivedTypes, ['sos']);
      },
    );

    test('foreground task push uses the general channel', () async {
      await service.init();
      messaging.onMessageController.add(
        _message({'type': 'task_assigned', 'id': 't1'}),
      );
      await _settle();
      expect(notifier.shown.single.channelId, PushChannelIds.general);
      expect(notifier.shown.single.payload, '/tasks/t1');
    });

    test('foreground messages are not re-shown on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await service.init();
      messaging.onMessageController.add(_message({'type': 'notice'}));
      await _settle();
      expect(notifier.shown, isEmpty);
      expect(receivedTypes, ['notice']);
    });

    test('tapping a system notification emits its route', () async {
      await service.init();
      final routes = <String>[];
      final sub = service.routeTaps.listen(routes.add);
      messaging.openedController.add(
        _message({'type': 'notice', 'route': '/notices'}),
      );
      await _settle();
      expect(routes, ['/notices']);
      await sub.cancel();
    });

    test('tapping a local notification emits the sanitized payload', () async {
      await service.init();
      final routes = <String>[];
      final sub = service.routeTaps.listen(routes.add);
      notifier.onTap!('/tasks/t9');
      notifier.onTap!('https://evil.example/phish'); // rejected
      notifier.onTap!(null);
      await _settle();
      expect(routes, ['/tasks/t9']);
      await sub.cancel();
    });

    test('cold-start route is buffered until the first listener', () async {
      messaging.initialMessage = _message({
        'type': 'sos',
        'id': 'x',
        'route': '/sos/alert/x',
      });
      await service.init();
      final routes = <String>[];
      final sub = service.routeTaps.listen(routes.add);
      await _settle();
      expect(routes, ['/sos/alert/x']);
      await sub.cancel();
    });

    test('cold start from a local notification (Android)', () async {
      notifier.launch = '/money';
      final routes = <String>[];
      final sub = service.routeTaps.listen(routes.add);
      await service.init();
      await _settle();
      expect(routes, ['/money']);
      await sub.cancel();
    });
  });

  group('device registration', () {
    test('registers token, platform and app language', () async {
      await service.registerDevice();
      expect(messaging.permissionRequests, 1);
      expect(messaging.autoInit, isTrue);
      expect(deviceApi.registered, hasLength(1));
      final r = deviceApi.registered.single;
      expect(r.token, 'token-1');
      expect(r.platform, DevicePlatform.android);
      expect(r.locale, 'hi');
      expect(await service.currentToken(), 'token-1');
    });

    test('explicit locale wins; unsupported codes are ignored', () async {
      await service.registerDevice(locale: 'ta');
      expect(deviceApi.registered.last.locale, 'ta');
      await service.registerDevice(locale: 'xx');
      expect(deviceApi.registered.last.locale, 'ta');
    });

    test('unknown app language is omitted (backend falls back)', () async {
      appLocale = 'zz';
      await service.registerDevice();
      expect(deviceApi.registered.single.locale, isNull);
    });

    test('iOS reports platform ios', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await service.registerDevice();
      expect(deviceApi.registered.single.platform, DevicePlatform.ios);
    });

    test(
      'no token yet -> nothing sent, token refresh registers later',
      () async {
        messaging.token = null;
        await service.registerDevice();
        expect(deviceApi.registered, isEmpty);
        messaging.tokenRefreshController.add('token-2');
        await _settle();
        expect(deviceApi.registered.single.token, 'token-2');
      },
    );

    test('token refresh is ignored when signed out', () async {
      await service.init();
      messaging.tokenRefreshController.add('token-3');
      await _settle();
      expect(deviceApi.registered, isEmpty);
    });

    test('API failures never throw', () async {
      deviceApi.error = Exception('offline');
      await service.registerDevice();
      await service.unregisterDevice();
      expect(deviceApi.registered, isEmpty);
    });

    test('updateLocale re-registers only when the language changed', () async {
      await service.registerDevice();
      await service.updateLocale('hi');
      expect(deviceApi.registered, hasLength(1));
      await service.updateLocale('ar');
      expect(deviceApi.registered, hasLength(2));
      expect(deviceApi.registered.last.locale, 'ar');
    });

    test(
      'unregister deletes backend + local token and disables auto-init',
      () async {
        await service.registerDevice();
        await service.unregisterDevice();
        expect(deviceApi.unregistered, ['token-1']);
        expect(messaging.deleteCount, 1);
        expect(messaging.autoInit, isFalse);

        // A later rotation must not re-register the signed-out device.
        messaging.tokenRefreshController.add('token-4');
        await _settle();
        expect(deviceApi.registered, hasLength(1));
      },
    );
  });

  group('routeFromData', () {
    test('prefers a safe explicit route', () {
      expect(
        PushNotificationService.routeFromData({
          'type': 'sos',
          'id': 'a',
          'route': '/sos/alert/a',
        }),
        '/sos/alert/a',
      );
    });

    test('rejects unsafe routes and derives one from type + id', () {
      expect(
        PushNotificationService.routeFromData({
          'type': 'sos',
          'id': 'a',
          'route': 'https://evil.example',
        }),
        '/sos/alert/a',
      );
      expect(
        PushNotificationService.routeFromData({
          'type': 'task_completed',
          'id': 't',
          'route': '//evil',
        }),
        '/tasks/t',
      );
    });

    test('derives routes for every contract type', () {
      String? r(Map<String, dynamic> d) =>
          PushNotificationService.routeFromData(d);
      expect(r({'type': 'sos_resolved', 'id': 'a'}), '/sos/alert/a');
      expect(r({'type': 'sos'}), '/sos');
      expect(r({'type': 'task_assigned', 'id': 't'}), '/tasks/t');
      expect(r({'type': 'notice', 'id': 'n'}), '/notices');
      expect(r({'type': 'goal_achieved', 'id': 'g'}), '/money');
      expect(r({'type': 'member_joined', 'id': 'm'}), '/members/m');
      expect(r({'type': 'member_joined'}), '/members');
      expect(r({'type': 'something_new'}), isNull);
      expect(r(const {}), isNull);
    });
  });

  test('channelFor', () {
    expect(PushNotificationService.channelFor({'type': 'sos'}), 'sos_alerts');
    expect(
      PushNotificationService.channelFor({'type': 'sos_resolved'}),
      'general',
    );
    expect(PushNotificationService.channelFor(const {}), 'general');
  });

  test('notificationIdFor is stable per resource and non-negative', () {
    final a = PushNotificationService.notificationIdFor(
      _message({'type': 'sos', 'id': 'a1'}, messageId: 'x'),
    );
    final b = PushNotificationService.notificationIdFor(
      _message({'type': 'sos', 'id': 'a1'}, messageId: 'y'),
    );
    final c = PushNotificationService.notificationIdFor(
      _message({'type': 'sos', 'id': 'a2'}),
    );
    final resolved = PushNotificationService.notificationIdFor(
      _message({'type': 'sos_resolved', 'id': 'a1'}),
    );
    expect(a, b);
    expect(a, isNot(c));
    expect(resolved, a, reason: 'resolved replaces the SOS notification');
    expect(a, greaterThanOrEqualTo(0));
  });

  test('scopesForType', () {
    expect(PushNotificationService.scopesForType('sos'), {DataScope.sos});
    expect(PushNotificationService.scopesForType('goal_achieved'), {
      DataScope.goals,
      DataScope.ledger,
    });
    expect(PushNotificationService.scopesForType('member_joined'), {
      DataScope.members,
      DataScope.family,
    });
    expect(PushNotificationService.scopesForType('unknown'), isEmpty);
  });
}
