import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/shared/data/repository_utils.dart';
import 'package:family_hub/shared/json.dart';
import 'package:family_hub/shared/models/auth_user.dart';
import 'package:family_hub/shared/models/member.dart';

/// Nullable profile fields a [MePatch] can explicitly clear (send `null`).
enum MePatchField { phone, avatarUrl, gender, dateOfBirth }

/// Body of `PATCH /me`. Only the given fields are sent; fields listed in
/// `clear` are sent as `null`.
class MePatch extends PatchBody {
  factory MePatch({
    String? name,
    String? phone,
    String? avatarUrl,
    String? locale,
    LocationSharingMode? locationSharing,
    Gender? gender,
    DateTime? dateOfBirth,
    Set<MePatchField> clear = const {},
  }) {
    return MePatch._(
      Map.unmodifiable(<String, dynamic>{
        for (final f in clear) f.name: null,
        'name': ?trimOrNull(name),
        'phone': ?normalizePhone(phone),
        'avatarUrl': ?trimOrNull(avatarUrl),
        'locale': ?trimOrNull(locale),
        'locationSharing': ?locationSharing?.wireName,
        'gender': ?gender?.wireName,
        'dateOfBirth': ?isoOrNull(dateOfBirth),
      }),
    );
  }

  /// Profile changes between the caller's member record [before] and the
  /// edited [after] (name, phone, avatar, gender, date of birth). Cleared
  /// values are sent as `null`. Locale / location sharing are set directly
  /// with the default constructor.
  factory MePatch.diff(Member before, Member after) {
    final d = PatchDiff<MePatchField>();
    return MePatch(
      name: d(before.name.trim(), after.name.trim()),
      phone: d(
        normalizePhone(before.phone),
        normalizePhone(after.phone),
        MePatchField.phone,
      ),
      avatarUrl: d(
        trimOrNull(before.avatarUrl),
        trimOrNull(after.avatarUrl),
        MePatchField.avatarUrl,
      ),
      gender: d(before.gender, after.gender, MePatchField.gender),
      dateOfBirth: d(
        before.dateOfBirth,
        after.dateOfBirth,
        MePatchField.dateOfBirth,
      ),
      clear: d.cleared,
    );
  }

  const MePatch._(super.fields);
}

/// `platform` of `POST /me/devices`.
enum DevicePlatform { android, ios }

/// `/me` endpoints — the signed-in user's own account (docs/03 §5).
class MeRepository {
  MeRepository(this._api);

  final ApiClient _api;

  /// `PATCH /me` → `{ user, member }` (`member` is `null` without a family).
  Future<({AuthUser user, Member? member})> updateMe(MePatch patch) async {
    final data = await _api.patch('/me', body: patch.toJson());
    final memberJson = optionalObject(data, 'member');
    final member = memberJson == null ? null : Member.fromJson(memberJson);
    return (
      user: AuthUser.fromJson(requireObject(data, 'user')),
      member: member == null || member.id.isEmpty ? null : member,
    );
  }

  /// `PUT /me/location` (only when sharing mode is `always`) → server
  /// `recordedAt`. Invalid coordinates are rejected locally with
  /// `ArgumentError`; a negative / non-finite accuracy is omitted.
  /// Errors: `LOCATION_SHARING_DISABLED`.
  Future<DateTime?> updateLocation({
    required double lat,
    required double lng,
    double? accuracy,
  }) async {
    if (!lat.isFinite || lat < -90 || lat > 90) {
      throw ArgumentError.value(lat, 'lat', 'must be within -90..90');
    }
    if (!lng.isFinite || lng < -180 || lng > 180) {
      throw ArgumentError.value(lng, 'lng', 'must be within -180..180');
    }
    final data = await _api.put(
      '/me/location',
      body: {
        'lat': lat,
        'lng': lng,
        if (accuracy != null && accuracy.isFinite && accuracy >= 0)
          'accuracy': accuracy,
      },
    );
    return parseDate(asMap(data)['recordedAt']);
  }

  /// `POST /me/devices` — upserts the FCM token for this user.
  Future<void> registerDevice({
    required String token,
    required DevicePlatform platform,
    String? locale,
  }) async {
    await _api.post(
      '/me/devices',
      body: {
        'token': token,
        'platform': platform.name,
        'locale': ?trimOrNull(locale),
      },
    );
  }

  /// `DELETE /me/devices/:token`.
  Future<void> unregisterDevice(String token) async {
    await _api.delete('/me/devices/${pathId(token)}');
  }

  /// `GET /me/export` — the caller's personal data (right of access).
  Future<Map<String, dynamic>> exportData() async =>
      asMap(await _api.get('/me/export'));

  /// `DELETE /me` — deletes the account. Errors: `INVALID_CREDENTIALS`,
  /// `LAST_ADMIN`. The caller must then clear the local session.
  Future<void> deleteAccount(String password) async {
    await _api.delete('/me', body: {'password': password});
  }

  /// `POST /me/leave-family` → the updated `user` (no family).
  /// Errors: `LAST_ADMIN`.
  Future<AuthUser> leaveFamily() async => AuthUser.fromJson(
    requireObject(await _api.post('/me/leave-family'), 'user'),
  );
}
