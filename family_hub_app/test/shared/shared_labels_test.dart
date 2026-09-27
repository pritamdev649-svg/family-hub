import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/l10n/app_localizations.dart';
import 'package:family_hub/shared/l10n/shared_labels.dart';
import 'package:family_hub/shared/models/member.dart';

void main() {
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('every enum value has a non-empty English label', () {
    for (final r in MemberRole.values) {
      expect(r.label(en), isNotEmpty);
      expect(r.description(en), isNotEmpty);
    }
    for (final g in Gender.values) {
      expect(g.label(en), isNotEmpty);
    }
    for (final a in AgeGroup.values) {
      expect(a.label(en), isNotEmpty);
    }
    for (final m in LocationSharingMode.values) {
      expect(m.label(en), isNotEmpty);
      expect(m.description(en), isNotEmpty);
    }
    expect(null.labelOrUnspecified(en), en.genderUnspecified);
    expect(Gender.female.labelOrUnspecified(en), en.genderFemale);
  });

  test('ageYears plural and member helpers', () {
    expect(en.ageYears(0), 'Under 1 year');
    expect(en.ageYears(1), '1 year');
    expect(en.ageYears(12), '12 years');
    const noDob = Member(id: 'x', familyId: 'f', name: 'X');
    expect(noDob.ageLabel(en), isNull);
    expect(noDob.titleOrRole(en), en.roleMember);
    expect(noDob.copyWith(designation: () => 'CFO').titleOrRole(en), 'CFO');
  });
}
