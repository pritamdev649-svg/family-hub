import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/providers/core_providers.dart';
import 'package:family_hub/features/notices/domain/notice.dart';
import 'package:family_hub/shared/data/repository_utils.dart';

/// Body of `POST /notices` (contract §9).
///
/// `title` and `body` are trimmed; `imageUrl` is omitted when there is no
/// image and `pinned` is only sent when set (the server ignores it for
/// non-admins anyway).
@immutable
class NoticeDraft {
  const NoticeDraft({
    required this.title,
    required this.body,
    this.imageUrl,
    this.pinned,
  });

  final String title;
  final String body;
  final String? imageUrl;
  final bool? pinned;

  Map<String, dynamic> toJson() => {
    'title': title.trim(),
    'body': body.trim(),
    'imageUrl': ?trimOrNull(imageUrl),
    'pinned': ?pinned,
  };

  @override
  bool operator ==(Object other) =>
      other is NoticeDraft &&
      other.title == title &&
      other.body == body &&
      other.imageUrl == imageUrl &&
      other.pinned == pinned;

  @override
  int get hashCode => Object.hash(title, body, imageUrl, pinned);
}

/// Body of `PATCH /notices/:id` — exactly the fields to change.
///
/// `imageUrl: null` in [fields] removes the image. `pinned` is admin-only on
/// the server; only send it when the current member is an admin.
class NoticePatch extends PatchBody {
  const NoticePatch._(super.fields);

  factory NoticePatch({
    String? title,
    String? body,
    String? imageUrl,
    bool clearImage = false,
    bool? pinned,
  }) {
    final image = trimOrNull(imageUrl);
    return NoticePatch._(
      Map.unmodifiable(<String, dynamic>{
        'title': ?trimOrNull(title),
        'body': ?trimOrNull(body),
        if (image != null)
          'imageUrl': image
        else if (clearImage)
          'imageUrl': null,
        'pinned': ?pinned,
      }),
    );
  }

  /// Only pin / unpin.
  factory NoticePatch.pin(bool pinned) => NoticePatch(pinned: pinned);

  /// The changes between [before] and the edit form's values. Blank title or
  /// body never clear the server value (the form validates them anyway); a
  /// blank [imageUrl] removes the image. Pass [pinned] only for admins.
  factory NoticePatch.diff(
    Notice before, {
    required String title,
    required String body,
    required String? imageUrl,
    bool? pinned,
  }) {
    final t = trimOrNull(title);
    final b = trimOrNull(body);
    final image = trimOrNull(imageUrl);
    return NoticePatch(
      title: t != null && t != before.title ? t : null,
      body: b != null && b != before.body ? b : null,
      imageUrl: image != before.imageUrl ? image : null,
      clearImage: image == null && before.imageUrl != null,
      pinned: pinned != null && pinned != before.pinned ? pinned : null,
    );
  }
}

/// `/notices` endpoints (contract §9).
class NoticesRepository {
  NoticesRepository(this._api);

  final ApiClient _api;

  static const String _base = '/notices';

  /// Largest page the API serves (contract §1).
  static const int maxPageSize = 100;

  /// How many pages [findById] scans at most (100 × 20 = 2000 notices).
  static const int _maxScanPages = 20;

  /// `GET /notices?page&limit` — pinned first, then newest first.
  Future<Paged<Notice>> list({int page = 1, int limit = 20}) =>
      _api.getPaged(_base, Notice.fromJson, page: page, limit: limit);

  /// `POST /notices` → the created notice.
  Future<Notice> create(NoticeDraft draft) async => Notice.fromJson(
    requireObject(await _api.post(_base, body: draft.toJson())),
  );

  /// `PATCH /notices/:id` → the updated notice.
  Future<Notice> update(String id, NoticePatch patch) async => Notice.fromJson(
    requireObject(
      await _api.patch('$_base/${pathId(id)}', body: patch.toJson()),
    ),
  );

  /// `DELETE /notices/:id`.
  Future<void> delete(String id) async {
    await _api.delete('$_base/${pathId(id)}');
  }

  /// One notice by id. The contract has no `GET /notices/:id`, so this pages
  /// through the board (largest pages first) — used when an edit screen is
  /// opened without the notice in memory (deep link, restored route).
  /// Throws `NOT_FOUND` when it does not exist (or is another family's).
  Future<Notice> findById(String id) async {
    final wanted = id.trim();
    if (wanted.isEmpty) {
      throw const ApiException(code: ApiErrorCode.notFound, statusCode: 404);
    }
    for (var page = 1; page <= _maxScanPages; page++) {
      final result = await list(page: page, limit: maxPageSize);
      for (final notice in result.items) {
        if (notice.id == wanted) return notice;
      }
      if (!result.hasMore || result.items.isEmpty) break;
    }
    throw const ApiException(code: ApiErrorCode.notFound, statusCode: 404);
  }
}

final noticesRepositoryProvider = Provider<NoticesRepository>(
  (ref) => NoticesRepository(ref.watch(apiClientProvider)),
);
