import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/core/config/timezones.dart';
import 'package:family_hub/core/network/mock/mock_backend.dart';
import 'package:family_hub/core/utils/date_x.dart' show ageFrom;
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/features/family/domain/family_limits.dart';
import 'package:family_hub/shared/json.dart' show asMap, asString, calendarDate;

/// Registers the `/family` mock routes (docs/03-API_CONTRACT.md §6).
///
/// Emergency cards (`/family/members/:id/emergency-card`) are owned by the
/// `emergency_card` feature; everything else under `/family` lives here and
/// applies every contract rule: admin checks, the self-limited member patch,
/// `GUARDIAN_CONSENT_REQUIRED` by the family country's consent age,
/// `MEMBER_EMAIL_EXISTS`, `LAST_ADMIN` on demote / delete, the delete cascade
/// and "invite code only for admins". A malformed `:id` answers
/// `400 BAD_REQUEST` (contract §1), after the auth / family checks.
void registerFamilyMocks(MockBackend b) {
  // POST /family { name, country, currency, timezone } → 201 { user, family, member }
  b.on('POST', '/family', (req) {
    final user = req.requireUser();
    final fields = FamilyMockService.validateNewFamily(req.body);
    FamilyMockService.createFamilyFor(req.db, user, fields);
    return MockResponse.created(
      MockSerializers.session(req.db, _reload(req.db, user)),
    );
  });

  // POST /family/join { inviteCode } → { user, family, member }
  b.on('POST', '/family/join', (req) {
    final user = req.requireUser();
    FamilyMockService.joinFamilyFor(req.db, user, req.body['inviteCode']);
    return MockResponse.ok(
      MockSerializers.session(req.db, _reload(req.db, user)),
    );
  });

  // GET /family → { family }
  b.on('GET', '/family', (req) {
    final family = req.requireFamily();
    return MockResponse.ok({
      'family': MockSerializers.family(req.db, family, isAdmin: req.isAdmin),
    });
  });

  // PATCH /family (admin) { name?, country?, currency?, timezone? } → { family }
  b.on('PATCH', '/family', (req) {
    req.requireAdmin();
    final family = req.requireFamily();
    final input = _Input(req.body);
    final patch = <String, dynamic>{
      if (input.has('name'))
        'name': input.text(
          'name',
          min: 1,
          max: FamilyMockService.maxNameLength,
        ),
      if (input.has('country')) 'country': input.country('country'),
      if (input.has('currency')) 'currency': input.currency('currency'),
      if (input.has('timezone')) 'timezone': input.timezone('timezone'),
    };
    input.throwIfInvalid();
    final updated = patch.isEmpty
        ? family
        : req.db.update(MockDb.families, family['id'] as String, patch)!;
    return MockResponse.ok({
      'family': MockSerializers.family(req.db, updated, isAdmin: true),
    });
  });

  // POST /family/invite-code (admin) → { family } with a new code; the old
  // one stops working immediately.
  b.on('POST', '/family/invite-code', (req) {
    req.requireAdmin();
    final family = req.requireFamily();
    final updated = req.db.update(MockDb.families, family['id'] as String, {
      'inviteCode': FamilyMockService.newInviteCode(req.db),
    })!;
    return MockResponse.ok({
      'family': MockSerializers.family(req.db, updated, isAdmin: true),
    });
  });

  // GET /family/members → Member[] (admins first, oldest → youngest).
  b.on(
    'GET',
    '/family/members',
    (req) => MockResponse.ok(MockSerializers.members(req.db, req.familyId)),
  );

  // POST /family/members (admin) → 201 Member
  b.on('POST', '/family/members', (req) {
    final admin = req.requireAdmin();
    final family = req.requireFamily();
    final input = _Input(req.body);
    final name = input.text(
      'name',
      min: 1,
      max: FamilyMockService.maxNameLength,
      nullable: false,
    );
    final email = input.email('email');
    final phone = input.phone('phone');
    final dateOfBirth = input.date('dateOfBirth');
    final gender = input.oneOf('gender', FamilyMockService.genders);
    final designation = input.text(
      'designation',
      max: FamilyMockService.maxDesignationLength,
    );
    // Optional, defaults to `member`.
    final role = input.oneOf('role', FamilyMockService.roles) ?? 'member';
    final consent = input.boolean('guardianConsent') ?? false;
    input.throwIfInvalid();

    final familyId = family['id'] as String;
    FamilyMockService.requireUniqueEmail(req.db, familyId, email);
    FamilyMockService.requireGuardianConsent(
      family,
      dateOfBirth: dateOfBirth,
      guardianConsent: consent,
    );

    final now = req.db.nowIso();
    final member = req.db.insert(MockDb.members, {
      'familyId': familyId,
      'userId': null,
      'name': name,
      'email': email,
      'phone': phone,
      'avatarUrl': null,
      'dateOfBirth': dateOfBirth,
      'gender': gender,
      'designation': designation,
      'role': role,
      'locationSharing': 'never',
      'lastLocation': null,
      'guardianConsent': consent,
      'guardianConsentAt': consent ? now : null,
      'guardianConsentById': consent ? admin['id'] : null,
    });
    // The real backend emails an invitation with the family invite code
    // (in the family creator's locale) when an email is given; the mock
    // has no mailer.
    return MockResponse.created(MockSerializers.member(member));
  });

  // GET /family/members/:id → Member (other family → 404)
  b.on('GET', '/family/members/:id', (req) {
    req.requireMember();
    final id = _memberIdParam(req);
    return MockResponse.ok(
      MockSerializers.member(req.findInFamily(MockDb.members, id)),
    );
  });

  // PATCH /family/members/:id — admin: any member, every field incl. role;
  // non-admin: only themselves and only name, phone, avatarUrl, gender,
  // dateOfBirth (else 403 FORBIDDEN). Demoting the last admin → 409.
  b.on('PATCH', '/family/members/:id', (req) {
    final caller = req.requireMember();
    final target = req.findInFamily(MockDb.members, _memberIdParam(req));
    final isAdmin = caller['role'] == 'admin';
    final isSelf = caller['id'] == target['id'];
    if (!isAdmin) {
      final forbiddenKeys = req.body.keys.where(
        (k) => !FamilyMockService.selfPatchableFields.contains(k),
      );
      if (!isSelf || forbiddenKeys.isNotEmpty) {
        throw const MockException.forbidden();
      }
    }

    final input = _Input(req.body);
    final patch = <String, dynamic>{
      if (input.has('name'))
        'name': input.text(
          'name',
          min: 1,
          max: FamilyMockService.maxNameLength,
          nullable: false,
        ),
      if (input.has('phone')) 'phone': input.phone('phone'),
      if (input.has('avatarUrl')) 'avatarUrl': input.avatarUrl('avatarUrl'),
      if (input.has('gender'))
        'gender': input.oneOf('gender', FamilyMockService.genders),
      if (input.has('dateOfBirth')) 'dateOfBirth': input.date('dateOfBirth'),
      if (isAdmin) ...{
        if (input.has('email')) 'email': input.email('email'),
        if (input.has('designation'))
          'designation': input.text(
            'designation',
            max: FamilyMockService.maxDesignationLength,
          ),
        if (input.has('role'))
          'role': input.oneOf('role', FamilyMockService.roles, nullable: false),
        if (input.has('guardianConsent'))
          'guardianConsent': input.boolean('guardianConsent', nullable: false),
      },
    };
    input.throwIfInvalid();

    final familyId = target['familyId'] as String;
    final targetId = target['id'] as String;
    if (patch.containsKey('email')) {
      FamilyMockService.requireUniqueEmail(
        req.db,
        familyId,
        patch['email'] as String?,
        exceptMemberId: targetId,
      );
    }
    if (target['role'] == 'admin' && patch['role'] == 'member') {
      FamilyMockService.requireAnotherAdmin(req.db, familyId);
    }
    if (patch['guardianConsent'] == true && target['guardianConsent'] != true) {
      patch['guardianConsentAt'] = req.db.nowIso();
      patch['guardianConsentById'] = caller['id'];
    } else if (patch['guardianConsent'] == false) {
      patch['guardianConsentAt'] = null;
      patch['guardianConsentById'] = null;
    }

    final updated = patch.isEmpty
        ? target
        : req.db.update(MockDb.members, targetId, patch)!;
    // A member renaming themselves renames their account too (like PATCH /me).
    final userId = target['userId'];
    if (isSelf && userId is String && patch['name'] is String) {
      req.db.update(MockDb.users, userId, {'name': patch['name']});
    }
    return MockResponse.ok(MockSerializers.member(updated));
  });

  // DELETE /family/members/:id (admin) → null, with the contract cascade.
  b.on('DELETE', '/family/members/:id', (req) {
    req.requireMember();
    final id = _memberIdParam(req);
    final admin = req.requireAdmin();
    final target = req.findInFamily(MockDb.members, id);
    if (target['role'] == 'admin') {
      FamilyMockService.requireAnotherAdmin(req.db, target['familyId']);
    }
    FamilyMockService.removeMember(
      req.db,
      target,
      removedByMemberId: admin['id'] as String,
    );
    return const MockResponse.ok();
  });
}

Map<String, dynamic> _reload(MockDb db, Map<String, dynamic> user) =>
    db.findById(MockDb.users, user['id']) ?? user;

final _objectIdPattern = RegExp(r'^[0-9a-fA-F]{24}$');

/// The `:id` path parameter; `400 BAD_REQUEST` unless it is an ObjectId
/// (like the backend's id validation — an old or mistyped link).
String _memberIdParam(MockRequest req) {
  final id = req.param('id');
  if (!_objectIdPattern.hasMatch(id)) {
    throw const MockException.badRequest('Invalid id');
  }
  return id;
}

/// Family / member operations of the mock backend, shared with other mock
/// files (e.g. `POST /auth/register` in create / join mode) so every entry
/// point applies the same rules.
abstract final class FamilyMockService {
  static const maxNameLength = FamilyLimits.name;
  static const maxDesignationLength = FamilyLimits.designation;
  static const maxAvatarUrlLength = FamilyLimits.avatarUrl;
  static const genders = ['male', 'female', 'other'];
  static const roles = ['admin', 'member'];

  /// Designation of the member created together with a new family.
  static const founderDesignation = 'Head of Family';

  /// Fields a non-admin may change on their own member record.
  static const selfPatchableFields = {
    'name',
    'phone',
    'avatarUrl',
    'gender',
    'dateOfBirth',
  };

  /// Validates `{ name, country, currency, timezone }` of `POST /family`
  /// (or the `family` object of register, with [prefix] `family.`).
  /// Returns the normalised values or throws `422 VALIDATION_ERROR`.
  static Map<String, String> validateNewFamily(
    Object? body, {
    String prefix = '',
  }) {
    final input = _Input(
      body is Map ? asMap(body) : const <String, dynamic>{},
      prefix: prefix,
    );
    final name = input.text(
      'name',
      min: 1,
      max: maxNameLength,
      nullable: false,
    );
    final country = input.country('country', nullable: false);
    final currency = input.currency('currency', nullable: false);
    final timezone = input.timezone('timezone', nullable: false);
    input.throwIfInvalid();
    return {
      'name': name!,
      'country': country!,
      'currency': currency!,
      'timezone': timezone!,
    };
  }

  /// Creates a family owned by [user] plus its first admin member and links
  /// the user. `409 ALREADY_IN_FAMILY` when the user already has one.
  /// Returns the new member document.
  static Map<String, dynamic> createFamilyFor(
    MockDb db,
    Map<String, dynamic> user,
    Map<String, String> family, {
    String? dateOfBirth,
  }) {
    _requireNoFamily(user);
    final userId = user['id'] as String;
    final familyDoc = db.insert(MockDb.families, {
      ...family,
      'inviteCode': newInviteCode(db),
      'ownerId': userId,
    });
    final member = db.insert(MockDb.members, {
      'familyId': familyDoc['id'],
      'userId': userId,
      'name': user['name'],
      'email': user['email'],
      'phone': null,
      'avatarUrl': null,
      'dateOfBirth': dateOfBirth ?? user['dateOfBirth'],
      'gender': null,
      'designation': founderDesignation,
      'role': 'admin',
      'locationSharing': 'never',
      'lastLocation': null,
      'guardianConsent': false,
      'guardianConsentAt': null,
      'guardianConsentById': null,
    });
    db.update(MockDb.users, userId, {
      'familyId': familyDoc['id'],
      'memberId': member['id'],
    });
    return member;
  }

  /// Joins the family of [inviteCode] (case-insensitive, spaces / dashes
  /// ignored). Links a pre-added member with the user's email and no
  /// account, else creates a `member`. Errors: `422` (missing code),
  /// `400 INVALID_INVITE_CODE`, `409 ALREADY_IN_FAMILY`. Returns the member.
  static Map<String, dynamic> joinFamilyFor(
    MockDb db,
    Map<String, dynamic> user,
    Object? inviteCode, {
    String? dateOfBirth,
  }) {
    final raw = asString(inviteCode)?.trim() ?? '';
    if (raw.isEmpty) {
      throw const MockException.validation({'inviteCode': 'Required'});
    }
    _requireNoFamily(user);
    final code = Validators.normalizeInviteCode(raw);
    final family = db.findOne(MockDb.families, (f) => f['inviteCode'] == code);
    if (family == null) {
      throw const MockException(
        400,
        'INVALID_INVITE_CODE',
        'Invite code not found',
      );
    }
    final familyId = family['id'] as String;
    final userId = user['id'] as String;
    final email = asString(user['email'])?.trim().toLowerCase();

    Map<String, dynamic> member;
    final existing = email == null
        ? null
        : db.findOne(
            MockDb.members,
            (m) =>
                m['familyId'] == familyId &&
                asString(m['email'])?.toLowerCase() == email,
          );
    if (existing != null) {
      if (existing['userId'] != null) {
        throw const MockException.conflict('MEMBER_EMAIL_EXISTS');
      }
      member = db.update(MockDb.members, existing['id'] as String, {
        'userId': userId,
        if (existing['dateOfBirth'] == null && dateOfBirth != null)
          'dateOfBirth': dateOfBirth,
      })!;
    } else {
      member = db.insert(MockDb.members, {
        'familyId': familyId,
        'userId': userId,
        'name': user['name'],
        'email': email,
        'phone': null,
        'avatarUrl': null,
        'dateOfBirth': dateOfBirth ?? user['dateOfBirth'],
        'gender': null,
        'designation': null,
        'role': 'member',
        'locationSharing': 'never',
        'lastLocation': null,
        'guardianConsent': false,
        'guardianConsentAt': null,
        'guardianConsentById': null,
      });
    }
    db.update(MockDb.users, userId, {
      'familyId': familyId,
      'memberId': member['id'],
    });
    return member;
  }

  /// A new unique 8-char code from the invite alphabet (no 0/O/1/I).
  static String newInviteCode(MockDb db) {
    const alphabet = Validators.inviteAlphabet;
    while (true) {
      final buffer = StringBuffer();
      for (var i = 0; i < Validators.inviteCodeLength; i++) {
        buffer.write(alphabet[db.randomInt(alphabet.length)]);
      }
      final code = buffer.toString();
      if (!db.exists(MockDb.families, (f) => f['inviteCode'] == code)) {
        return code;
      }
    }
  }

  /// `409 MEMBER_EMAIL_EXISTS` when another member of [familyId] already
  /// uses [email] (case-insensitive).
  static void requireUniqueEmail(
    MockDb db,
    String familyId,
    String? email, {
    String? exceptMemberId,
  }) {
    if (email == null) return;
    final taken = db.exists(
      MockDb.members,
      (m) =>
          m['familyId'] == familyId &&
          m['id'] != exceptMemberId &&
          asString(m['email'])?.toLowerCase() == email.toLowerCase(),
    );
    if (taken) {
      throw const MockException.conflict(
        'MEMBER_EMAIL_EXISTS',
        'A member with this email already exists',
      );
    }
  }

  /// `422 GUARDIAN_CONSENT_REQUIRED` when [dateOfBirth] makes the person
  /// younger than the family country's consent age and [guardianConsent] is
  /// not `true`. Unknown ages need no consent (contract: "computed age").
  static void requireGuardianConsent(
    Map<String, dynamic> family, {
    required String? dateOfBirth,
    required bool guardianConsent,
  }) {
    if (guardianConsent) return;
    final age = ageOf(dateOfBirth);
    if (age == null) return;
    final consentAge = Countries.byCode(asString(family['country'])).consentAge;
    if (age < consentAge) {
      throw const MockException(
        422,
        'GUARDIAN_CONSENT_REQUIRED',
        'Guardian consent is required for this member',
      );
    }
  }

  /// Completed years on [now] for a date-only ISO value (calendar day, so
  /// the result does not depend on the device time zone).
  static int? ageOf(String? dateOfBirth, {DateTime? now}) =>
      ageFrom(calendarDate(MockDb.parse(dateOfBirth)), now: now);

  /// `409 LAST_ADMIN` unless [familyId] has at least two admins.
  static void requireAnotherAdmin(MockDb db, Object? familyId) {
    final admins = db.count(
      MockDb.members,
      (m) => m['familyId'] == familyId && m['role'] == 'admin',
    );
    if (admins <= 1) {
      throw const MockException.conflict(
        'LAST_ADMIN',
        'The family needs at least one admin',
      );
    }
  }

  /// Deletes [member] with the contract cascade: unlinks its user
  /// (`familyId` / `memberId` null, refresh tokens revoked, devices
  /// removed), deletes its **pending** tasks and its emergency card,
  /// resolves its active SOS alerts. Ledger entries stay and keep the
  /// member's name.
  static void removeMember(
    MockDb db,
    Map<String, dynamic> member, {
    required String removedByMemberId,
  }) {
    final memberId = member['id'] as String;
    final familyId = member['familyId'];
    final userId = member['userId'];
    final now = db.nowIso();

    if (userId is String) {
      db.update(MockDb.users, userId, {'familyId': null, 'memberId': null});
      MockTokens.revokeAll(db, userId);
      db.removeWhere(MockDb.devices, (d) => d['userId'] == userId);
    }
    db.removeWhere(
      MockDb.tasks,
      (t) =>
          t['familyId'] == familyId &&
          t['assigneeId'] == memberId &&
          t['status'] == 'pending',
    );
    db.removeWhere(MockDb.emergencyCards, (c) => c['memberId'] == memberId);
    db.updateWhere(
      MockDb.sosAlerts,
      (s) =>
          s['familyId'] == familyId &&
          s['memberId'] == memberId &&
          s['status'] == 'active',
      {
        'status': 'resolved',
        'resolvedAt': now,
        'resolvedById': removedByMemberId,
        // No outcome is known for a removed member (not "safe").
        'resolution': null,
      },
    );
    db.updateWhere(
      MockDb.ledgerEntries,
      (e) =>
          e['familyId'] == familyId &&
          e['memberId'] == memberId &&
          (asString(e['memberName']) ?? '').isEmpty,
      {'memberName': member['name']},
      timestamps: false,
    );
    db.remove(MockDb.members, memberId);
  }

  static void _requireNoFamily(Map<String, dynamic> user) {
    if (user['familyId'] != null) {
      throw const MockException.conflict(
        'ALREADY_IN_FAMILY',
        'You are already in a family',
      );
    }
  }
}

/// Reads and validates contract fields of a request body, collecting
/// field → message details for one `422 VALIDATION_ERROR` (like zod).
class _Input {
  _Input(this.body, {this.prefix = ''});

  final Map<String, dynamic> body;
  final String prefix;
  final Map<String, dynamic> errors = {};

  static final _email = RegExp(r'^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$');
  static final _phone = RegExp(r'^\+?\d{6,15}$');
  static final _phoneSeparators = RegExp(r'[\s\-().]');
  static final _currency = RegExp(r'^[A-Z]{3}$');
  static const _cloudinaryHost = 'res.cloudinary.com';

  bool has(String key) => body.containsKey(key);

  void _fail(String key, String message) => errors['$prefix$key'] = message;

  void throwIfInvalid() {
    if (errors.isNotEmpty) throw MockException.validation(errors);
  }

  /// Trimmed text; blank → `null` (an error when not [nullable] or
  /// [min] > 0).
  String? text(
    String key, {
    int min = 0,
    required int max,
    bool nullable = true,
  }) {
    final v = body[key];
    if (v == null) {
      if (!nullable) _fail(key, 'Required');
      return null;
    }
    if (v is! String) {
      _fail(key, 'Must be a string');
      return null;
    }
    final t = v.trim();
    if (t.isEmpty) {
      if (!nullable || min > 0) _fail(key, 'Required');
      return null;
    }
    if (t.length < min || t.length > max) {
      _fail(key, 'Must be $min-$max characters');
      return null;
    }
    return t;
  }

  /// Trimmed, lower-cased email or `null`.
  String? email(String key) {
    final t = text(key, max: 254);
    if (t == null) return null;
    if (!_email.hasMatch(t)) {
      _fail(key, 'Invalid email');
      return null;
    }
    return t.toLowerCase();
  }

  /// Phone without separators (`+919876543210`) or `null`.
  String? phone(String key) {
    final t = text(key, max: 32);
    if (t == null) return null;
    final cleaned = t.replaceAll(_phoneSeparators, '');
    if (!_phone.hasMatch(cleaned)) {
      _fail(key, 'Invalid phone number');
      return null;
    }
    return cleaned;
  }

  /// Date-only ISO value in the API format. Its calendar day (the app sends
  /// local midnight as UTC, so the instant may fall on the previous UTC day)
  /// must lie between 1 Jan 1900 and tomorrow (slack for time zones ahead).
  String? date(String key) {
    final v = body[key];
    if (v == null) return null;
    final parsed = v is String ? DateTime.tryParse(v.trim()) : null;
    final day = calendarDate(parsed);
    if (parsed == null || day == null) {
      _fail(key, 'Invalid date');
      return null;
    }
    final now = DateTime.now();
    final latest = DateTime(now.year, now.month, now.day + 1);
    if (day.isAfter(latest) || day.isBefore(DateTime(1900))) {
      _fail(key, 'Date out of range');
      return null;
    }
    return MockDb.iso(parsed);
  }

  String? oneOf(String key, List<String> allowed, {bool nullable = true}) {
    final v = body[key];
    if (v == null) {
      if (!nullable) _fail(key, 'Required');
      return null;
    }
    if (v is! String || !allowed.contains(v)) {
      _fail(key, 'Must be one of ${allowed.join(', ')}');
      return null;
    }
    return v;
  }

  bool? boolean(String key, {bool nullable = true}) {
    final v = body[key];
    if (v == null) {
      if (!nullable) _fail(key, 'Required');
      return null;
    }
    if (v is! bool) {
      _fail(key, 'Must be true or false');
      return null;
    }
    return v;
  }

  /// ISO 3166-1 alpha-2 code the app knows (upper-cased).
  String? country(String key, {bool nullable = false}) {
    final t = text(key, max: 2, nullable: nullable)?.toUpperCase();
    if (t == null) return null;
    if (!Countries.all.any((c) => c.code == t)) {
      _fail(key, 'Unknown country');
      return null;
    }
    return t;
  }

  /// ISO 4217 code offered by the app (upper-cased).
  String? currency(String key, {bool nullable = false}) {
    final t = text(key, max: 3, nullable: nullable)?.toUpperCase();
    if (t == null) return null;
    if (!_currency.hasMatch(t) || !Countries.currencies.contains(t)) {
      _fail(key, 'Unknown currency');
      return null;
    }
    return t;
  }

  /// IANA time zone the app offers.
  String? timezone(String key, {bool nullable = false}) {
    final t = text(key, max: 64, nullable: nullable);
    if (t == null) return null;
    if (!Timezones.isKnown(t)) {
      _fail(key, 'Unknown time zone');
      return null;
    }
    return t;
  }

  /// `null`, a Cloudinary `https` URL, or a local file path (mock-mode
  /// uploads without Cloudinary return the picked file's path).
  String? avatarUrl(String key) {
    final t = text(key, max: FamilyMockService.maxAvatarUrlLength);
    if (t == null) return null;
    final uri = Uri.tryParse(t);
    final isLocalPath = uri != null && (!uri.hasScheme || uri.isScheme('file'));
    final isCloudinary =
        uri != null && uri.isScheme('https') && uri.host == _cloudinaryHost;
    if (!isLocalPath && !isCloudinary) {
      _fail(key, 'Only Cloudinary image URLs are allowed');
      return null;
    }
    return t;
  }
}
