/// Every location of the app lives here — never hard-code a path in a feature.
///
/// Naming scheme (one rule for every route):
/// * **Static routes** (no path parameters, no query) are a single `const`
///   that is both the `GoRoute.path` and the location you navigate to:
///   `GoRoute(path: AppRoutes.login)` / `context.push(AppRoutes.login)`.
/// * **Parameterised routes** have a `…Path` pattern constant for the
///   `GoRoute.path` and a builder method with the base name for navigation:
///   `GoRoute(path: AppRoutes.taskDetailPath)` /
///   `context.push(AppRoutes.taskDetail(task.id))`.
/// * **Routes with optional query parameters** follow the same pattern:
///   `GoRoute(path: AppRoutes.taskNewPath)` /
///   `context.push(AppRoutes.taskNew(assigneeId: member.id))`.
///
/// Read parameters with the key constants, e.g.
/// `state.pathParameters[AppRoutes.idParam]` or
/// `state.uri.queryParameters[AppRoutes.assigneeIdQuery]`.
///
/// Full-screen feature routes are registered as **top-level** routes (they
/// cover the navigation bar). Inside one feature, list static segments before
/// parameter segments (e.g. `/tasks/new` before `/tasks/:id`).
abstract final class AppRoutes {
  // ---------------------------------------------------------------------------
  // Path-parameter and query keys
  // ---------------------------------------------------------------------------

  /// `:id` — task, goal, member, notice or SOS alert id.
  static const idParam = 'id';

  /// `:memberId` — emergency card owner.
  static const memberIdParam = 'memberId';

  /// `?mode=create|join` on [registerPath].
  static const modeQuery = 'mode';

  /// `?code=<inviteCode>` on [registerPath].
  static const codeQuery = 'code';

  /// `?assigneeId=<memberId>` on [taskNewPath].
  static const assigneeIdQuery = 'assigneeId';

  /// `?type=income|expense` on [ledgerEntryNewPath].
  static const typeQuery = 'type';

  /// Values of [modeQuery].
  static const registerModeCreate = 'create';
  static const registerModeJoin = 'join';

  // ---------------------------------------------------------------------------
  // Public / onboarding
  // ---------------------------------------------------------------------------

  static const splash = '/splash';
  static const welcome = '/welcome';
  static const login = '/login';
  static const registerPath = '/register';
  static const forgotPassword = '/forgot-password';
  static const verifyEmail = '/verify-email';
  static const familySetup = '/family-setup';

  /// `/register?mode=create|join&code=XXXX`. Use [registerModeCreate] /
  /// [registerModeJoin] for [mode].
  static String register({String? mode, String? code}) =>
      _withQuery(registerPath, {modeQuery: mode, codeQuery: code});

  // ---------------------------------------------------------------------------
  // Shell tabs (bottom navigation)
  // ---------------------------------------------------------------------------

  static const home = '/home';
  static const tasks = '/tasks';
  static const sos = '/sos';
  static const money = '/money';
  static const more = '/more';

  /// Tab roots in navigation-bar order.
  static const tabs = <String>[home, tasks, sos, money, more];

  // ---------------------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------------------

  static const taskNewPath = '/tasks/new';
  static const taskDetailPath = '/tasks/:$idParam';
  static const taskEditPath = '/tasks/:$idParam/edit';

  static String taskNew({String? assigneeId}) =>
      _withQuery(taskNewPath, {assigneeIdQuery: assigneeId});
  static String taskDetail(String id) => '/tasks/${_seg(id)}';
  static String taskEdit(String id) => '/tasks/${_seg(id)}/edit';

  // ---------------------------------------------------------------------------
  // Money (ledger + savings goals)
  // ---------------------------------------------------------------------------

  static const ledgerEntries = '/money/entries';
  static const ledgerEntryNewPath = '/money/entries/new';
  static const goalNew = '/money/goals/new';
  static const goalDetailPath = '/money/goals/:$idParam';
  static const goalEditPath = '/money/goals/:$idParam/edit';

  /// `/money/entries/new?type=income|expense` (pass `LedgerType.name`).
  static String ledgerEntryNew({String? type}) =>
      _withQuery(ledgerEntryNewPath, {typeQuery: type});
  static String goalDetail(String id) => '/money/goals/${_seg(id)}';
  static String goalEdit(String id) => '/money/goals/${_seg(id)}/edit';

  // ---------------------------------------------------------------------------
  // Family & members
  // ---------------------------------------------------------------------------

  static const members = '/members';
  static const memberNew = '/members/new';
  static const memberDetailPath = '/members/:$idParam';
  static const memberEditPath = '/members/:$idParam/edit';
  static const familySettings = '/family/settings';

  static String memberDetail(String id) => '/members/${_seg(id)}';
  static String memberEdit(String id) => '/members/${_seg(id)}/edit';

  // ---------------------------------------------------------------------------
  // Notices
  // ---------------------------------------------------------------------------

  static const notices = '/notices';
  static const noticeNew = '/notices/new';
  static const noticeEditPath = '/notices/:$idParam/edit';

  static String noticeEdit(String id) => '/notices/${_seg(id)}/edit';

  // ---------------------------------------------------------------------------
  // Emergency cards
  // ---------------------------------------------------------------------------

  static const emergencyCards = '/emergency-cards';
  static const emergencyCardPath = '/emergency-cards/:$memberIdParam';
  static const emergencyCardEditPath = '/emergency-cards/:$memberIdParam/edit';

  static String emergencyCard(String memberId) =>
      '/emergency-cards/${_seg(memberId)}';
  static String emergencyCardEdit(String memberId) =>
      '/emergency-cards/${_seg(memberId)}/edit';

  // ---------------------------------------------------------------------------
  // SOS
  // ---------------------------------------------------------------------------

  static const sosAlertPath = '/sos/alert/:$idParam';
  static const sosHistory = '/sos/history';

  static String sosAlert(String id) => '/sos/alert/${_seg(id)}';

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  static const settingsProfile = '/settings/profile';
  static const settingsLanguage = '/settings/language';
  static const settingsAppearance = '/settings/appearance';
  static const settingsLocation = '/settings/location';
  static const settingsPrivacy = '/settings/privacy';
  static const settingsPassword = '/settings/password';
  static const settingsAbout = '/settings/about';

  // ---------------------------------------------------------------------------
  // Route groups used by the redirect logic
  // ---------------------------------------------------------------------------

  /// Screens a signed-out user may see.
  static const signedOutPaths = <String>{
    welcome,
    login,
    registerPath,
    forgotPassword,
  };

  /// Screens of an incomplete session (signed in, but not verified / no family).
  static const onboardingPaths = <String>{verifyEmail, familySetup};

  /// Every route that is not part of the signed-in app.
  static const publicPaths = <String>{
    splash,
    ...signedOutPaths,
    ...onboardingPaths,
  };

  /// Whether [path] (a location path without query) is a public route.
  static bool isPublic(String path) => publicPaths.contains(_normalize(path));

  /// Whether [path] is one of the signed-out screens.
  static bool isSignedOutPath(String path) =>
      signedOutPaths.contains(_normalize(path));

  /// Whether [location] is the root of a bottom-navigation tab.
  static bool isTabRoot(String location) =>
      tabs.contains(_normalize(Uri.tryParse(location)?.path ?? location));

  /// Validates a location coming from outside the app's own code (push
  /// notification payloads, deep links). Returns a normalised in-app location
  /// (`/path?query`) or `null` when it is not a safe internal path.
  static String? sanitizeLocation(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    // Uri.parse silently resolves dot segments (`/a/../b` -> `/b`), so check
    // the raw path first.
    final rawPath = value.split(RegExp('[?#]')).first;
    if (rawPath.split('/').any((s) => s == '.' || s == '..')) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    // Absolute URLs, `//host` URLs and relative paths are rejected.
    if (uri.hasScheme || uri.hasAuthority) return null;
    if (!uri.path.startsWith('/') || uri.path.startsWith('//')) return null;
    final path = _normalize(uri.path);
    return uri.hasQuery ? '$path?${uri.query}' : path;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _seg(String value) => Uri.encodeComponent(value);

  /// Removes a trailing slash (except for the root `/`).
  static String _normalize(String path) {
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  static String _withQuery(String path, Map<String, String?> query) {
    final params = <String, String>{
      for (final e in query.entries)
        if (e.value != null && e.value!.trim().isNotEmpty)
          e.key: e.value!.trim(),
    };
    if (params.isEmpty) return path;
    return Uri(path: path, queryParameters: params).toString();
  }
}
