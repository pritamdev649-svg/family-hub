/// Helpers shared by repositories: strict-but-safe response unwrapping and
/// normalisation of user input before it is sent to the API.
///
/// Parsing individual fields is lenient (see `json.dart`), but a response
/// whose *shape* is wrong (e.g. `data.user` missing on login) is a server /
/// proxy bug: it surfaces as `ApiException(UNKNOWN)` instead of a crash or a
/// half-populated model.
library;

import 'package:flutter/foundation.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/shared/json.dart';

/// Returns `data` (or `data[key]`) as an object, or throws
/// `ApiException.unknown` when it is not one.
Map<String, dynamic> requireObject(Object? data, [String? key]) {
  final value = key == null ? data : asMap(data)[key];
  if (value is! Map) {
    throw ApiException.unknown(
      'Malformed response: expected an object${key == null ? '' : ' at "$key"'}',
    );
  }
  return asMap(value);
}

/// Like [requireObject] but returns `null` when the value is `null` / absent
/// (e.g. `member: null` in `GET /auth/me` for users without a family).
Map<String, dynamic>? optionalObject(Object? data, String key) {
  final value = asMap(data)[key];
  return value is Map ? asMap(value) : null;
}

/// Returns `data` as a list or throws `ApiException.unknown`.
List<Object?> requireList(Object? data) {
  if (data is! List) {
    throw const ApiException.unknown('Malformed response: expected a list');
  }
  return data;
}

/// URL-encodes a resource id for a path segment. A blank id can never exist
/// on the server, so it fails fast as `NOT_FOUND` instead of hitting a
/// different route (`/family/members/` = the list endpoint).
String pathId(String id) {
  final trimmed = id.trim();
  if (trimmed.isEmpty) {
    throw const ApiException(
      code: ApiErrorCode.notFound,
      message: 'Empty id',
      statusCode: 404,
    );
  }
  return Uri.encodeComponent(trimmed);
}

/// Trimmed text, or `null` when blank.
String? trimOrNull(String? v) {
  final t = v?.trim();
  return t == null || t.isEmpty ? null : t;
}

/// Emails are trimmed + lower-cased everywhere (contract §4); blank → null.
String? normalizeEmail(String? v) => trimOrNull(v)?.toLowerCase();

/// Removes spaces, dashes, dots and parentheses users type in phone numbers
/// (`+91 98765-43210` → `+919876543210`); blank → null.
String? normalizePhone(String? v) {
  final t = trimOrNull(v);
  if (t == null) return null;
  final cleaned = t.replaceAll(RegExp(r'[\s\-().]'), '');
  return cleaned.isEmpty ? null : cleaned;
}

/// Invite codes are matched case-insensitively; users may paste them with
/// spaces or dashes (`k7q2-m9xd`) → `K7Q2M9XD`.
String normalizeInviteCode(String v) =>
    v.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();

/// One-time passwords: digits only (users paste `123 456`).
String normalizeOtp(String v) => v.replaceAll(RegExp(r'\D'), '');

/// Base class of PATCH bodies: an immutable map of exactly the fields to send
/// (a field mapped to `null` clears it on the server).
@immutable
abstract class PatchBody {
  const PatchBody(this.fields);

  /// Fields to send. Unmodifiable.
  final Map<String, dynamic> fields;

  /// Nothing to send (callers can skip the request).
  bool get isEmpty => fields.isEmpty;

  Map<String, dynamic> toJson() => Map<String, dynamic>.of(fields);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is PatchBody &&
          mapEquals(other.fields, fields);

  @override
  int get hashCode => Object.hash(
    runtimeType,
    Object.hashAllUnordered(
      fields.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() => '$runtimeType(${fields.keys.join(', ')})';
}

/// Collects the changes between two versions of a record for a
/// `*Patch.diff(before, after)` factory:
///
/// ```dart
/// final d = PatchDiff<MemberPatchField>();
/// MemberPatch(phone: d(before.phone, after.phone, MemberPatchField.phone),
///             clear: d.cleared);
/// ```
/// Calling it returns the new value when it differs from the old one (else
/// `null` = "unchanged"); a value that became `null` is added to [cleared]
/// when a clearable [field] is given.
class PatchDiff<F extends Enum> {
  final Set<F> cleared = <F>{};

  T? call<T>(T? old, T? now, [F? field]) {
    if (old == now) return null;
    if (now == null && field != null) cleared.add(field);
    return now;
  }
}
