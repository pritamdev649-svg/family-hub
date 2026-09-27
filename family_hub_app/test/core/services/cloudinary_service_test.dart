import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/services/cloudinary_service.dart';

/// Answers every request with [status] / [body] and records the request.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.status = 200, this.body, this.error});

  final int status;
  final Object? body;
  final DioExceptionType? error;
  RequestOptions? lastRequest;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    lastRequest = options;
    // Drain the body so Dio reports upload progress.
    await requestStream?.drain<void>();
    if (error != null) {
      throw DioException(requestOptions: options, type: error!);
    }
    return ResponseBody.fromString(
      jsonEncode(body ?? const {}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, String> _fields(RequestOptions options) => {
  for (final e in (options.data as FormData).fields) e.key: e.value,
};

const _signature = {
  'cloudName': 'demo',
  'apiKey': '1234',
  'timestamp': 1790000000,
  'signature': 'abc123',
  'folder': 'familyhub/fam1/avatars',
};

const _secureUrl =
    'https://res.cloudinary.com/demo/image/upload/v1/familyhub/fam1/avatars/a.jpg';

void main() {
  late Directory tmp;
  late XFile image;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('cloudinary_test');
    final file = File('${tmp.path}/photo.jpg');
    await file.writeAsBytes(List<int>.filled(2048, 7));
    image = XFile(file.path);
  });

  tearDownAll(() async {
    await tmp.delete(recursive: true);
  });

  CloudinaryService build({
    required _FakeAdapter adapter,
    CloudinaryConfig config = const CloudinaryConfig(useMockApi: false),
    List<UploadFolder>? signatureCalls,
    Object? signature = _signature,
    int maxBytes = CloudinaryService.defaultMaxBytes,
  }) {
    final dio = Dio()..httpClientAdapter = adapter;
    return CloudinaryService(
      dio: dio,
      config: config,
      maxBytes: maxBytes,
      fetchSignature: (folder) async {
        signatureCalls?.add(folder);
        return signature;
      },
    );
  }

  test(
    'signed upload sends exactly the signed params and returns the URL',
    () async {
      final adapter = _FakeAdapter(body: {'secure_url': _secureUrl});
      final calls = <UploadFolder>[];
      final progress = <double>[];
      final service = build(adapter: adapter, signatureCalls: calls);

      final url = await service.uploadImage(
        image,
        folder: UploadFolder.avatars,
        onProgress: progress.add,
      );

      expect(url, _secureUrl);
      expect(calls, [UploadFolder.avatars]);
      final request = adapter.lastRequest!;
      expect(
        request.uri.toString(),
        'https://api.cloudinary.com/v1_1/demo/image/upload',
      );
      // Never leak the backend bearer token to a third party.
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(_fields(request), {
        'api_key': '1234',
        'timestamp': '1790000000',
        'signature': 'abc123',
        'folder': 'familyhub/fam1/avatars',
      });
      final files = (request.data as FormData).files;
      expect(files.single.key, 'file');
      expect(files.single.value.filename, 'photo.jpg');

      expect(progress.first, 0);
      expect(progress.last, 1);
      expect(progress.where((p) => p > 0 && p < 1), isNotEmpty);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
    },
  );

  test('unsigned upload uses the preset and skips the backend', () async {
    final adapter = _FakeAdapter(body: {'secure_url': _secureUrl});
    final calls = <UploadFolder>[];
    final service = build(
      adapter: adapter,
      signatureCalls: calls,
      config: const CloudinaryConfig(
        useMockApi: true,
        cloudName: 'mycloud',
        uploadPreset: 'unsigned_preset',
      ),
    );

    await service.uploadImage(image, folder: UploadFolder.notices);

    expect(calls, isEmpty);
    expect(adapter.lastRequest!.uri.path, '/v1_1/mycloud/image/upload');
    expect(_fields(adapter.lastRequest!), {
      'upload_preset': 'unsigned_preset',
      'folder': 'familyhub/notices',
    });
  });

  test('mock mode without Cloudinary config returns the local path', () async {
    final adapter = _FakeAdapter();
    final progress = <double>[];
    final service = build(
      adapter: adapter,
      config: const CloudinaryConfig(useMockApi: true),
    );

    final url = await service.uploadImage(
      image,
      folder: UploadFolder.avatars,
      onProgress: progress.add,
    );

    expect(url, image.path);
    expect(progress, [0, 1]);
    expect(adapter.requestCount, 0);
  });

  test('rejects files above the size limit before uploading', () async {
    final adapter = _FakeAdapter();
    final service = build(adapter: adapter, maxBytes: 1024);
    await expectLater(
      service.uploadImage(image, folder: UploadFolder.avatars),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          UploadErrorCode.fileTooLarge,
        ),
      ),
    );
    expect(adapter.requestCount, 0);
  });

  test('incomplete signature -> UPLOAD_FAILED without uploading', () async {
    final adapter = _FakeAdapter();
    final service = build(
      adapter: adapter,
      signature: const {'cloudName': 'demo', 'apiKey': '1'},
    );
    await expectLater(
      service.uploadImage(image, folder: UploadFolder.avatars),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          UploadErrorCode.uploadFailed,
        ),
      ),
    );
    expect(adapter.requestCount, 0);
  });

  test('signature endpoint errors pass through unchanged', () async {
    final service = CloudinaryService(
      dio: Dio()..httpClientAdapter = _FakeAdapter(),
      config: const CloudinaryConfig(useMockApi: false),
      fetchSignature: (_) async =>
          throw const ApiException(code: ApiErrorCode.forbidden),
    );
    await expectLater(
      service.uploadImage(image, folder: UploadFolder.avatars),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.forbidden,
        ),
      ),
    );
  });

  test('Cloudinary 401 is UPLOAD_FAILED (never UNAUTHORIZED)', () async {
    final adapter = _FakeAdapter(
      status: 401,
      body: {
        'error': {'message': 'Invalid Signature'},
      },
    );
    final service = build(adapter: adapter);
    await expectLater(
      service.uploadImage(image, folder: UploadFolder.avatars),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', UploadErrorCode.uploadFailed)
            .having((e) => e.message, 'message', 'Invalid Signature')
            .having((e) => e.isUnauthorized, 'isUnauthorized', isFalse),
      ),
    );
  });

  test('Cloudinary rate limit maps to TOO_MANY_REQUESTS', () async {
    final service = build(adapter: _FakeAdapter(status: 420));
    await expectLater(
      service.uploadImage(image, folder: UploadFolder.avatars),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ApiErrorCode.tooManyRequests)
            .having((e) => e.retryAfterSeconds, 'retryAfter', isNull),
      ),
    );
  });

  test('rate limit keeps Retry-After for the localized message', () {
    final options = RequestOptions();
    final error = CloudinaryService.mapDioError(
      DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<Object?>(
          requestOptions: options,
          statusCode: 429,
          headers: Headers.fromMap({
            'retry-after': ['30'],
          }),
        ),
      ),
    );
    expect(error.code, ApiErrorCode.tooManyRequests);
    expect(error.retryAfterSeconds, 30);
  });

  test('response without an https secure_url is UPLOAD_FAILED', () async {
    final service = build(
      adapter: _FakeAdapter(body: {'secure_url': 'http://insecure/a.jpg'}),
    );
    await expectLater(
      service.uploadImage(image, folder: UploadFolder.avatars),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          UploadErrorCode.uploadFailed,
        ),
      ),
    );
  });

  test('transport errors map to network / timeout / cancelled', () {
    ApiException map(DioExceptionType type) => CloudinaryService.mapDioError(
      DioException(requestOptions: RequestOptions(), type: type),
    );
    expect(map(DioExceptionType.connectionError).code, ApiErrorCode.network);
    expect(map(DioExceptionType.sendTimeout).code, ApiErrorCode.timeout);
    expect(map(DioExceptionType.receiveTimeout).code, ApiErrorCode.timeout);
    expect(map(DioExceptionType.cancel).code, ApiErrorCode.cancelled);
    expect(map(DioExceptionType.unknown).code, UploadErrorCode.uploadFailed);
  });

  test('network failure during upload surfaces as NETWORK_ERROR', () async {
    final service = build(
      adapter: _FakeAdapter(error: DioExceptionType.connectionError),
    );
    await expectLater(
      service.uploadImage(image, folder: UploadFolder.avatars),
      throwsA(
        isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', isTrue),
      ),
    );
  });

  test('in-memory XFile (no path) is uploaded from bytes', () async {
    final adapter = _FakeAdapter(body: {'secure_url': _secureUrl});
    final service = build(adapter: adapter);
    final memory = XFile.fromData(
      Uint8List.fromList(List<int>.filled(16, 1)),
      name: 'mem.png',
    );
    expect(
      await service.uploadImage(memory, folder: UploadFolder.notices),
      _secureUrl,
    );
    // On the VM cross_file ignores `name` for in-memory files; the service
    // falls back to a generic file name instead of sending none.
    final files = (adapter.lastRequest!.data as FormData).files;
    expect(files.single.value.filename, isNotEmpty);
    expect(files.single.value.length, 16);
  });

  group('CloudinarySignature.tryParse', () {
    test('accepts numeric-string timestamps', () {
      final s = CloudinarySignature.tryParse({
        ..._signature,
        'timestamp': '1790000000',
      });
      expect(s?.timestamp, 1790000000);
    });

    test('rejects missing fields and non-maps', () {
      expect(CloudinarySignature.tryParse(null), isNull);
      expect(CloudinarySignature.tryParse('x'), isNull);
      expect(
        CloudinarySignature.tryParse({..._signature, 'signature': ''}),
        isNull,
      );
      expect(
        CloudinarySignature.tryParse({..._signature, 'timestamp': null}),
        isNull,
      );
    });
  });

  test('config flags', () {
    const mockOnly = CloudinaryConfig(useMockApi: true);
    expect(mockOnly.keepLocal, isTrue);
    expect(mockOnly.useUnsigned, isFalse);
    const unsigned = CloudinaryConfig(
      useMockApi: false,
      cloudName: 'c',
      uploadPreset: 'p',
    );
    expect(unsigned.useUnsigned, isTrue);
    expect(unsigned.keepLocal, isFalse);
  });
}
