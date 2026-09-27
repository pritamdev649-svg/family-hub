import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/providers/core_providers.dart'
    show apiClientProvider;
import 'package:family_hub/shared/json.dart';

/// Where an image belongs. The wire value (`avatars` / `notices`) is the
/// `folder` of `POST /uploads/signature`.
enum UploadFolder { avatars, notices }

/// Error codes raised by [CloudinaryService] in addition to the client
/// codes of [ApiErrorCode] (`NETWORK_ERROR`, `TIMEOUT`, `CANCELLED`,
/// `TOO_MANY_REQUESTS`, ...). `localizedErrorMessage` maps them to the
/// `servicesError*` strings.
abstract final class UploadErrorCode {
  /// Cloudinary rejected the upload or returned an unusable response.
  static const uploadFailed = 'UPLOAD_FAILED';

  /// The picked file exceeds [CloudinaryService.maxBytes].
  static const fileTooLarge = 'FILE_TOO_LARGE';
}

/// Signed-upload parameters returned by `POST /uploads/signature`.
@immutable
class CloudinarySignature {
  const CloudinarySignature({
    required this.cloudName,
    required this.apiKey,
    required this.timestamp,
    required this.signature,
    required this.folder,
  });

  /// Parses the endpoint's `data`. Returns `null` when a field is missing,
  /// because an incomplete signature can only produce a rejected upload.
  static CloudinarySignature? tryParse(Object? json) {
    final m = asMap(json);
    final cloudName = asNonEmptyString(m['cloudName']);
    final apiKey = asNonEmptyString(m['apiKey']);
    final signature = asNonEmptyString(m['signature']);
    final folder = asNonEmptyString(m['folder']);
    final timestamp = asInt(m['timestamp'], -1);
    if (cloudName == null ||
        apiKey == null ||
        signature == null ||
        folder == null ||
        timestamp <= 0) {
      return null;
    }
    return CloudinarySignature(
      cloudName: cloudName,
      apiKey: apiKey,
      timestamp: timestamp,
      signature: signature,
      folder: folder,
    );
  }

  final String cloudName;
  final String apiKey;

  /// Unix seconds - part of the signed payload, sent back unchanged.
  final int timestamp;
  final String signature;

  /// Full folder, e.g. `familyhub/<familyId>/avatars` (signed as well).
  final String folder;
}

/// Upload configuration; defaults come from `--dart-define` via [AppConfig].
@immutable
class CloudinaryConfig {
  const CloudinaryConfig({
    required this.useMockApi,
    this.cloudName = '',
    this.uploadPreset = '',
  });

  factory CloudinaryConfig.fromAppConfig() => CloudinaryConfig(
    useMockApi: AppConfig.useMockApi,
    cloudName: AppConfig.cloudinaryCloudName,
    uploadPreset: AppConfig.cloudinaryUploadPreset,
  );

  final bool useMockApi;
  final String cloudName;
  final String uploadPreset;

  /// Unsigned uploads with a preset (no backend round trip). Mirrors
  /// [AppConfig.useUnsignedCloudinary].
  bool get useUnsigned => cloudName.isNotEmpty && uploadPreset.isNotEmpty;

  /// Mock backend and no Cloudinary account configured: nothing can be
  /// uploaded, so the local file path is used as the "URL"
  /// (`AppNetworkImage` renders local paths with `Image.file`).
  bool get keepLocal => useMockApi && !useUnsigned;
}

/// Fetches the signed-upload parameters for [folder]; returns the unwrapped
/// `data` of `POST /uploads/signature`.
typedef UploadSignatureFetcher = Future<Object?> Function(UploadFolder folder);

/// Uploads images straight to Cloudinary (docs/03-API_CONTRACT.md §12).
///
/// Uses its **own** [Dio] without the auth / locale interceptors: the
/// backend access token must never be sent to a third-party host.
class CloudinaryService {
  CloudinaryService({
    required UploadSignatureFetcher fetchSignature,
    CloudinaryConfig? config,
    Dio? dio,
    this.maxBytes = defaultMaxBytes,
  }) : _fetchSignature = fetchSignature,
       _config = config ?? CloudinaryConfig.fromAppConfig(),
       _dio = dio ?? _createDio();

  /// Cloudinary's image limit on the free plan. Pickers already resize to
  /// 1600 px / quality 80, so real photos stay far below this.
  static const defaultMaxBytes = 10 * 1024 * 1024;

  static const _uploadHost = 'https://api.cloudinary.com/v1_1';
  static const _unsignedFolderRoot = 'familyhub';

  final UploadSignatureFetcher _fetchSignature;
  final CloudinaryConfig _config;
  final Dio _dio;
  final int maxBytes;

  static Dio _createDio() => Dio(
    BaseOptions(
      connectTimeout: AppConfig.connectTimeout,
      // Large photos on slow mobile networks need more than an API call.
      sendTimeout: const Duration(minutes: 2),
      receiveTimeout: AppConfig.receiveTimeout,
      responseType: ResponseType.json,
    ),
  );

  /// Uploads [file] and returns its `secure_url`
  /// (`https://res.cloudinary.com/...`), or the local path in mock mode
  /// without Cloudinary config.
  ///
  /// [onProgress] receives values from 0.0 to 1.0 (1.0 only once the URL is
  /// known). Throws only [ApiException] (codes from [UploadErrorCode] or the
  /// contract, e.g. from the signature endpoint).
  Future<String> uploadImage(
    XFile file, {
    required UploadFolder folder,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    onProgress?.call(0);
    if (_config.keepLocal) {
      onProgress?.call(1);
      return file.path;
    }

    try {
      final size = await file.length();
      if (size > maxBytes) {
        throw ApiException(
          code: UploadErrorCode.fileTooLarge,
          message: 'Image is $size bytes; the limit is $maxBytes bytes.',
          details: {'maxBytes': maxBytes, 'size': size},
        );
      }

      final String cloudName;
      final Map<String, Object> fields;
      if (_config.useUnsigned) {
        cloudName = _config.cloudName;
        fields = {
          'upload_preset': _config.uploadPreset,
          'folder': '$_unsignedFolderRoot/${folder.name}',
        };
      } else {
        final signature = CloudinarySignature.tryParse(
          await _fetchSignature(folder),
        );
        if (signature == null) {
          throw const ApiException(
            code: UploadErrorCode.uploadFailed,
            message: 'The upload signature response is incomplete.',
          );
        }
        cloudName = signature.cloudName;
        // Exactly the signed parameters - anything extra breaks the
        // signature check on Cloudinary's side.
        fields = {
          'api_key': signature.apiKey,
          'timestamp': signature.timestamp.toString(),
          'signature': signature.signature,
          'folder': signature.folder,
        };
      }

      final form = FormData.fromMap({
        ...fields,
        'file': await _multipartFile(file),
      });

      final response = await _dio.post<Object?>(
        '$_uploadHost/${Uri.encodeComponent(cloudName)}/image/upload',
        data: form,
        cancelToken: cancelToken,
        onSendProgress: onProgress == null
            ? null
            : (sent, total) {
                if (total <= 0) return;
                // Keep a sliver for Cloudinary's processing time.
                onProgress(math.min(sent / total, 0.99));
              },
      );

      final url = secureUrlFrom(response.data);
      if (url == null) {
        throw const ApiException(
          code: UploadErrorCode.uploadFailed,
          message: 'Cloudinary did not return a secure URL.',
        );
      }
      onProgress?.call(1);
      return url;
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      throw mapDioError(e);
    } catch (e) {
      // File could not be read, unexpected response type, ...
      throw ApiException(
        code: UploadErrorCode.uploadFailed,
        message: 'Upload failed: $e',
      );
    }
  }

  /// The `secure_url` of an upload response when it is an absolute https
  /// URL, else `null`.
  @visibleForTesting
  static String? secureUrlFrom(Object? responseData) {
    final url = asNonEmptyString(asMap(responseData)['secure_url'])?.trim();
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return url;
  }

  static Future<MultipartFile> _multipartFile(XFile file) async {
    final name = _fileName(file);
    if (kIsWeb || file.path.isEmpty) {
      // Web XFiles are blob URLs and in-memory XFiles have no path.
      return MultipartFile.fromBytes(await file.readAsBytes(), filename: name);
    }
    return MultipartFile.fromFile(file.path, filename: name);
  }

  static String _fileName(XFile file) {
    final name = file.name.trim();
    if (name.isNotEmpty) return name;
    final segments = Uri.tryParse(file.path)?.pathSegments ?? const [];
    return segments.isNotEmpty && segments.last.isNotEmpty
        ? segments.last
        : 'upload.jpg';
  }

  /// Maps a Cloudinary transport/HTTP failure to an [ApiException].
  ///
  /// HTTP errors are mapped here, not by [ApiException.fromDio]: that one
  /// reads our backend's envelope and would turn Cloudinary's 401 (bad
  /// signature) into `UNAUTHORIZED`, which signs the user out.
  @visibleForTesting
  static ApiException mapDioError(DioException e) {
    if (e.type != DioExceptionType.badResponse) {
      // Timeouts, offline, cancellation (`CANCELLED`, never shown).
      final mapped = ApiException.fromDio(e);
      return mapped.code == ApiErrorCode.unknown
          ? ApiException(
              code: UploadErrorCode.uploadFailed,
              message: mapped.message,
            )
          : mapped;
    }
    final status = e.response?.statusCode;
    final message =
        asNonEmptyString(asMap(asMap(e.response?.data)['error'])['message']) ??
        'Cloudinary rejected the upload (HTTP $status).';
    final rateLimited = status == 420 || status == 429;
    if (rateLimited) {
      final retryAfter = int.tryParse(
        e.response?.headers.value('retry-after')?.trim() ?? '',
      );
      return ApiException(
        code: ApiErrorCode.tooManyRequests,
        message: message,
        statusCode: status,
        details: retryAfter == null || retryAfter < 0
            ? null
            : {'retryAfterSeconds': retryAfter},
      );
    }
    return ApiException(
      code: UploadErrorCode.uploadFailed,
      message: message,
      statusCode: status,
    );
  }
}

final cloudinaryServiceProvider = Provider<CloudinaryService>((ref) {
  final api = ref.watch(apiClientProvider);
  return CloudinaryService(
    fetchSignature: (folder) =>
        api.post('/uploads/signature', body: {'folder': folder.name}),
  );
});
