import 'package:flutter/foundation.dart';

import 'package:family_hub/shared/json.dart';

/// A notice on the family notice board (docs/03-API_CONTRACT.md §9).
///
/// `{ id, title, body, imageUrl|null, pinned, authorId, authorName,
///    authorAvatarUrl|null, createdAt, updatedAt }`
///
/// `authorId` is a **member** id. `authorName` / `authorAvatarUrl` are
/// resolved by the server at read time (so avatar changes show up on old
/// notices). Parsing is defensive: missing or wrongly-typed fields never
/// throw (docs/05-FLUTTER_GUIDE.md §1.6).
@immutable
class Notice {
  const Notice({
    required this.id,
    required this.title,
    required this.body,
    this.imageUrl,
    this.pinned = false,
    required this.authorId,
    required this.authorName,
    this.authorAvatarUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Contract limits (backend zod + Mongoose schema, UTF-16 code units).
  static const int titleMaxLength = 100;
  static const int bodyMaxLength = 2000;

  factory Notice.fromJson(Map<String, dynamic> json) {
    final created =
        parseDate(json['createdAt']) ??
        parseDate(json['updatedAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return Notice(
      id: asStringOr(json['id'], ''),
      title: asStringOr(json['title'], '').trim(),
      body: asStringOr(json['body'], '').trim(),
      imageUrl: asNonEmptyString(json['imageUrl'])?.trim(),
      pinned: asBool(json['pinned']),
      authorId: asStringOr(json['authorId'], ''),
      authorName: asStringOr(json['authorName'], '').trim(),
      authorAvatarUrl: asNonEmptyString(json['authorAvatarUrl'])?.trim(),
      createdAt: created,
      updatedAt: parseDate(json['updatedAt']) ?? created,
    );
  }

  final String id;
  final String title;
  final String body;

  /// Cloudinary `secure_url` (or a local file path in mock mode).
  final String? imageUrl;

  /// Pinned notices are listed before all others. Only admins can pin.
  final bool pinned;

  /// Member id of the author.
  final String authorId;

  /// Display name of the author; empty when the server does not know it
  /// (e.g. the member was removed from the family).
  final String authorName;
  final String? authorAvatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasImage => imageUrl != null;

  /// Whether [memberId] wrote this notice.
  bool isAuthoredBy(String? memberId) =>
      memberId != null && memberId.isNotEmpty && memberId == authorId;

  /// Board order, identical to `GET /notices`: pinned first, then newest
  /// first (`createdAt` desc). Ties are broken by id (ObjectIds grow over
  /// time) so the order is stable.
  static int compareForBoard(Notice a, Notice b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final byDate = b.createdAt.compareTo(a.createdAt);
    if (byDate != 0) return byDate;
    return b.id.compareTo(a.id);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'imageUrl': imageUrl,
    'pinned': pinned,
    'authorId': authorId,
    'authorName': authorName,
    'authorAvatarUrl': authorAvatarUrl,
    'createdAt': isoOrNull(createdAt),
    'updatedAt': isoOrNull(updatedAt),
  };

  /// Nullable fields take a [ValueGetter] so they can be cleared:
  /// `notice.copyWith(imageUrl: () => null)`.
  Notice copyWith({
    String? id,
    String? title,
    String? body,
    ValueGetter<String?>? imageUrl,
    bool? pinned,
    String? authorId,
    String? authorName,
    ValueGetter<String?>? authorAvatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Notice(
    id: id ?? this.id,
    title: title ?? this.title,
    body: body ?? this.body,
    imageUrl: imageUrl == null ? this.imageUrl : imageUrl(),
    pinned: pinned ?? this.pinned,
    authorId: authorId ?? this.authorId,
    authorName: authorName ?? this.authorName,
    authorAvatarUrl: authorAvatarUrl == null
        ? this.authorAvatarUrl
        : authorAvatarUrl(),
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Notice &&
          other.id == id &&
          other.title == title &&
          other.body == body &&
          other.imageUrl == imageUrl &&
          other.pinned == pinned &&
          other.authorId == authorId &&
          other.authorName == authorName &&
          other.authorAvatarUrl == authorAvatarUrl &&
          other.createdAt.isAtSameMomentAs(createdAt) &&
          other.updatedAt.isAtSameMomentAs(updatedAt);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    body,
    imageUrl,
    pinned,
    authorId,
    authorName,
    authorAvatarUrl,
    createdAt.millisecondsSinceEpoch,
    updatedAt.millisecondsSinceEpoch,
  );

  @override
  String toString() => 'Notice($id, "$title", pinned: $pinned)';
}

/// What the signed-in member may do with notices — the UI mirror of the
/// backend rules (contract §9, docs/02-ARCHITECTURE.md permission matrix):
///
/// | action            | admin | member   |
/// |-------------------|-------|----------|
/// | post              | yes   | yes      |
/// | pin / unpin       | yes   | no       |
/// | edit / delete     | any   | own only |
///
/// The backend is authoritative; screens still handle `FORBIDDEN`.
@immutable
class NoticePermissions {
  const NoticePermissions({required this.memberId, required this.isAdmin});

  /// Signed out / without a family: nothing is allowed.
  static const none = NoticePermissions(memberId: null, isAdmin: false);

  /// Member id of the signed-in user (`null` without a family).
  final String? memberId;
  final bool isAdmin;

  bool get _isMember => memberId != null && memberId!.isNotEmpty;

  bool get canCreate => _isMember;

  bool get canPin => _isMember && isAdmin;

  bool canEdit(Notice notice) =>
      _isMember && (isAdmin || notice.isAuthoredBy(memberId));

  bool canDelete(Notice notice) => canEdit(notice);

  @override
  bool operator ==(Object other) =>
      other is NoticePermissions &&
      other.memberId == memberId &&
      other.isAdmin == isAdmin;

  @override
  int get hashCode => Object.hash(memberId, isAdmin);
}
