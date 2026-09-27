import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/core/settings/settings_controller.dart';
import 'package:family_hub/features/settings/application/location_upload_clock.dart';
import 'package:family_hub/shared/data/me_repository.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// What happened when the member changed their location sharing mode or
/// asked to share their location now.
enum LocationSharingOutcome {
  /// The mode was saved (`never` / `sos_only`).
  saved,

  /// Location is shared: mode `always` saved (if it changed) and a fresh fix
  /// uploaded.
  shared,

  /// Mode `always` saved, but no fix could be uploaded right now (no GPS fix,
  /// network error). The background sync retries on the next app resume.
  noFix,

  /// Location permission is missing; nothing was changed.
  permissionDenied,
}

@immutable
class LocationSharingResult {
  const LocationSharingResult._(this.outcome, {this.permission, this.sharedAt});

  const LocationSharingResult.saved() : this._(LocationSharingOutcome.saved);

  const LocationSharingResult.shared(DateTime at)
    : this._(LocationSharingOutcome.shared, sharedAt: at);

  const LocationSharingResult.noFix() : this._(LocationSharingOutcome.noFix);

  const LocationSharingResult.permissionDenied(LocationPermissionState state)
    : this._(LocationSharingOutcome.permissionDenied, permission: state);

  final LocationSharingOutcome outcome;

  /// Why permission is missing (only for [LocationSharingOutcome.permissionDenied]).
  final LocationPermissionState? permission;

  /// When the uploaded fix was recorded (only for [LocationSharingOutcome.shared]).
  final DateTime? sharedAt;

  @override
  bool operator ==(Object other) =>
      other is LocationSharingResult &&
      other.outcome == outcome &&
      other.permission == permission &&
      other.sharedAt == sharedAt;

  @override
  int get hashCode => Object.hash(outcome, permission, sharedAt);

  @override
  String toString() => 'LocationSharingResult(${outcome.name})';
}

/// Mutations of the settings feature. Every successful server change is
/// merged into the session (`applyMe`) and announced on the data-change bus
/// (`markChanged`), so every screen showing the member stays consistent.
///
/// Methods throw the repository's `ApiException` on failure (screens show it
/// with `context.showError`), except the documented best-effort parts.
class SettingsActions {
  SettingsActions(this._ref);

  final Ref _ref;

  /// Serialises account-locale updates so the last language picked wins even
  /// when the user taps through several languages quickly.
  Future<void> _localeSync = Future<void>.value();

  MeRepository get _me => _ref.read(meRepositoryProvider);
  SessionController get _session =>
      _ref.read(sessionControllerProvider.notifier);
  LocationService get _location => _ref.read(locationServiceProvider);

  /// Error codes meaning the session is out of date: the member was removed
  /// from the family, or their sharing mode was changed on another phone.
  static const _staleSessionCodes = {
    ApiErrorCode.noFamily,
    ApiErrorCode.locationSharingDisabled,
  };

  /// When [error] shows that the server's view of the membership differs
  /// from the session, re-reads `GET /auth/me` in the background so every
  /// screen — and the router (no family → family setup) — catches up.
  /// Never throws.
  void resyncIfStale(Object error) {
    if (error is ApiException && _staleSessionCodes.contains(error.code)) {
      unawaited(_refreshSession());
    }
  }

  Future<void> _refreshSession() async {
    try {
      await _session.refreshMe();
    } catch (e) {
      if (kDebugMode) debugPrint('[Settings] session refresh failed: $e');
    }
  }

  /// Runs [action]; on a "stale session" error also resyncs the session
  /// (see [resyncIfStale]) before rethrowing.
  Future<T> _resyncingOnStale<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      resyncIfStale(e);
      rethrow;
    }
  }

  Member _requireMember() {
    final member = _ref.read(currentMemberProvider);
    if (member == null) {
      throw const ApiException(
        code: ApiErrorCode.noFamily,
        message: 'Not in a family',
        statusCode: 403,
      );
    }
    return member;
  }

  // ── Profile ──────────────────────────────────────────────────────────────

  /// `PATCH /me` with the changes between [before] and [after] (name, phone,
  /// avatar, gender, date of birth). Returns `false` (and sends nothing)
  /// when nothing changed.
  Future<bool> saveProfile(Member before, Member after) async {
    final patch = MePatch.diff(before, after);
    if (patch.isEmpty) return false;
    final res = await _resyncingOnStale(() => _me.updateMe(patch));
    await _session.applyMe(res.user, res.member);
    markChanged(_ref, {DataScope.members});
    return true;
  }

  // ── Language ─────────────────────────────────────────────────────────────

  /// Switches the app language on this device (`null` = phone language) and,
  /// when signed in, stores the effective language on the account
  /// (`PATCH /me {locale}`) so pushes and emails use it. The account update
  /// is best effort: it never throws. Persisting the local setting can throw
  /// (the setting is then rolled back).
  Future<void> setLanguage(String? code) async {
    await _ref.read(settingsControllerProvider.notifier).setLocale(code);
    await syncAccountLocale();
  }

  /// Best-effort `PATCH /me {locale}` when the account language differs from
  /// the app language. Calls are chained; never throws.
  Future<void> syncAccountLocale() {
    final next = _localeSync.then((_) => _syncAccountLocaleOnce());
    _localeSync = next;
    return next;
  }

  Future<void> _syncAccountLocaleOnce() async {
    try {
      final user = _ref.read(currentUserProvider);
      if (user == null) return;
      final code = _ref.read(resolvedLocaleProvider).languageCode;
      if (user.locale == code) return;
      final res = await _me.updateMe(MePatch(locale: code));
      await _session.applyMe(res.user);
    } catch (e) {
      if (kDebugMode) debugPrint('[Settings] account locale not synced: $e');
    }
  }

  // ── Location sharing ─────────────────────────────────────────────────────

  /// Changes who can see the member's location.
  ///
  /// `always` first makes sure location permission is granted (may show the
  /// system prompt) — without it nothing changes — then saves the mode and
  /// uploads a fresh fix (`PUT /me/location`). Other modes are just saved.
  Future<LocationSharingResult> setLocationSharing(
    LocationSharingMode mode,
  ) async {
    final member = _requireMember();
    if (mode == LocationSharingMode.always) {
      final permission = await _location.ensurePermission();
      if (!permission.isGranted) {
        return LocationSharingResult.permissionDenied(permission);
      }
    }
    if (member.locationSharing != mode) {
      final res = await _resyncingOnStale(
        () => _me.updateMe(MePatch(locationSharing: mode)),
      );
      await _session.applyMe(res.user, res.member);
      markChanged(_ref, {DataScope.members});
    }
    if (mode != LocationSharingMode.always) {
      return const LocationSharingResult.saved();
    }
    try {
      final result = await shareLocationNow();
      return result.outcome == LocationSharingOutcome.shared
          ? result
          : const LocationSharingResult.noFix();
    } catch (e) {
      // The mode is saved; the background sync shares on the next resume.
      if (kDebugMode) debugPrint('[Settings] first location upload failed: $e');
      return const LocationSharingResult.noFix();
    }
  }

  /// Uploads the current location now (`always` mode only). Asks for
  /// permission if needed. A missing or too old fix (see [isShareableFix])
  /// is [LocationSharingOutcome.noFix]. Throws the API error (e.g.
  /// `LOCATION_SHARING_DISABLED` — the session is then resynced — or
  /// network errors).
  Future<LocationSharingResult> shareLocationNow() async {
    final member = _requireMember();
    final location = _location;
    final permission = await location.ensurePermission();
    if (!permission.isGranted) {
      return LocationSharingResult.permissionDenied(permission);
    }
    final fix = await location.currentFix();
    if (fix == null ||
        !isShareableFix(fix, _ref.read(settingsClockProvider)())) {
      return const LocationSharingResult.noFix();
    }

    final DateTime recordedAt;
    try {
      recordedAt =
          await _resyncingOnStale(
            () => _me.updateLocation(
              lat: fix.lat,
              lng: fix.lng,
              accuracy: fix.accuracy,
            ),
          ) ??
          fix.at;
    } on ArgumentError catch (e) {
      // Unusable coordinates from the platform: nothing was sent.
      if (kDebugMode) debugPrint('[Settings] invalid location fix: $e');
      return const LocationSharingResult.noFix();
    }
    _ref.read(locationUploadClockProvider.notifier).record();

    // Show the fresh fix right away ("last shared just now").
    final current = _ref.read(currentMemberProvider) ?? member;
    if (current.id == member.id) {
      await _session.applyMe(
        null,
        current.copyWith(
          lastLocation: () => GeoPoint(
            lat: fix.lat,
            lng: fix.lng,
            accuracy: fix.accuracy,
            recordedAt: recordedAt,
          ),
        ),
      );
    }
    markChanged(_ref, {DataScope.members});
    return LocationSharingResult.shared(recordedAt);
  }

  // ── Account ──────────────────────────────────────────────────────────────

  /// `POST /auth/change-password`. Errors: `INVALID_CREDENTIALS` (wrong
  /// current password), `VALIDATION_ERROR`.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _ref
      .read(authRepositoryProvider)
      .changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

  /// `POST /me/leave-family`. The session switches to "no family" and the
  /// router opens family setup. A background `GET /auth/me` then re-syncs the
  /// whole session (best effort). Errors: `LAST_ADMIN`.
  ///
  /// `NO_FAMILY` (already out of the family: a retry after a lost response,
  /// or an admin removed the member meanwhile) counts as success once the
  /// refreshed session agrees.
  Future<void> leaveFamily() async {
    try {
      await _session.leaveFamily();
    } on ApiException catch (e) {
      if (e.code != ApiErrorCode.noFamily) rethrow;
      await _refreshSession();
      if (_ref.read(currentFamilyProvider) != null) rethrow;
      return;
    }
    unawaited(_refreshSession());
  }

  /// `DELETE /me`, then signs out locally. Errors: `INVALID_CREDENTIALS`,
  /// `LAST_ADMIN`.
  Future<void> deleteAccount(String password) =>
      _session.deleteAccount(password);

  /// Signs out (never throws).
  Future<void> logout() => _session.logout();
}

final settingsActionsProvider = Provider<SettingsActions>(SettingsActions.new);
