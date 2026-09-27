import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/network/api_client.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/features/family/family_routes.dart';
import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/data/family_repository.dart';
import 'package:family_hub/shared/models/models.dart';
import 'package:family_hub/shared/session/session_controller.dart';

// ── Test data ───────────────────────────────────────────────────────────────

const familyId = 'fam1';
const adminUserId = 'user-admin';
const memberUserId = 'user-member';

Family testFamily({
  String country = 'IN',
  String currency = 'INR',
  String timezone = 'Asia/Kolkata',
  String? inviteCode = 'K7Q2M9XD',
  int memberCount = 4,
}) => Family(
  id: familyId,
  name: 'Sharma Family',
  country: country,
  currency: currency,
  timezone: timezone,
  inviteCode: inviteCode,
  memberCount: memberCount,
);

/// Local midnight of a calendar day, like the date picker returns.
DateTime day(int y, int m, int d) => DateTime(y, m, d);

/// A birth date making the person [years] old today.
DateTime birthDateForAge(int years) {
  final now = DateTime.now();
  return DateTime(now.year - years, now.month, 1);
}

Member testMember({
  String id = 'm-admin',
  String name = 'Amit',
  MemberRole role = MemberRole.admin,
  String? userId = adminUserId,
  String? email = 'amit@example.com',
  String? phone = '+919876543210',
  DateTime? dateOfBirth,
  Gender? gender = Gender.male,
  String? designation = 'Head of Family',
  bool guardianConsent = false,
  LocationSharingMode locationSharing = LocationSharingMode.never,
}) => Member(
  id: id,
  familyId: familyId,
  name: name,
  userId: userId,
  email: email,
  phone: phone,
  dateOfBirth: (dateOfBirth ?? day(1985, 2, 1)).toUtc(),
  gender: gender,
  designation: designation,
  role: role,
  hasAccount: userId != null,
  guardianConsent: guardianConsent,
  locationSharing: locationSharing,
);

final amit = testMember();
final kamla = testMember(
  id: 'm-kamla',
  name: 'Kamla',
  role: MemberRole.member,
  userId: memberUserId,
  email: 'kamla@example.com',
  phone: null,
  dateOfBirth: day(1952, 11, 3),
  gender: Gender.female,
  designation: 'Family Advisor',
);
final aarav = testMember(
  id: 'm-aarav',
  name: 'Aarav',
  role: MemberRole.member,
  userId: null,
  email: 'aarav@example.com',
  phone: null,
  dateOfBirth: birthDateForAge(15),
  designation: 'Chief Study Officer',
  guardianConsent: true,
);
final anaya = testMember(
  id: 'm-anaya',
  name: 'Anaya',
  role: MemberRole.member,
  userId: null,
  email: null,
  phone: null,
  dateOfBirth: birthDateForAge(9),
  gender: Gender.female,
  designation: null,
);

SessionState sessionFor(Member me, {Family? family}) => SessionState(
  user: AuthUser(
    id: me.userId ?? 'user-${me.id}',
    email: me.email ?? 'someone@example.com',
    name: me.name,
    emailVerified: true,
    familyId: familyId,
    memberId: me.id,
    role: me.role,
  ),
  member: me,
  family: family ?? testFamily(inviteCode: me.isAdmin ? 'K7Q2M9XD' : null),
);

// ── Fakes ───────────────────────────────────────────────────────────────────

/// Signed-in session with a recorded [applyMe] and [refreshMe] (no
/// storage, no network).
class FakeSession extends SessionController {
  FakeSession(this.initial);

  final SessionState initial;
  final List<({AuthUser? user, Member? member, Family? family})> applied = [];

  /// Number of `refreshMe` calls (session resyncs).
  int refreshes = 0;

  /// What `GET /auth/me` "returns" on the next [refreshMe] (null: keep).
  SessionState? onRefresh;

  /// Holds [refreshMe] until completed (to test concurrent resyncs).
  Completer<void>? refreshGate;

  @override
  Future<SessionState> build() async => initial;

  @override
  Future<void> refreshMe() async {
    refreshes++;
    final gate = refreshGate;
    if (gate != null) await gate.future;
    final next = onRefresh;
    if (next != null) state = AsyncData(next);
  }

  @override
  Future<void> applyMe([AuthUser? user, Member? member, Family? family]) async {
    applied.add((user: user, member: member, family: family));
    final current = state.value ?? initial;
    state = AsyncData(
      current.copyWith(
        user: user == null ? null : () => user,
        member: member == null ? null : () => member,
        family: family == null ? null : () => family,
      ),
    );
  }
}

/// In-memory [FamilyRepository]. Each call is recorded in [calls]; set the
/// `*Error` fields to make a call fail, or [gate] to hold calls until it
/// completes.
class FakeFamilyRepository extends FamilyRepository {
  FakeFamilyRepository({List<Member>? members, Family? family})
    : members = [...?members],
      family = family ?? testFamily(),
      super(ApiClient(Dio()));

  List<Member> members;
  Family family;
  final List<String> calls = [];
  final List<Object?> bodies = [];

  Object? getMembersError;
  Object? getMemberError;
  Object? addError;
  Object? updateError;
  Object? deleteError;
  Object? familyError;
  Object? updateFamilyError;
  Object? regenerateError;

  /// Errors thrown by the next add calls, one per call (then [addError]).
  final List<Object> addErrors = [];

  /// Completes held calls (add / update / delete) when set.
  Completer<void>? gate;

  /// Body of the last call whose name starts with [prefix].
  Object? lastBody(String prefix) {
    for (var i = calls.length - 1; i >= 0; i--) {
      if (calls[i].startsWith(prefix)) return bodies[i];
    }
    return null;
  }

  Future<void> _record(String call, [Object? body]) async {
    calls.add(call);
    bodies.add(body);
    await Future<void>.delayed(Duration.zero);
    final g = gate;
    if (g != null) await g.future;
  }

  @override
  Future<List<Member>> getMembers() async {
    await _record('getMembers');
    final e = getMembersError;
    if (e != null) throw e;
    return List.unmodifiable(members);
  }

  @override
  Future<Member> getMember(String id) async {
    await _record('getMember $id');
    final e = getMemberError;
    if (e != null) throw e;
    for (final m in members) {
      if (m.id == id) return m;
    }
    throw const ApiException(code: ApiErrorCode.notFound, statusCode: 404);
  }

  @override
  Future<Member> addMember(NewMemberRequest request) async {
    await _record('addMember', request.toJson());
    if (addErrors.isNotEmpty) throw addErrors.removeAt(0);
    final e = addError;
    if (e != null) throw e;
    final json = request.toJson();
    final member = Member(
      id: 'm-new-${members.length}',
      familyId: familyId,
      name: request.name,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      dateOfBirth: request.dateOfBirth?.toUtc(),
      gender: request.gender,
      designation: json['designation'] as String?,
      role: request.role,
      guardianConsent: request.guardianConsent,
    );
    members = [...members, member];
    return member;
  }

  @override
  Future<Member> updateMember(String id, MemberPatch patch) async {
    await _record('updateMember $id', patch.toJson());
    final e = updateError;
    if (e != null) throw e;
    final index = members.indexWhere((m) => m.id == id);
    if (index < 0) {
      throw const ApiException(code: ApiErrorCode.notFound, statusCode: 404);
    }
    final merged = {...members[index].toJson(), ...patch.toJson()};
    final updated = Member.fromJson(merged);
    members = [...members]..[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteMember(String id) async {
    await _record('deleteMember $id');
    final e = deleteError;
    if (e != null) throw e;
    members = members.where((m) => m.id != id).toList();
  }

  @override
  Future<Family> getFamily() async {
    await _record('getFamily');
    final e = familyError;
    if (e != null) throw e;
    return family;
  }

  @override
  Future<Family> updateFamily(FamilyPatch patch) async {
    await _record('updateFamily', patch.toJson());
    final e = updateFamilyError;
    if (e != null) throw e;
    final json = {...family.toJson(), ...patch.toJson()};
    family = Family.fromJson(json);
    return family;
  }

  @override
  Future<Family> regenerateInviteCode() async {
    await _record('regenerateInviteCode');
    final e = regenerateError;
    if (e != null) throw e;
    family = family.copyWith(inviteCode: () => 'N3WCQDE7');
    return family;
  }
}

ApiException apiError(String code, [int status = 409]) =>
    ApiException(code: code, message: code, statusCode: status);

// ── Containers & widgets ────────────────────────────────────────────────────

Fmt testFmt() =>
    Fmt(locale: const Locale('en'), currency: 'INR', country: 'IN');

List<Override> familyOverrides({
  required FakeFamilyRepository repo,
  required FakeSession session,
}) => [
  familyRepositoryProvider.overrideWithValue(repo),
  sessionControllerProvider.overrideWith(() => session),
  fmtProvider.overrideWithValue(testFmt()),
];

/// A container with the fakes and the session restored.
Future<ProviderContainer> createFamilyContainer({
  required FakeFamilyRepository repo,
  required FakeSession session,
}) async {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: familyOverrides(repo: repo, session: session),
  );
  addTearDown(container.dispose);
  await container.read(sessionControllerProvider.future);
  return container;
}

/// Screens of other features the family screens link to; each renders
/// `route:<location>` so tests can assert navigation.
final List<RouteBase> _otherRoutes = [
  for (final path in [
    AppRoutes.home,
    AppRoutes.emergencyCardPath,
    AppRoutes.taskNewPath,
    AppRoutes.settingsLocation,
  ])
    GoRoute(
      path: path,
      builder: (context, state) => Scaffold(body: Text('route:${state.uri}')),
    ),
];

/// Pumps the real [familyRoutes] at [location] (on top of `/home`, so the
/// screen can pop) with the fakes. [asRoot] opens [location] directly with
/// nothing below it, like a deep link / notification tap.
Future<GoRouter> pumpFamilyApp(
  WidgetTester tester, {
  required String location,
  required FakeFamilyRepository repo,
  required FakeSession session,
  Widget Function(Widget child)? wrap,
  bool tall = true,
  bool asRoot = false,
  ThemeData? theme,
}) async {
  if (tall) {
    // A tall phone-width window so every section of the long screens is
    // built (lazy lists only build what is on screen).
    tester.view.physicalSize = const Size(1200, 7200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [...familyRoutes, ..._otherRoutes],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: familyOverrides(repo: repo, session: session),
      child: MaterialApp.router(
        routerConfig: router,
        theme: theme ?? AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: wrap == null ? null : (context, child) => wrap(child!),
      ),
    ),
  );
  // Restore the session first, like the real app does before any screen.
  final container = appContainer(tester);
  container.listen(sessionControllerProvider, (_, _) {});
  await container.read(sessionControllerProvider.future);
  await tester.pumpAndSettle();
  if (asRoot) {
    router.go(location);
  } else {
    unawaited(router.push(location));
  }
  await tester.pumpAndSettle();
  return router;
}

/// The app's provider container (to change data behind an open screen).
ProviderContainer appContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

/// Announces [scopes] as changed, like another screen's mutation would.
Future<void> markScopesChanged(
  WidgetTester tester,
  Set<DataScope> scopes,
) async {
  appContainer(tester).read(dataRefreshProvider.notifier).markChanged(scopes);
  await tester.pumpAndSettle();
}

/// English strings for assertions.
Future<AppLocalizations> englishL10n() =>
    AppLocalizations.delegate.load(const Locale('en'));
