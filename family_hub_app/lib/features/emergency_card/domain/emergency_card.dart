import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:family_hub/shared/json.dart';

/// Limits of an emergency card (docs/03-API_CONTRACT.md §6 "EmergencyCard";
/// the text backstops match `family_hub_backend/src/models/enums.js`).
abstract final class EmergencyCardLimits {
  /// Max entries of `allergies`, `medications` and `conditions`.
  static const listMaxItems = 20;

  /// Max characters of one allergy / medication / condition.
  static const listItemMaxLength = 80;

  /// Max `emergencyContacts`.
  static const contactsMax = 5;

  /// Max characters of `notes`.
  static const notesMaxLength = 500;

  /// Max characters of `doctorName`, `insuranceProvider`,
  /// `insurancePolicyNumber` and a contact's `name`.
  static const textMaxLength = 100;

  /// Max characters of a contact's `relation`.
  static const relationMaxLength = 60;

  /// Max characters typed into a phone field (the server accepts `+` and
  /// 6–15 digits once separators are removed).
  static const phoneMaxLength = 32;
}

/// ABO/Rh blood group. Wire values: `A+ A- B+ B- AB+ AB- O+ O- unknown`.
enum BloodGroup {
  aPositive('A+'),
  aNegative('A-'),
  bPositive('B+'),
  bNegative('B-'),
  abPositive('AB+'),
  abNegative('AB-'),
  oPositive('O+'),
  oNegative('O-'),
  unknown('unknown');

  const BloodGroup(this.wireName);

  /// Value sent to / received from the API (also the universal symbol shown
  /// in the UI for known groups, e.g. `AB+`).
  final String wireName;

  /// Whether the group has been recorded.
  bool get isKnown => this != unknown;

  /// Every recorded group in the usual display order (without [unknown]).
  static const known = <BloodGroup>[
    aPositive,
    aNegative,
    bPositive,
    bNegative,
    abPositive,
    abNegative,
    oPositive,
    oNegative,
  ];

  /// Lenient parser: accepts the wire value in any case and with spaces,
  /// typographic minus signs (`A−`, `A–`), `ve` suffixes (`B+ve`) and the
  /// Dart enum name (`abNegative`). Anything else → [unknown].
  static BloodGroup fromWire(Object? value) {
    if (value is BloodGroup) return value;
    final raw = asString(value);
    if (raw == null) return unknown;
    final byName = enumByNameOrNull(values, raw);
    if (byName != null) return byName;
    final normalized = raw
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp('[−–—]'), '-')
        .replaceAll(RegExp(r'VE$'), '');
    for (final group in known) {
      if (group.wireName == normalized) return group;
    }
    return unknown;
  }
}

/// A person to call in an emergency (`{ name, phone, relation }`).
@immutable
class EmergencyContact {
  const EmergencyContact({required this.name, this.phone, this.relation});

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        name: asStringOr(json['name'], '').trim(),
        phone: asNonEmptyString(json['phone'])?.trim(),
        relation: asNonEmptyString(json['relation'])?.trim(),
      );

  final String name;
  final String? phone;

  /// Free text, e.g. *Uncle*, *Neighbour*.
  final String? relation;

  /// Whether the contact can be called.
  bool get hasPhone => phone != null && phone!.trim().isNotEmpty;

  /// A row without any value (dropped before saving).
  bool get isBlank =>
      name.trim().isEmpty &&
      (phone?.trim().isEmpty ?? true) &&
      (relation?.trim().isEmpty ?? true);

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'relation': relation,
  };

  EmergencyContact copyWith({
    String? name,
    ValueGetter<String?>? phone,
    ValueGetter<String?>? relation,
  }) => EmergencyContact(
    name: name ?? this.name,
    phone: phone != null ? phone() : this.phone,
    relation: relation != null ? relation() : this.relation,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmergencyContact &&
          other.name == name &&
          other.phone == phone &&
          other.relation == relation;

  @override
  int get hashCode => Object.hash(name, phone, relation);

  @override
  String toString() => 'EmergencyContact($name)';
}

/// The "key details" counted by [EmergencyCard.completeness].
///
/// Allergies, medications and conditions are deliberately **not** counted:
/// an empty list is a valid answer ("none"), so a healthy child's card can
/// still be complete.
enum EmergencyCardSection { bloodGroup, contacts, doctor, insurance }

/// How much of the card is filled in (drives the completeness indicator).
@immutable
class EmergencyCardCompleteness {
  const EmergencyCardCompleteness(this.missing);

  /// Key details that are still empty, in [EmergencyCardSection] order.
  final List<EmergencyCardSection> missing;

  int get total => EmergencyCardSection.values.length;
  int get filled => total - missing.length;

  /// `0.0` … `1.0`.
  double get ratio => total == 0 ? 1 : filled / total;

  bool get isComplete => missing.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is EmergencyCardCompleteness && listEquals(other.missing, missing);

  @override
  int get hashCode => Object.hashAll(missing);
}

/// A member's emergency quick-access card (docs/03-API_CONTRACT.md §6).
///
/// `GET` returns an empty card (`updatedAt == null`) when none was saved, so
/// every member always has one. Lists are unmodifiable; blank strings parse
/// as `null`.
@immutable
class EmergencyCard {
  EmergencyCard({
    required this.memberId,
    this.bloodGroup = BloodGroup.unknown,
    List<String> allergies = const [],
    List<String> medications = const [],
    List<String> conditions = const [],
    this.doctorName,
    this.doctorPhone,
    this.insuranceProvider,
    this.insurancePolicyNumber,
    List<EmergencyContact> emergencyContacts = const [],
    this.notes,
    this.updatedAt,
    this.updatedById,
    this.offlineSavedAt,
  }) : allergies = List.unmodifiable(allergies),
       medications = List.unmodifiable(medications),
       conditions = List.unmodifiable(conditions),
       emergencyContacts = List.unmodifiable(emergencyContacts);

  /// The card a member has before anything was saved.
  factory EmergencyCard.empty(String memberId) =>
      EmergencyCard(memberId: memberId);

  /// Parses the contract shape. Never throws: unknown blood groups become
  /// [BloodGroup.unknown], junk list entries are skipped and a missing
  /// `memberId` falls back to [fallbackMemberId] (the id that was requested).
  factory EmergencyCard.fromJson(
    Map<String, dynamic> json, {
    String? fallbackMemberId,
  }) {
    List<String> list(Object? v) => [for (final s in asStringList(v)) s.trim()];
    String? text(Object? v) => asNonEmptyString(v)?.trim();
    return EmergencyCard(
      memberId:
          asNonEmptyString(json['memberId'])?.trim() ?? fallbackMemberId ?? '',
      bloodGroup: BloodGroup.fromWire(json['bloodGroup']),
      allergies: list(json['allergies']),
      medications: list(json['medications']),
      conditions: list(json['conditions']),
      doctorName: text(json['doctorName']),
      doctorPhone: text(json['doctorPhone']),
      insuranceProvider: text(json['insuranceProvider']),
      insurancePolicyNumber: text(json['insurancePolicyNumber']),
      emergencyContacts: asMapList(
        json['emergencyContacts'],
        EmergencyContact.fromJson,
      ).where((c) => !c.isBlank).toList(),
      notes: text(json['notes']),
      updatedAt: parseDate(json['updatedAt']),
      updatedById: asNonEmptyString(json['updatedById']),
    );
  }

  final String memberId;
  final BloodGroup bloodGroup;
  final List<String> allergies;
  final List<String> medications;
  final List<String> conditions;
  final String? doctorName;
  final String? doctorPhone;
  final String? insuranceProvider;
  final String? insurancePolicyNumber;
  final List<EmergencyContact> emergencyContacts;
  final String? notes;

  /// Last save on the server; `null` = never saved.
  final DateTime? updatedAt;

  /// Member who saved it last (self or an admin).
  final String? updatedById;

  /// Client-only: set when this card was served from the on-device offline
  /// copy (saved at this moment) because the server was unreachable. Never
  /// sent to or read from the API.
  final DateTime? offlineSavedAt;

  /// Whether this is the on-device offline copy (may be out of date).
  bool get isOfflineCopy => offlineSavedAt != null;

  /// Whether the card was ever saved on the server.
  bool get hasBeenSaved => updatedAt != null;

  bool get hasDoctor => doctorName != null || doctorPhone != null;

  bool get hasInsurance =>
      insuranceProvider != null || insurancePolicyNumber != null;

  bool get hasMedicalInfo =>
      allergies.isNotEmpty || medications.isNotEmpty || conditions.isNotEmpty;

  /// Contacts that have a phone number (the ones that can be called).
  List<EmergencyContact> get callableContacts =>
      emergencyContacts.where((c) => c.hasPhone).toList(growable: false);

  /// Nothing at all is recorded.
  bool get isEmpty =>
      !bloodGroup.isKnown &&
      !hasMedicalInfo &&
      !hasDoctor &&
      !hasInsurance &&
      emergencyContacts.isEmpty &&
      notes == null;

  /// Which key details are filled in (see [EmergencyCardSection]).
  EmergencyCardCompleteness get completeness => EmergencyCardCompleteness([
    if (!bloodGroup.isKnown) EmergencyCardSection.bloodGroup,
    if (callableContacts.isEmpty) EmergencyCardSection.contacts,
    if (!hasDoctor) EmergencyCardSection.doctor,
    if (!hasInsurance) EmergencyCardSection.insurance,
  ]);

  /// The full contract shape (also used for the offline copy).
  Map<String, dynamic> toJson() => {
    'memberId': memberId,
    ...toUpdateJson(),
    'updatedAt': isoOrNull(updatedAt),
    'updatedById': updatedById,
  };

  /// Body of `PUT /family/members/:id/emergency-card`: only the editable
  /// fields (the backend rejects unknown ones). The whole card is replaced,
  /// so cleared values are sent as `null` / `[]`. Strings are trimmed, blank
  /// list items and blank contact rows are dropped, list duplicates removed
  /// (case-insensitive, first spelling kept).
  Map<String, dynamic> toUpdateJson() {
    String? text(String? v) {
      final t = v?.trim();
      return t == null || t.isEmpty ? null : t;
    }

    return {
      'bloodGroup': bloodGroup.wireName,
      'allergies': cleanList(allergies),
      'medications': cleanList(medications),
      'conditions': cleanList(conditions),
      'doctorName': text(doctorName),
      'doctorPhone': text(doctorPhone),
      'insuranceProvider': text(insuranceProvider),
      'insurancePolicyNumber': text(insurancePolicyNumber),
      'emergencyContacts': [
        for (final c in emergencyContacts)
          if (!c.isBlank)
            {
              'name': c.name.trim(),
              'phone': text(c.phone),
              'relation': text(c.relation),
            },
      ],
      'notes': text(notes),
    };
  }

  /// Trimmed, non-blank, case-insensitively unique entries of [items].
  static List<String> cleanList(Iterable<String> items) {
    final seen = <String>{};
    return [
      for (final raw in items)
        if (raw.trim().isNotEmpty && seen.add(raw.trim().toLowerCase()))
          raw.trim(),
    ];
  }

  /// Nullable fields take a [ValueGetter] so they can be cleared:
  /// `card.copyWith(notes: () => null)`.
  EmergencyCard copyWith({
    String? memberId,
    BloodGroup? bloodGroup,
    List<String>? allergies,
    List<String>? medications,
    List<String>? conditions,
    ValueGetter<String?>? doctorName,
    ValueGetter<String?>? doctorPhone,
    ValueGetter<String?>? insuranceProvider,
    ValueGetter<String?>? insurancePolicyNumber,
    List<EmergencyContact>? emergencyContacts,
    ValueGetter<String?>? notes,
    ValueGetter<DateTime?>? updatedAt,
    ValueGetter<String?>? updatedById,
    ValueGetter<DateTime?>? offlineSavedAt,
  }) {
    return EmergencyCard(
      memberId: memberId ?? this.memberId,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      allergies: allergies ?? this.allergies,
      medications: medications ?? this.medications,
      conditions: conditions ?? this.conditions,
      doctorName: doctorName != null ? doctorName() : this.doctorName,
      doctorPhone: doctorPhone != null ? doctorPhone() : this.doctorPhone,
      insuranceProvider: insuranceProvider != null
          ? insuranceProvider()
          : this.insuranceProvider,
      insurancePolicyNumber: insurancePolicyNumber != null
          ? insurancePolicyNumber()
          : this.insurancePolicyNumber,
      emergencyContacts: emergencyContacts ?? this.emergencyContacts,
      notes: notes != null ? notes() : this.notes,
      updatedAt: updatedAt != null ? updatedAt() : this.updatedAt,
      updatedById: updatedById != null ? updatedById() : this.updatedById,
      offlineSavedAt: offlineSavedAt != null
          ? offlineSavedAt()
          : this.offlineSavedAt,
    );
  }

  /// Whether the editable content equals [other]'s (ignores `memberId`,
  /// timestamps and the offline marker) — used for "unsaved changes".
  bool sameContentAs(EmergencyCard other) =>
      jsonEncode(toUpdateJson()) == jsonEncode(other.toUpdateJson());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmergencyCard &&
          other.memberId == memberId &&
          other.bloodGroup == bloodGroup &&
          listEquals(other.allergies, allergies) &&
          listEquals(other.medications, medications) &&
          listEquals(other.conditions, conditions) &&
          other.doctorName == doctorName &&
          other.doctorPhone == doctorPhone &&
          other.insuranceProvider == insuranceProvider &&
          other.insurancePolicyNumber == insurancePolicyNumber &&
          listEquals(other.emergencyContacts, emergencyContacts) &&
          other.notes == notes &&
          other.updatedAt == updatedAt &&
          other.updatedById == updatedById &&
          other.offlineSavedAt == offlineSavedAt;

  @override
  int get hashCode => Object.hash(
    memberId,
    bloodGroup,
    Object.hashAll(allergies),
    Object.hashAll(medications),
    Object.hashAll(conditions),
    doctorName,
    doctorPhone,
    insuranceProvider,
    insurancePolicyNumber,
    Object.hashAll(emergencyContacts),
    notes,
    updatedAt,
    updatedById,
    offlineSavedAt,
  );

  /// No health data in logs (docs/08-COMPLIANCE.md §3 row 26).
  @override
  String toString() =>
      'EmergencyCard($memberId, saved: ${updatedAt != null}'
      '${isOfflineCopy ? ', offline copy' : ''})';
}
