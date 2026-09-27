import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/config/countries.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/error_messages.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/services/cloudinary_service.dart';
import 'package:family_hub/core/utils/date_x.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/settings/application/settings_actions.dart';
import 'package:family_hub/features/settings/presentation/settings_navigation.dart';
import 'package:family_hub/features/settings/presentation/widgets/no_family_view.dart';
import 'package:family_hub/features/settings/presentation/widgets/settings_page.dart';
import 'package:family_hub/features/settings/presentation/widgets/settings_section.dart';
import 'package:family_hub/shared/data/me_repository.dart';
import 'package:family_hub/shared/data/repository_utils.dart';
import 'package:family_hub/shared/l10n/shared_labels.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// Edit your own profile: photo, name, phone, date of birth and gender
/// (`PATCH /me`). Designation and role are shown read-only — admins set them.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  /// Longest name the API accepts.
  static const maxNameLength = 60;

  /// Accent of this screen's section headers.
  static const AppAccent accent = AppAccents.settings;

  /// Earliest selectable date of birth. The API rejects years before 1900
  /// in UTC, and local midnight of 1 January 1900 is still 1899 in UTC for
  /// every time zone east of Greenwich.
  static final firstBirthDate = DateTime(1900, 1, 2);

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  /// The member as loaded, with the date of birth as a local calendar date
  /// so it compares equal to what the date picker returns.
  Member? _original;
  String? _avatarUrl;
  DateTime? _dateOfBirth;
  Gender? _gender;
  bool _saving = false;
  bool _closing = false;

  /// After the first save attempt fields re-validate while the user edits
  /// them, so fixed errors disappear right away.
  bool _submitted = false;

  /// Inline messages for values the server rejected, by `PATCH /me` field
  /// (`name`, `phone`, `dateOfBirth`). Cleared when that field changes.
  Map<String, String> _serverErrors = const {};

  @override
  void initState() {
    super.initState();
    final member = ref.read(currentMemberProvider);
    if (member != null) {
      final original = member.copyWith(dateOfBirth: () => member.birthDate);
      _original = original;
      _name.text = original.name;
      _phone.text = original.phone ?? '';
      _avatarUrl = original.avatarUrl;
      _dateOfBirth = original.dateOfBirth;
      _gender = original.gender;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Member? get _edited => _original?.copyWith(
    name: _name.text.trim(),
    phone: () => trimOrNull(_phone.text),
    avatarUrl: () => trimOrNull(_avatarUrl),
    dateOfBirth: () => _dateOfBirth,
    gender: () => _gender,
  );

  bool get _dirty {
    final original = _original;
    final edited = _edited;
    if (original == null || edited == null) return false;
    return !MePatch.diff(original, edited).isEmpty;
  }

  void _changed([String? field]) => setState(() {
    if (field != null && _serverErrors.containsKey(field)) {
      _serverErrors = {..._serverErrors}..remove(field);
    }
  });

  /// Server-side validator for [field] (see [_serverErrors]).
  FormFieldValidator<String> _serverValidator(String field) =>
      (_) => _serverErrors[field];

  /// Date of birth: the server's verdict first, then the consent rule — a
  /// member without recorded guardian consent cannot set an age below the
  /// family country's consent age themselves (GAP-05; an admin adds them).
  String? _validateDateOfBirth(DateTime? dob, CountryInfo country) {
    final server = _serverErrors['dateOfBirth'];
    if (server != null) return server;
    final original = _original;
    if (dob == null || original == null || original.guardianConsent) {
      return null;
    }
    if (dob == original.dateOfBirth) return null; // unchanged → not sent
    final age = ageFrom(dob);
    if (age != null && age < country.consentAge) {
      return context.l10n.settingsProfileGuardianConsentNeeded(
        country.consentAge,
      );
    }
    return null;
  }

  Future<void> _save() async {
    final original = _original;
    final edited = _edited;
    if (_saving || original == null || edited == null) return;
    setState(() {
      _submitted = true;
      _serverErrors = const {};
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final country = ref.read(currentCountryProvider);
    setState(() => _saving = true);
    try {
      final changed = await ref
          .read(settingsActionsProvider)
          .saveProfile(original, edited);
      if (!mounted) return;
      if (changed) context.showSuccess(l10n.settingsProfileSaved);
      _close();
    } catch (e) {
      if (!mounted) return;
      final fields = _fieldErrors(e, country);
      if (fields.isEmpty) {
        context.showError(e);
      } else {
        setState(() => _serverErrors = fields);
        _formKey.currentState?.validate();
        if (fields.containsKey('avatarUrl')) {
          context.showInfo(l10n.settingsProfilePhotoRejected);
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Field messages for a rejected `PATCH /me` (localized here: the
  /// server's `details` texts are not). Empty → show the generic error.
  Map<String, String> _fieldErrors(Object error, CountryInfo country) {
    final e = unwrapProviderError(error);
    if (e is! ApiException) return const {};
    final l10n = context.l10n;
    if (e.code == ApiErrorCode.guardianConsentRequired) {
      final age = e.details?['consentAge'];
      return {
        'dateOfBirth': l10n.settingsProfileGuardianConsentNeeded(
          age is int ? age : country.consentAge,
        ),
      };
    }
    if (!e.isValidation) return const {};
    final fields = e.fieldErrors;
    return {
      if (fields.containsKey('name'))
        'name': l10n.settingsProfileNameInvalid(ProfileScreen.maxNameLength),
      if (fields.containsKey('phone')) 'phone': l10n.validationPhone,
      if (fields.containsKey('dateOfBirth'))
        'dateOfBirth': l10n.settingsProfileDateOfBirthInvalid,
      if (fields.containsKey('avatarUrl'))
        'avatarUrl': l10n.settingsProfilePhotoRejected,
    };
  }

  /// Leaves the screen once the rebuilt [PopScope] allows it.
  void _close() {
    setState(() => _closing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) closeSettingsScreen(context);
    });
  }

  Future<void> _confirmDiscard() async {
    final l10n = context.l10n;
    final discard = await showConfirmDialog(
      context,
      title: l10n.commonDiscardChangesTitle,
      message: l10n.commonDiscardChangesMessage,
      confirmLabel: l10n.commonDiscard,
      destructive: true,
    );
    if (discard && mounted) _close();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final original = _original;
    if (original == null) {
      return SettingsPage(
        title: l10n.settingsProfileTitle,
        child: const NoFamilyView(),
      );
    }

    final user = ref.watch(currentUserProvider);
    final country = ref.watch(currentCountryProvider);
    final email = original.email ?? user?.email;
    final theme = Theme.of(context);
    final dirty = _dirty;

    return PopScope(
      canPop: !dirty || _closing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _confirmDiscard();
      },
      child: SettingsPage(
        title: l10n.settingsProfileTitle,
        child: Form(
          key: _formKey,
          autovalidateMode: _submitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: SettingsListView(
            children: [
              Center(
                child: ImagePickerField(
                  imageUrl: _avatarUrl,
                  folder: UploadFolder.avatars,
                  circular: true,
                  size: AppSizes.avatarXl * 2,
                  label: l10n.settingsProfilePhoto,
                  onChanged: (url) => setState(() {
                    _avatarUrl = url;
                    _serverErrors = {..._serverErrors}..remove('avatarUrl');
                  }),
                ),
              ),
              AppGap.xl,
              SectionHeader(
                title: l10n.settingsProfileSectionPersonal,
                icon: AppIcons.profile,
                accent: ProfileScreen.accent,
              ),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppTextField(
                      controller: _name,
                      label: l10n.settingsProfileName,
                      prefixIcon: AppIcons.member,
                      maxLength: ProfileScreen.maxNameLength,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      enabled: !_saving,
                      onChanged: (_) => _changed('name'),
                      validator: Validators.compose([
                        Validators.required(l10n),
                        Validators.maxLength(l10n, ProfileScreen.maxNameLength),
                        _serverValidator('name'),
                      ]),
                    ),
                    AppGap.md,
                    AppTextField(
                      controller: _phone,
                      label: l10n.settingsProfilePhone,
                      hint: l10n.settingsProfilePhoneHint,
                      prefixIcon: AppIcons.phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      enabled: !_saving,
                      onChanged: (_) => _changed('phone'),
                      validator: Validators.compose([
                        Validators.phone(l10n),
                        _serverValidator('phone'),
                      ]),
                    ),
                    AppGap.lg,
                    DatePickerField(
                      label: l10n.settingsProfileDateOfBirth,
                      value: _dateOfBirth,
                      firstDate: ProfileScreen.firstBirthDate,
                      lastDate: DateTime.now(),
                      validator: (d) => _validateDateOfBirth(d, country),
                      onChanged: (d) {
                        _dateOfBirth = d;
                        _changed('dateOfBirth');
                      },
                    ),
                    AppGap.lg,
                    Text(
                      l10n.settingsProfileGender,
                      style: theme.textTheme.titleSmall,
                    ),
                    AppGap.sm,
                    ChoiceChipsField<Gender?>(
                      options: const [null, ...Gender.values],
                      selected: _gender,
                      label: (g) => g.labelOrUnspecified(l10n),
                      onSelected: (g) {
                        if (!_saving) setState(() => _gender = g);
                      },
                    ),
                  ],
                ),
              ),
              AppGap.xl,
              _ReadOnlyDetails(
                email: email,
                designation: original.designation,
                role: original.role.label(l10n),
              ),
              AppGap.xl,
              AppButton(
                label: l10n.commonSave,
                icon: AppIcons.save,
                isLoading: _saving,
                onPressed: dirty ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Email, designation and role — managed elsewhere, shown for reference as
/// icon-badge rows.
class _ReadOnlyDetails extends StatelessWidget {
  const _ReadOnlyDetails({
    required this.email,
    required this.designation,
    required this.role,
  });

  final String? email;
  final String? designation;
  final String role;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: l10n.settingsSectionAccount,
          icon: AppIcons.designation,
          accent: AppAccents.family,
          children: [
            if (email != null && email!.isNotEmpty)
              SettingsTile(
                icon: AppIcons.email,
                accent: AppAccent.sky,
                title: l10n.settingsProfileEmail,
                subtitle: email,
              ),
            SettingsTile(
              icon: AppIcons.designation,
              accent: AppAccents.family,
              title: l10n.settingsProfileDesignation,
              subtitle: designation ?? l10n.commonNotSet,
            ),
            SettingsTile(
              icon: AppIcons.admin,
              accent: AppAccent.indigo,
              title: l10n.settingsProfileRole,
              subtitle: role,
            ),
          ],
        ),
        AppGap.sm,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            l10n.settingsProfileManagedByAdmin,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
