import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/features/sos/data/sos_repository.dart';
import 'package:family_hub/features/sos/domain/sos_alert.dart';

/// Records calls and answers with canned data.
class _RecordingApi extends ApiClient {
  _RecordingApi() : super(Dio());

  final List<(String, String, Object?)> calls = [];
  Object? response;
  Map<String, dynamic>? lastQuery;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    calls.add(('GET', path, null));
    lastQuery = query;
    return response;
  }

  @override
  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    calls.add(('POST', path, body));
    return response;
  }

  @override
  Future<Paged<T>> getPaged<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, dynamic>? query,
    int page = 1,
    int limit = 20,
  }) async {
    calls.add(('GET', path, {'page': page, 'limit': limit}));
    final items = [
      for (final e in response! as List) fromJson(e as Map<String, dynamic>),
    ];
    return Paged<T>(
      items: items,
      page: page,
      limit: limit,
      total: items.length,
      hasMore: false,
    );
  }
}

Map<String, dynamic> _alertJson([String id = 'a1']) => {
  'id': id,
  'memberId': 'm1',
  'status': 'active',
  'startedAt': '2026-09-27T10:00:00.000Z',
  'expiresAt': '2026-09-27T10:15:00.000Z',
  'trail': <Object?>[],
};

void main() {
  late _RecordingApi api;
  late SosRepository repo;

  setUp(() {
    api = _RecordingApi()..response = _alertJson();
    repo = SosRepository(api);
  });

  test('create sends the location and a trimmed message', () async {
    final alert = await repo.create(
      location: const GeoPoint(lat: 28.6, lng: 77.2, accuracy: 9),
      message: '  help  ',
    );
    expect(alert.id, 'a1');
    expect(api.calls.single.$1, 'POST');
    expect(api.calls.single.$2, '/sos');
    expect(api.calls.single.$3, {
      'location': {'lat': 28.6, 'lng': 77.2, 'accuracy': 9.0},
      'message': 'help',
    });
  });

  test('create without location / blank message sends an empty body', () async {
    await repo.create(message: '   ');
    expect(api.calls.single.$3, <String, dynamic>{});
  });

  test('negative accuracy is omitted', () async {
    await repo.create(location: const GeoPoint(lat: 1, lng: 2, accuracy: -1));
    expect(api.calls.single.$3, {
      'location': {'lat': 1.0, 'lng': 2.0},
    });
  });

  test('clampMessage keeps 140 code units without splitting emoji', () {
    final long = 'a' * 139 + '😀' * 3;
    final clamped = SosRepository.clampMessage(long);
    expect(clamped.length, 139, reason: 'the surrogate pair is not split');
    expect(SosRepository.clampMessage('ok'), 'ok');
    expect(SosRepository.clampMessage('b' * 200).length, 140);
  });

  test('active parses a list, skipping junk', () async {
    api.response = [_alertJson('a1'), 'junk', _alertJson('a2')];
    final list = await repo.active();
    expect(list.map((a) => a.id), ['a1', 'a2']);
    expect(api.calls.single.$2, '/sos/active');
  });

  test('active with a non-list answer is a malformed response', () async {
    api.response = {'oops': true};
    await expectLater(
      repo.active(),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', ApiErrorCode.unknown),
      ),
    );
  });

  test('history is paginated and capped at 100', () async {
    api.response = [_alertJson()];
    final page = await repo.history(page: 2, limit: 500);
    expect(page.items.single.id, 'a1');
    expect(api.calls.single.$2, '/sos/history');
    expect(api.calls.single.$3, {'page': 2, 'limit': 100});
  });

  test('get / location / resolve hit the id routes', () async {
    await repo.get('a1');
    await repo.sendLocation('a1', const GeoPoint(lat: 1, lng: 2));
    await repo.resolve('a1', SosResolution.falseAlarm);
    expect(api.calls.map((c) => '${c.$1} ${c.$2}'), [
      'GET /sos/a1',
      'POST /sos/a1/location',
      'POST /sos/a1/resolve',
    ]);
    expect(api.calls[1].$3, {'lat': 1.0, 'lng': 2.0});
    expect(api.calls[2].$3, {'resolution': 'false_alarm'});
  });

  test('a blank id fails fast with NOT_FOUND', () async {
    await expectLater(
      repo.get('  '),
      throwsA(
        isA<ApiException>().having((e) => e.isNotFound, 'notFound', true),
      ),
    );
    expect(api.calls, isEmpty);
  });

  test('an alert without id is a malformed response', () async {
    api.response = {'status': 'active'};
    await expectLater(repo.get('a1'), throwsA(isA<ApiException>()));
  });
}
