import 'package:family_hub/core/config/app_languages.dart';
import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/features/auth/domain/auth_rules.dart';
import 'package:family_hub/features/family/data/family_mock_handlers.dart'
    show FamilyMockService;

/// Rules of the `/auth` mock (docs/03-API_CONTRACT.md §4), shared with the
/// tests so they never drift from the implementation.
abstract final class AuthMockRules {
  /// Every OTP of the mock backend.
  static const otp = MockSeed.otp;

  /// Email verification / password reset codes are valid this long.
  static const otpValidity = OtpRules.validity;

  /// Wrong codes allowed per OTP (`INVALID_OTP`); any further try gets
  /// `OTP_EXPIRED`.
  static const otpMaxAttempts = OtpRules.maxAttempts;

  /// Minimum time between two codes of the same kind for one account.
  static const resendCooldown = OtpRules.resendCooldown;

  /// Extra resend wait per wrong guess on the current code (5 → 15 min).
  static const otpWrongGuessCooldown = OtpRules.wrongGuessCooldown;

  /// Longest `otp` input accepted before normalising (server: 64).
  static const otpInputMaxLength = 64;

  /// Failed logins per email within [lockoutWindow] that lock the email.
  static const maxFailedLogins = 5;

  /// Failures are counted within this window; the lock lasts as long.
  static const lockoutWindow = Duration(minutes: 15);

  static const nameMaxLength = 60;
  static const emailMaxLength = 254;
  static const passwordMinLength = 8;
  static const passwordMaxLength = 128;

  /// bcrypt limit of new passwords (see [AuthInputs.passwordMaxBytes]).
  static const passwordMaxBytes = AuthInputs.passwordMaxBytes;

  /// Dates of birth may be at most this far in the future (time zones).
  static const dateOfBirthFutureSlack = Duration(days: 1);
  static const oldestBirthYear = 1900;

  /// Designation of the member created for a new family's owner.
  static const ownerDesignation = FamilyMockService.founderDesignation;

  /// Mock-only collection with the failed-login counters (keyed by email, so
  /// unknown emails are locked exactly like real ones — no enumeration).
  static const loginAttempts = 'loginAttempts';

  /// `otps.purpose` values.
  static const purposeVerifyEmail = 'verify_email';
  static const purposeResetPassword = 'reset_password';
}

/// Every `/auth/*` mock route of docs/03-API_CONTRACT.md §4, with the same
/// decisions as the real server (docs/progress/b-auth.md, incl. its
/// hardening review):
///
/// * `register` — create / join through [FamilyMockService] (linking a
///   pre-added member with the same email and no account), `EMAIL_TAKEN`
///   (before any family check), `INVALID_INVITE_CODE`,
///   `MEMBER_EMAIL_EXISTS`, the self-registration age gate
///   (`GUARDIAN_CONSENT_REQUIRED` with `details.consentAge`; a pre-added
///   profile's date of birth and consent win); nothing is left behind when a
///   step fails;
/// * `login` — one generic `INVALID_CREDENTIALS`; 5 failures within 15 min
///   lock the email for 15 min, the 5th already answers `429`
///   (`retryAfterSeconds`); unknown emails lock the same way;
/// * `refresh` (rotation + reuse detection), `logout` (+ device token; a
///   late replay of the logged-out token is a plain `INVALID_REFRESH_TOKEN`,
///   never reuse detection — the server deletes the token);
/// * `verify-email` / `resend-verification` — OTP [AuthMockRules.otp],
///   10 min, 5 × `INVALID_OTP` then `OTP_EXPIRED`; one live code per email
///   and purpose; resend cooldown `max(60 s, wrong guesses × 3 min)`;
/// * `forgot-password` (always `sent`, decoys for unknown emails, nothing
///   re-sent inside the cooldown), `reset-password` (ends every session,
///   marks the email verified), `change-password` (shares the lockout,
///   returns fresh `tokens`), `me`;
/// * input rules: names without control / bidi-override characters and
///   with a visible character, new passwords ≤ 72 UTF-8 bytes, native
///   digits in codes, ISO dates with an offset (calendar-checked).
///
/// Not mirrored (no Dart equivalent needed for a demo backend): NFC / NFKC
/// normalisation of names and passwords, and ending the tokens *rotated
/// from* a logged-out refresh token.
///
/// [clock] lets tests move time forward (OTP expiry, lockout end).
void registerAuthMocks(MockBackend b, {DateTime Function()? clock}) {
  final auth = _AuthMock(clock ?? DateTime.now);
  b
    ..on('POST', '/auth/register', auth.register)
    ..on('POST', '/auth/login', auth.login)
    ..on('POST', '/auth/refresh', auth.refresh)
    ..on('POST', '/auth/logout', auth.logout)
    ..on('POST', '/auth/verify-email', auth.verifyEmail)
    ..on('POST', '/auth/resend-verification', auth.resendVerification)
    ..on('POST', '/auth/forgot-password', auth.forgotPassword)
    ..on('POST', '/auth/reset-password', auth.resetPassword)
    ..on('POST', '/auth/change-password', auth.changePassword)
    ..on('GET', '/auth/me', auth.me);
}

class _AuthMock {
  _AuthMock(this._now);

  final DateTime Function() _now;

  DateTime get now => _now();
  String get nowIso => MockDb.iso(now);

  // ── POST /auth/register ──────────────────────────────────────────────────

  MockResponse register(MockRequest req) {
    final db = req.db;
    final body = req.body;
    final errors = <String, String>{};

    final (name, nameError) = _displayName(body['name']);
    if (nameError != null) errors['name'] = nameError;
    final email = _email(body['email']);
    if (email == null) errors['email'] = 'Invalid email';
    final passwordError = _newPasswordError(body['password']);
    if (passwordError != null) errors['password'] = passwordError;
    final locale = _locale(body['locale']);
    if (locale == null) errors['locale'] = 'Unsupported language';
    if (body['consentAccepted'] != true) {
      errors['consentAccepted'] =
          'You must accept the privacy policy and the terms';
    }
    final dob = _dateOfBirth(body['dateOfBirth']);
    if (dob == _invalid) errors['dateOfBirth'] = 'Invalid date of birth';
    final String? dateOfBirth = dob is String ? dob : null;

    final mode = body['mode'];
    Map<String, String>? familyInput;
    String? inviteCode;
    if (mode == 'create') {
      // Same rules as `POST /family`, reported under `family.<field>`.
      try {
        familyInput = FamilyMockService.validateNewFamily(
          body['family'],
          prefix: 'family.',
        );
      } on MockException catch (e) {
        if (e.code != 'VALIDATION_ERROR') rethrow;
        errors.addAll({
          for (final entry in (e.details ?? const {}).entries)
            entry.key: '${entry.value}',
        });
      }
      // The server's `displayName` rules also apply to the family name.
      final familyNameError = familyInput == null
          ? null
          : _displayName(familyInput['name']).$2;
      if (familyNameError != null) errors['family.name'] = familyNameError;
    } else if (mode == 'join') {
      inviteCode = _inviteCode(body['inviteCode']);
      if (inviteCode == null) errors['inviteCode'] = 'Invalid invite code';
    } else {
      errors['mode'] = 'Mode must be create or join';
    }
    if (errors.isNotEmpty) throw MockException.validation(errors);

    // "Log in instead" wins over any family check (like the server).
    if (db.exists(MockDb.users, (u) => u['email'] == email)) {
      throw const MockException.conflict(
        'EMAIL_TAKEN',
        'An account with this email already exists',
      );
    }

    // Checks that need no writes first (like the server's `planJoin`).
    if (familyInput != null) {
      _requireAgeOfConsent(dateOfBirth, familyInput['country']!);
    } else {
      final family = db.findOne(
        MockDb.families,
        (f) => '${f['inviteCode']}'.toUpperCase() == inviteCode,
      );
      if (family == null) {
        throw const MockException(
          400,
          'INVALID_INVITE_CODE',
          'Invalid invite code',
        );
      }
      // A profile an admin pre-added with this email: linked by the join.
      final profile = db.findOne(
        MockDb.members,
        (m) =>
            m['familyId'] == family['id'] &&
            '${m['email'] ?? ''}'.trim().toLowerCase() == email,
      );
      if (profile != null && profile['userId'] != null) {
        throw const MockException.conflict(
          'MEMBER_EMAIL_EXISTS',
          'A member with this email already exists',
        );
      }
      // The profile's date of birth and guardian consent win.
      final profileDob = profile?['dateOfBirth'];
      _requireAgeOfConsent(
        profileDob is String ? profileDob : dateOfBirth,
        '${family['country']}',
        consentOnFile: profile?['guardianConsent'] == true,
      );
    }

    final userId = db.newId();
    db.insert(MockDb.users, {
      'id': userId,
      'email': email,
      // Plain text on purpose: in-memory demo backend.
      'password': body['password'],
      'name': name,
      'locale': locale,
      'emailVerified': false,
      'familyId': null,
      'memberId': null,
      'consentAcceptedAt': nowIso,
      'lastLoginAt': null,
    });
    final Map<String, dynamic> member;
    try {
      final user = db.findById(MockDb.users, userId)!;
      member = familyInput != null
          ? FamilyMockService.createFamilyFor(
              db,
              user,
              familyInput,
              dateOfBirth: dateOfBirth,
            )
          : FamilyMockService.joinFamilyFor(
              db,
              user,
              inviteCode,
              dateOfBirth: dateOfBirth,
            );
    } catch (_) {
      db.remove(MockDb.users, userId); // no half-created accounts
      rethrow;
    }

    final user = db.findById(MockDb.users, userId)!;
    final family = db.findById(MockDb.families, member['familyId'])!;
    // The first code is sent without a cooldown check (like the server).
    _issueOtp(
      db,
      email: email!,
      userId: userId,
      purpose: AuthMockRules.purposeVerifyEmail,
      cooldown: false,
    );
    return MockResponse.created({
      'user': MockSerializers.user(db, user),
      'tokens': MockTokens.issue(db, userId),
      'family': MockSerializers.family(
        db,
        family,
        isAdmin: member['role'] == 'admin',
      ),
      'member': MockSerializers.member(member),
    });
  }

  /// Self-registration age gate (docs/08-COMPLIANCE.md GAP-01): somebody
  /// younger than the country's consent age cannot sign up alone — unless
  /// they link to a profile an admin added with guardian consent.
  void _requireAgeOfConsent(
    String? dateOfBirth,
    String country, {
    bool consentOnFile = false,
  }) {
    if (consentOnFile) return;
    final age = FamilyMockService.ageOf(dateOfBirth, now: now);
    final consentAge = Countries.byCode(country).consentAge;
    if (age != null && age < consentAge) {
      throw MockException(
        422,
        'GUARDIAN_CONSENT_REQUIRED',
        'A parent or guardian must add you to the family first',
        {
          'dateOfBirth': 'Below the consent age ($consentAge) for this country',
          'consentAge': consentAge,
        },
      );
    }
  }

  // ── POST /auth/login ─────────────────────────────────────────────────────

  MockResponse login(MockRequest req) {
    final db = req.db;
    final email = _email(req.body['email']);
    final password = req.body['password'];
    final details = <String, dynamic>{
      if (email == null) 'email': 'Invalid email',
      'password': ?_currentPasswordError(password),
    };
    if (details.isNotEmpty) throw MockException.validation(details);

    final lockedFor = _lockedSeconds(db, email!);
    if (lockedFor > 0) throw MockException.tooManyRequests(lockedFor);

    final user = db.findOne(MockDb.users, (u) => u['email'] == email);
    // Never reveal whether the email or the password was wrong.
    if (user == null || user['password'] != password) {
      final lock = _recordFailedLogin(db, email);
      if (lock > 0) throw MockException.tooManyRequests(lock);
      throw const MockException.unauthorized(
        'INVALID_CREDENTIALS',
        'Invalid email or password',
      );
    }
    _clearFailedLogins(db, email);
    final userId = user['id'] as String;
    final updated = db.update(MockDb.users, userId, {'lastLoginAt': nowIso})!;
    return MockResponse.ok({
      'user': MockSerializers.user(db, updated),
      'tokens': MockTokens.issue(db, userId),
    });
  }

  // ── POST /auth/refresh · /auth/logout ────────────────────────────────────

  /// Rotation + reuse detection live in [MockTokens]. A token ended by
  /// logout is refused plainly, without reuse detection: the server deletes
  /// it, so a refresh that was still in flight when the user logged out
  /// must not sign them out on every other device.
  MockResponse refresh(MockRequest req) {
    final token = req.body['refreshToken'];
    final loggedOut =
        token is String &&
        req.db.exists(
          MockDb.refreshTokens,
          (t) => t['token'] == token && t[_loggedOutAt] != null,
        );
    if (loggedOut) {
      throw const MockException.unauthorized(
        'INVALID_REFRESH_TOKEN',
        'Invalid refresh token',
      );
    }
    return MockResponse.ok({'tokens': MockTokens.rotate(req.db, token)});
  }

  /// Marks a refresh token ended by logout (see [refresh]). The row stays
  /// (revoked) so the core mock's bookkeeping keeps working.
  static const _loggedOutAt = 'loggedOutAt';

  MockResponse logout(MockRequest req) {
    final user = req.requireUser();
    final userId = user['id'];
    final token = req.body['refreshToken'];
    if (token is! String || token.trim().isEmpty) {
      throw const MockException.validation({
        'refreshToken': 'Refresh token is required',
      });
    }
    // A caller may only end their own session.
    final mine = token.trim();
    for (final row in req.db.where(
      MockDb.refreshTokens,
      (t) => t['token'] == mine && t['userId'] == userId,
    )) {
      req.db.update(MockDb.refreshTokens, row['id'] as String, {
        'revokedAt': row['revokedAt'] ?? nowIso,
        _loggedOutAt: nowIso,
      });
    }
    final deviceToken = req.body['deviceToken'];
    if (deviceToken is String && deviceToken.isNotEmpty) {
      req.db.removeWhere(
        MockDb.devices,
        (d) => d['token'] == deviceToken && d['userId'] == userId,
      );
    }
    return const MockResponse.ok();
  }

  // ── Email verification ───────────────────────────────────────────────────

  MockResponse verifyEmail(MockRequest req) {
    final db = req.db;
    final user = req.requireUser();
    // The body is validated first, like the server's schema.
    final otp = _otp(req.body['otp']);
    if (otp == null) {
      throw const MockException.validation({'otp': 'Code must be 6 digits'});
    }
    // Idempotent: an already verified account just gets its user back.
    if (user['emailVerified'] == true) {
      return MockResponse.ok({'user': MockSerializers.user(db, user)});
    }
    _consumeOtp(
      db,
      email: '${user['email']}',
      purpose: AuthMockRules.purposeVerifyEmail,
      code: otp,
    );
    final updated = db.update(MockDb.users, user['id'] as String, {
      'emailVerified': true,
      'emailVerifiedAt': nowIso,
    })!;
    return MockResponse.ok({'user': MockSerializers.user(db, updated)});
  }

  MockResponse resendVerification(MockRequest req) {
    final db = req.db;
    final user = req.requireUser();
    if (user['emailVerified'] == true) {
      return const MockResponse.ok({'sent': false, 'retryAfterSeconds': 0});
    }
    // Inside the cooldown → 429 with the remaining wait.
    _issueOtp(
      db,
      email: '${user['email']}',
      userId: user['id'] as String,
      purpose: AuthMockRules.purposeVerifyEmail,
    );
    return MockResponse.ok({
      'sent': true,
      'retryAfterSeconds': AuthMockRules.resendCooldown.inSeconds,
    });
  }

  // ── Passwords ────────────────────────────────────────────────────────────

  /// Always `{ sent: true }`. Unknown emails get a decoy code that is never
  /// sent, so reset-password answers exactly like for a real account (no
  /// enumeration). Within the cooldown nothing is re-sent.
  MockResponse forgotPassword(MockRequest req) {
    final db = req.db;
    final email = _email(req.body['email']);
    if (email == null) {
      throw const MockException.validation({'email': 'Invalid email'});
    }
    final user = db.findOne(MockDb.users, (u) => u['email'] == email);
    try {
      _issueOtp(
        db,
        email: email,
        userId: user?['id'] as String?,
        purpose: AuthMockRules.purposeResetPassword,
      );
    } on MockException catch (e) {
      if (e.status != 429) rethrow; // cooling down: nothing new is sent
    }
    return const MockResponse.ok({'sent': true});
  }

  MockResponse resetPassword(MockRequest req) {
    final db = req.db;
    final body = req.body;
    final errors = <String, String>{};
    final email = _email(body['email']);
    if (email == null) errors['email'] = 'Invalid email';
    final otp = _otp(body['otp']);
    if (otp == null) errors['otp'] = 'Code must be 6 digits';
    final passwordError = _newPasswordError(body['newPassword']);
    if (passwordError != null) errors['newPassword'] = passwordError;
    if (errors.isNotEmpty) throw MockException.validation(errors);

    final row = _consumeOtp(
      db,
      email: email!,
      purpose: AuthMockRules.purposeResetPassword,
      code: otp!,
    );
    final user = db.findOne(MockDb.users, (u) => u['email'] == email);
    // A decoy (unknown email when requested) or a code of a deleted account.
    if (user == null || row['userId'] == null || row['userId'] != user['id']) {
      throw _invalidOtp;
    }

    final userId = user['id'] as String;
    db.update(MockDb.users, userId, {
      'password': body['newPassword'],
      // The code arrived by email, which proves the address is theirs.
      'emailVerified': true,
      'passwordChangedAt': nowIso,
    });
    _endAllSessions(db, userId);
    _clearFailedLogins(db, email);
    _discardOtp(db, email, AuthMockRules.purposeVerifyEmail);
    return const MockResponse.ok({'reset': true});
  }

  /// Like the server: a wrong current password counts towards the login
  /// lockout; success ends every session and returns a fresh token pair for
  /// the calling device (`{ changed: true, tokens }`, a superset of the
  /// contract).
  MockResponse changePassword(MockRequest req) {
    final db = req.db;
    final user = req.requireUser();
    final current = req.body['currentPassword'];
    final next = req.body['newPassword'];
    final errors = <String, String>{
      'currentPassword': ?_currentPasswordError(current),
      'newPassword': ?_newPasswordError(next),
    };
    if (errors.isEmpty && current == next) {
      errors['newPassword'] =
          'The new password must be different from the current one';
    }
    if (errors.isNotEmpty) throw MockException.validation(errors);

    final email = '${user['email']}';
    final lockedFor = _lockedSeconds(db, email);
    if (lockedFor > 0) throw MockException.tooManyRequests(lockedFor);
    if (user['password'] != current) {
      final lock = _recordFailedLogin(db, email);
      if (lock > 0) throw MockException.tooManyRequests(lock);
      throw const MockException.unauthorized(
        'INVALID_CREDENTIALS',
        'Current password is incorrect',
      );
    }
    final userId = user['id'] as String;
    db.update(MockDb.users, userId, {
      'password': next,
      'passwordChangedAt': nowIso,
    });
    _clearFailedLogins(db, email);
    _endAllSessions(db, userId);
    return MockResponse.ok({
      'changed': true,
      'tokens': MockTokens.issue(db, userId),
    });
  }

  /// Ends every session of [userId] by deleting its refresh tokens (like
  /// the server). Flagging them revoked would make a stale device's next
  /// refresh look like token reuse, which revokes the fresh session too.
  static void _endAllSessions(MockDb db, String userId) =>
      db.removeWhere(MockDb.refreshTokens, (t) => t['userId'] == userId);

  // ── GET /auth/me ─────────────────────────────────────────────────────────

  MockResponse me(MockRequest req) =>
      MockResponse.ok(MockSerializers.session(req.db, req.requireUser()));

  // ── One-time codes ───────────────────────────────────────────────────────
  // Like the server: one live code per email + purpose (a new code replaces
  // it and resets its attempts), deleted once used. `userId` is null for
  // password-reset decoys of unknown emails.

  static const _otpExpired = MockException(
    400,
    'OTP_EXPIRED',
    'Code expired, request a new one',
  );

  static const _invalidOtp = MockException(400, 'INVALID_OTP', 'Invalid code');

  Map<String, dynamic>? _otpRow(MockDb db, String email, String purpose) =>
      db.findOne(
        MockDb.otps,
        (o) => o['email'] == email && o['purpose'] == purpose,
      );

  /// "Sends" a new code ([AuthMockRules.otp]; a random never-sent code for
  /// decoys), replacing the live one. With [cooldown] a code sent too
  /// recently gives `429 TOO_MANY_REQUESTS` (`retryAfterSeconds`).
  void _issueOtp(
    MockDb db, {
    required String email,
    required String? userId,
    required String purpose,
    bool cooldown = true,
  }) {
    final row = _otpRow(db, email, purpose);
    if (cooldown) {
      final wait = _resendWaitSeconds(row);
      if (wait > 0) throw MockException.tooManyRequests(wait);
    }
    final fields = <String, dynamic>{
      'userId': userId,
      'email': email,
      'purpose': purpose,
      'code': userId == null ? _decoyCode(db) : AuthMockRules.otp,
      'attempts': 0,
      'sentAt': nowIso,
      'expiresAt': MockDb.iso(now.add(AuthMockRules.otpValidity)),
    };
    if (row == null) {
      db.insert(MockDb.otps, fields);
    } else {
      db.update(MockDb.otps, row['id'] as String, fields);
    }
  }

  static String _decoyCode(MockDb db) {
    while (true) {
      final code = db.randomInt(1000000).toString().padLeft(6, '0');
      if (code != AuthMockRules.otp) return code;
    }
  }

  /// Checks [code] against the live code of [email] / [purpose]; every check
  /// counts. A wrong code is `INVALID_OTP`; after
  /// [AuthMockRules.otpMaxAttempts] of them — or when it expired or was
  /// never requested — the answer is `OTP_EXPIRED`. The right code is
  /// consumed (single use) and its row returned.
  Map<String, dynamic> _consumeOtp(
    MockDb db, {
    required String email,
    required String purpose,
    required String code,
  }) {
    final row = _otpRow(db, email, purpose);
    if (row == null) throw _otpExpired;
    final id = row['id'] as String;
    final expiresAt = MockDb.parse(row['expiresAt']);
    final attempts = _attemptsOf(row);
    if (expiresAt == null ||
        !expiresAt.isAfter(now) ||
        attempts >= AuthMockRules.otpMaxAttempts) {
      throw _otpExpired;
    }
    if (row['code'] != code) {
      db.update(MockDb.otps, id, {'attempts': attempts + 1});
      throw _invalidOtp;
    }
    db.remove(MockDb.otps, id);
    return row;
  }

  void _discardOtp(MockDb db, String email, String purpose) => db.removeWhere(
    MockDb.otps,
    (o) => o['email'] == email && o['purpose'] == purpose,
  );

  static int _attemptsOf(Map<String, dynamic>? row) {
    final attempts = row?['attempts'];
    return attempts is int && attempts > 0 ? attempts : 0;
  }

  /// Seconds until another code may be sent for [row]:
  /// [OtpRules.resendCooldownAfter] its wrong guesses, from when it was
  /// sent (0 without a live code).
  int _resendWaitSeconds(Map<String, dynamic>? row) {
    final sent = MockDb.parse(row?['sentAt']);
    if (sent == null) return 0;
    final cooldown = OtpRules.resendCooldownAfter(_attemptsOf(row));
    return _secondsUntil(sent.add(cooldown));
  }

  // ── Login lockout ────────────────────────────────────────────────────────

  Map<String, dynamic>? _attempts(MockDb db, String email) =>
      db.findOne(AuthMockRules.loginAttempts, (a) => a['email'] == email);

  /// Remaining lock of [email] in seconds (0 = not locked).
  int _lockedSeconds(MockDb db, String email) {
    final until = MockDb.parse(_attempts(db, email)?['lockedUntil']);
    return until == null ? 0 : _secondsUntil(until);
  }

  /// Counts a failed login; returns the lock in seconds when this failure
  /// reached the limit, else 0.
  int _recordFailedLogin(MockDb db, String email) {
    final doc = _attempts(db, email);
    final windowStart = MockDb.parse(doc?['windowStartedAt']);
    final inWindow =
        windowStart != null &&
        now.difference(windowStart) < AuthMockRules.lockoutWindow;
    final count = (inWindow && doc?['count'] is int ? doc!['count'] as int : 0);
    final failures = count + 1;
    final locked = failures >= AuthMockRules.maxFailedLogins;
    final patch = <String, dynamic>{
      'email': email,
      'count': locked ? 0 : failures,
      'windowStartedAt': inWindow && !locked ? doc!['windowStartedAt'] : nowIso,
      'lockedUntil': locked
          ? MockDb.iso(now.add(AuthMockRules.lockoutWindow))
          : null,
    };
    if (doc == null) {
      db.insert(AuthMockRules.loginAttempts, patch);
    } else {
      db.update(AuthMockRules.loginAttempts, doc['id'] as String, patch);
    }
    return locked ? AuthMockRules.lockoutWindow.inSeconds : 0;
  }

  void _clearFailedLogins(MockDb db, String email) =>
      db.removeWhere(AuthMockRules.loginAttempts, (a) => a['email'] == email);

  int _secondsUntil(DateTime moment) {
    final ms = moment.difference(now).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  // ── Validation helpers ───────────────────────────────────────────────────

  /// Marker for a present but malformed optional value.
  static const _invalid = Object();

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Trimmed, lower-cased email (contract §4), or null when not an email.
  static String? _email(Object? value) {
    if (value is! String) return null;
    final email = value.trim().toLowerCase();
    return email.length <= AuthMockRules.emailMaxLength &&
            _emailPattern.hasMatch(email)
        ? email
        : null;
  }

  /// The server's `displayName` (person and family names): trimmed,
  /// 1–60 characters, no control / bidi-override characters, at least one
  /// visible letter, digit or symbol. Returns the value or the error.
  static (String?, String?) _displayName(Object? value) {
    if (value is! String) return (null, 'Name is required');
    final name = value.trim();
    if (name.isEmpty || name.length > AuthMockRules.nameMaxLength) {
      return (null, 'Name must be 1-60 characters');
    }
    if (AuthInputs.hasForbiddenNameChars(name)) {
      return (null, 'Name contains characters that are not allowed');
    }
    if (AuthInputs.looksBlank(name)) {
      return (null, 'Name must contain a letter or digit');
    }
    return (name, null);
  }

  static final _letter = RegExp(r'\p{L}', unicode: true);
  static final _digit = RegExp(r'\d');

  /// Rules of a new password (register, reset, change).
  static String? _newPasswordError(Object? value) {
    if (value is! String || value.length < AuthMockRules.passwordMinLength) {
      return 'Password must be at least 8 characters';
    }
    if (value.length > AuthMockRules.passwordMaxLength ||
        AuthInputs.passwordTooLong(value)) {
      return 'Password is too long';
    }
    if (!_letter.hasMatch(value) || !_digit.hasMatch(value)) {
      return 'Password must contain a letter and a digit';
    }
    return null;
  }

  /// A password typed to sign in / confirm: only bounded, never re-checked
  /// against the rules (older accounts may predate them).
  static String? _currentPasswordError(Object? value) {
    if (value is! String || value.isEmpty) return 'Password is required';
    if (value.length > AuthMockRules.passwordMaxLength) {
      return 'Password is too long';
    }
    return null;
  }

  /// Supported language code; absent → `en`; unsupported → null.
  static String? _locale(Object? value) {
    if (value == null) return 'en';
    if (value is! String) return null;
    return AppLanguages.byCode(value.trim().toLowerCase())?.code;
  }

  /// `YYYY-MM-DD`, or an ISO date-time **with** `Z` / an offset.
  static final _isoDate = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})'
    r'(?:T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,9})?)?(?:Z|[+-]\d{2}:\d{2}))?$',
  );

  /// `null` when absent, the ISO string when valid, [_invalid] otherwise:
  /// calendar-checked (no 2010-02-31), from 1900, at most a day ahead.
  Object? _dateOfBirth(Object? value) {
    if (value == null) return null;
    final match = value is String ? _isoDate.firstMatch(value.trim()) : null;
    if (match == null) return _invalid;
    final y = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    final d = int.parse(match.group(3)!);
    final day = DateTime.utc(y, m, d);
    if (day.year != y || day.month != m || day.day != d) return _invalid;
    final date = DateTime.tryParse((value as String).trim());
    if (date == null ||
        date.toUtc().year < AuthMockRules.oldestBirthYear ||
        date.isAfter(now.add(AuthMockRules.dateOfBirthFutureSlack))) {
      return _invalid;
    }
    return MockDb.iso(date);
  }

  static final _codeSeparators = RegExp(r'[\s\-]');

  /// 6 digits; spaces and dashes are ignored and native digits accepted
  /// (like the server).
  static String? _otp(Object? value) {
    if (value is! String || value.length > AuthMockRules.otpInputMaxLength) {
      return null;
    }
    final code = Validators.normalizeDigits(
      value,
    ).replaceAll(_codeSeparators, '');
    return RegExp(r'^\d{6}$').hasMatch(code) ? code : null;
  }

  /// Upper-cased invite code without spaces / dashes (native digits
  /// accepted), or null.
  static String? _inviteCode(Object? value) {
    if (value is! String) return null;
    final code = Validators.normalizeDigits(
      value,
    ).replaceAll(_codeSeparators, '').toUpperCase();
    return RegExp(r'^[A-Z0-9]{8}$').hasMatch(code) ? code : null;
  }
}
