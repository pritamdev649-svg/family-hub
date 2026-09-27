import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/error_messages.dart'
    show unwrapProviderError;
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/services/cloudinary_service.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/family/application/family_providers.dart';
import 'package:family_hub/features/family/application/family_session_sync.dart';
import 'package:family_hub/features/family/application/member_editor_controller.dart';
import 'package:family_hub/features/family/domain/family_limits.dart';
import 'package:family_hub/features/family/domain/member_designation.dart';
import 'package:family_hub/features/family/domain/member_form_data.dart';
import 'package:family_hub/features/family/presentation/family_navigation.dart';
import 'package:family_hub/features/family/presentation/family_style.dart';
import 'package:family_hub/features/family/presentation/widgets/designation_field.dart';
import 'package:family_hub/features/family/presentation/widgets/family_choice_chips.dart';
import 'package:family_hub/features/family/presentation/widgets/family_info_row.dart';
import 'package:family_hub/features/family/presentation/widgets/field_help_text.dart';
import 'package:family_hub/features/family/presentation/widgets/guardian_consent_field.dart';
import 'package:family_hub/features/family/presentation/widgets/member_gone_view.dart';
import 'package:family_hub/shared/data/repository_utils.dart';
import 'package:family_hub/shared/l10n/shared_labels.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// Add a member ([memberId] `null`, admins only) or edit one.
///
/// Admins edit every field (not their own role); a member editing
/// themselves only sees name, phone, photo, gender and date of birth
/// (contract: self-limited `PATCH`). When the date of birth makes the person
/// younger than the family country's consent age, an admin must tick the
/// guardian-consent checkbox.
///
/// The access follows the session live: an admin demoted on another phone
/// sees "admins only" instead of a form they can no longer save. A member
/// that no longer exists shows [MemberGoneView].
class MemberFormScreen extends ConsumerWidget {
  const MemberFormScreen({super.key, this.memberId});

  /// Member to edit; `null` adds a new member.
  final String? memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isAdmin = ref.watch(isAdminProvider);
    final myId = ref.watch(currentMemberProvider.select((m) => m?.id));
    final id = memberId;
    ref.syncFamilySession();

    Widget content(Member? target) {
      final access = MemberFormAccess.resolve(
        isAdmin: isAdmin,
        currentMemberId: myId,
        target: target,
      );
      if (!access.isAllowed) {
        return EmptyState(
          icon: AppIcons.security,
          title: target == null
              ? l10n.commonAdminOnly
              : l10n.familyCannotEditTitle,
          message: target == null ? null : l10n.familyCannotEditMessage,
        );
      }
      return _MemberForm(
        key: ValueKey<String>(target?.id ?? 'new'),
        target: target,
        access: access,
      );
    }

    final String title;
    if (id == null) {
      title = l10n.familyAddMember;
    } else if (id == myId) {
      title = l10n.familyEditMyDetailsTitle;
    } else {
      title = l10n.familyEditMemberTitle;
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ResponsiveCenter(
        child: id == null
            ? content(null)
            : AsyncValueView<Member?>(
                value: memberOrGone(ref.watch(memberByIdProvider(id))),
                onRetry: () {
                  ref.invalidate(membersProvider);
                  ref.invalidate(memberByIdProvider(id));
                },
                isEmpty: (m) => m == null,
                empty: const MemberGoneView(),
                data: (m) => m == null ? const MemberGoneView() : content(m),
              ),
      ),
    );
  }
}

/// A field error the server reported for [value] (the field's text when the
/// save failed). Shown until the field changes.
typedef _ServerFieldError = ({String value, String message});

class _MemberForm extends ConsumerStatefulWidget {
  const _MemberForm({super.key, required this.target, required this.access});

  /// The member as loaded when the form opened (`null` when adding).
  final Member? target;
  final MemberFormAccess access;

  @override
  ConsumerState<_MemberForm> createState() => _MemberFormState();
}

class _MemberFormState extends ConsumerState<_MemberForm> {
  final _formKey = GlobalKey<FormState>();
  final _consentKey = GlobalKey();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _designation;

  /// The member the edits started from; the patch is computed against it
  /// (a background refresh must not turn untouched fields into changes).
  late final Member? _initial;
  late final MemberFormData _initialData;

  String? _avatarUrl;
  DateTime? _birthDate;
  Gender? _gender;
  MemberRole _role = MemberRole.member;
  bool _consent = false;

  /// Set after a successful save / confirmed discard so the route can pop.
  bool _leaving = false;

  /// After a failed submit every field re-validates as the user types.
  bool _autovalidate = false;

  /// The server answered `GUARDIAN_CONSENT_REQUIRED` although the app's
  /// rule said no consent was needed (its consent table or "today" differ):
  /// the checkbox is shown from then on and its value is sent.
  bool _consentRequiredByServer = false;

  /// Field errors of the last failed save by contract field name
  /// (`MEMBER_EMAIL_EXISTS`, `VALIDATION_ERROR` details).
  Map<String, _ServerFieldError> _serverErrors = const {};

  MemberFormAccess get _access => widget.access;

  @override
  void initState() {
    super.initState();
    final target = widget.target;
    _initial = target;
    final start = target == null
        ? const MemberFormData()
        : MemberFormData.fromMember(target);
    _name = TextEditingController(text: start.name);
    _email = TextEditingController(text: start.email ?? '');
    _phone = TextEditingController(text: start.phone ?? '');
    _designation = TextEditingController(text: start.designation ?? '');
    _avatarUrl = start.avatarUrl;
    _birthDate = start.birthDate;
    _gender = start.gender;
    _role = start.role;
    _consent = start.guardianConsent;
    _initialData = _data;
    for (final c in [_name, _email, _phone, _designation]) {
      c.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _designation]) {
      c
        ..removeListener(_onTextChanged)
        ..dispose();
    }
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  /// Current form values, normalised like the requests will be.
  MemberFormData get _data => MemberFormData(
    name: _name.text.trim(),
    email: trimOrNull(_email.text)?.toLowerCase(),
    phone: trimOrNull(Validators.normalizePhone(_phone.text)),
    avatarUrl: trimOrNull(_avatarUrl),
    birthDate: _birthDate,
    gender: _gender,
    designation: trimOrNull(_designation.text),
    role: _role,
    guardianConsent: _consent,
  );

  bool get _isDirty => _data != _initialData;

  /// The text fields' current values by contract field name.
  Map<String, String> get _fieldValues => {
    'name': _name.text.trim(),
    'email': _email.text.trim(),
    'phone': _phone.text.trim(),
    'designation': _designation.text.trim(),
  };

  /// [local] first, then the server's error for [field] while its value is
  /// still the one that was rejected.
  FormFieldValidator<String> _checked(
    String field, [
    FormFieldValidator<String>? local,
  ]) => (v) {
    final error = local?.call(v);
    if (error != null) return error;
    final server = _serverErrors[field];
    return server != null && server.value == (v ?? '').trim()
        ? server.message
        : null;
  };

  Future<void> _submit() async {
    final l10n = context.l10n;
    // A second tap while the duplicate-name dialog opens is ignored, and so
    // is a submit while a save is running.
    if (!context.isTopRoute) return;
    if (ref.read(memberEditorControllerProvider).isLoading) return;
    FocusScope.of(context).unfocus();
    setState(() => _serverErrors = const {});
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _autovalidate = true);
      return;
    }

    final data = _data;
    final initial = _initial;
    if (initial == null && !await _confirmDuplicateName(data)) return;
    if (!mounted) return;

    final controller = ref.read(memberEditorControllerProvider.notifier);
    try {
      if (initial == null) {
        final result = await controller.add(
          data,
          consentRequired: _consentRequiredByServer,
        );
        if (result == null || !mounted) return;
        final member = result.member;
        final email = member.email;
        if (!result.avatarSaved) {
          context.showInfo(l10n.familyPhotoNotSaved(member.name));
        } else if (email != null) {
          context.showSuccess(
            l10n.familyMemberAddedInvited(member.name, email),
          );
        } else {
          context.showSuccess(l10n.familyMemberAdded(member.name));
        }
      } else {
        final updated = await controller.update(
          initial,
          data,
          _access,
          consentRequired: _consentRequiredByServer,
        );
        if (updated == null || !mounted) return;
        context.showSuccess(l10n.commonSaved);
      }
      _leave();
    } catch (e) {
      // GUARDIAN_CONSENT_REQUIRED, MEMBER_EMAIL_EXISTS, LAST_ADMIN,
      // FORBIDDEN, VALIDATION_ERROR, network … → localised message, plus
      // the field it concerns where there is one.
      if (!mounted) return;
      context.showError(e);
      _showServerErrors(e);
    }
  }

  /// Asks before adding a second member with the same name (usually a
  /// mistake, or a retry of an add whose answer was lost although the
  /// server created the member).
  Future<bool> _confirmDuplicateName(MemberFormData data) async {
    final members = ref.read(membersProvider).value ?? const <Member>[];
    final existing = data.sameNameIn(members);
    if (existing == null) return true;
    final l10n = context.l10n;
    return showConfirmDialog(
      context,
      title: l10n.familyDuplicateNameTitle(existing.name),
      message: l10n.familyDuplicateNameMessage,
      confirmLabel: l10n.familyDuplicateNameConfirm,
    );
  }

  /// Shows what the server rejected at the field it concerns: the email of
  /// `MEMBER_EMAIL_EXISTS`, the fields of `VALIDATION_ERROR`, and the
  /// guardian-consent checkbox after `GUARDIAN_CONSENT_REQUIRED`.
  void _showServerErrors(Object error) {
    final e = unwrapProviderError(error);
    if (e is! ApiException) return;
    final l10n = context.l10n;
    final values = _fieldValues;
    final errors = <String, _ServerFieldError>{};
    if (e.code == ApiErrorCode.memberEmailExists) {
      errors['email'] = (
        value: _email.text.trim(),
        message: l10n.errorMemberEmailExists,
      );
    } else if (e.code == ApiErrorCode.validation) {
      for (final MapEntry(:key, :value) in (e.details ?? const {}).entries) {
        final fieldValue = values[key];
        if (fieldValue == null) continue;
        final message = '${value ?? ''}'.trim();
        errors[key] = (
          value: fieldValue,
          message: message.isEmpty ? l10n.errorValidation : message,
        );
      }
    }
    final consentMissing = e.code == ApiErrorCode.guardianConsentRequired;
    if (errors.isEmpty && !consentMissing) return;
    setState(() {
      _serverErrors = errors;
      _autovalidate = true;
      if (consentMissing) _consentRequiredByServer = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _formKey.currentState?.validate();
      final consent = _consentKey.currentContext;
      if (consentMissing && consent != null && consent.mounted) {
        Scrollable.ensureVisible(consent, duration: AppDurations.normal);
      }
    });
  }

  void _leave() {
    setState(() => _leaving = true);
    // Opened directly (deep link): continue to the member list.
    context.popOrGo(AppRoutes.members);
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
    if (discard && mounted) _leave();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final country = ref.watch(currentCountryProvider);
    final busy = ref.watch(
      memberEditorControllerProvider.select((s) => s.isLoading),
    );
    final data = _data;
    final target = _initial;
    final access = _access;
    final emailEditable = access.canEditEmail(target);
    final showEmail = access.isAdminAccess;
    final needsConsent =
        access.isAdminAccess &&
        (_consentRequiredByServer || data.needsGuardianConsent(country));
    final today = DateUtils.dateOnly(DateTime.now());

    final String? emailHelp;
    if (!emailEditable) {
      emailHelp = access.isSelf
          ? l10n.familyEmailLinkedSelfHint
          : l10n.familyEmailLinkedHint;
    } else if (access.isAdd) {
      emailHelp = l10n.familyEmailInviteHint;
    } else if (target?.hasAccount == false) {
      emailHelp = l10n.familyEmailManagedHint;
    } else {
      emailHelp = null;
    }

    // Inputs without an `enabled` switch are locked while a save runs (the
    // values were already sent).
    Widget lockable(Widget child) =>
        IgnorePointer(ignoring: busy, child: child);

    return PopScope(
      canPop: _leaving || !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Form(
        key: _formKey,
        autovalidateMode: _autovalidate
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: ListView(
          padding: AppSpacing.screen.copyWith(
            bottom: AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            // Photo, centred on a soft blue card.
            AppCard(
              accent: FamilyStyle.accent,
              child: Center(
                child: lockable(
                  ImagePickerField(
                    imageUrl: _avatarUrl,
                    onChanged: (url) => setState(() => _avatarUrl = url),
                    folder: UploadFolder.avatars,
                    circular: true,
                    label: l10n.familyPhotoLabel,
                  ),
                ),
              ),
            ),
            AppGap.xl,
            _Section(
              title: l10n.familyDetailsSection,
              icon: AppIcons.memberOutlined,
              accent: FamilyStyle.accent,
              children: [
                AppTextField(
                  controller: _name,
                  label: l10n.familyNameLabel,
                  prefixIcon: AppIcons.memberOutlined,
                  maxLength: FamilyLimits.name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  enabled: !busy,
                  validator: _checked(
                    'name',
                    Validators.compose([
                      Validators.required(l10n),
                      Validators.maxLength(l10n, FamilyLimits.name),
                    ]),
                  ),
                ),
                AppGap.md,
                lockable(
                  DatePickerField(
                    label: l10n.familyInfoDateOfBirth,
                    value: _birthDate,
                    firstDate: DatePickerField.defaultFirstDate,
                    lastDate: today,
                    onChanged: (d) => setState(() => _birthDate = d),
                  ),
                ),
                AppGap.lg,
                _FieldLabel(l10n.familyInfoGender),
                lockable(
                  FamilyChoiceChips<Gender?>(
                    options: const [...Gender.values, null],
                    selected: _gender,
                    label: (g) => g.labelOrUnspecified(l10n),
                    accent: AppAccent.violet,
                    onSelected: (g) => setState(() => _gender = g),
                  ),
                ),
              ],
            ),
            AppGap.xl,
            _Section(
              title: l10n.familyContactSection,
              icon: AppIcons.phone,
              accent: AppAccent.emerald,
              children: [
                if (showEmail) ...[
                  AppTextField(
                    controller: _email,
                    label: l10n.familyEmailLabel,
                    prefixIcon: AppIcons.email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    enabled: emailEditable && !busy,
                    validator: emailEditable
                        ? _checked(
                            'email',
                            Validators.email(l10n, optional: true),
                          )
                        : null,
                  ),
                  if (emailHelp != null) FieldHelpText(emailHelp),
                  if (emailEditable && access.isAdd)
                    FieldHelpText(l10n.familyNoEmailHint),
                  AppGap.md,
                ],
                AppTextField(
                  controller: _phone,
                  label: l10n.familyPhoneLabel,
                  prefixIcon: AppIcons.phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  enabled: !busy,
                  validator: _checked('phone', Validators.phone(l10n)),
                ),
                FieldHelpText(l10n.familyPhoneHint(country.dialCode)),
              ],
            ),
            if (access.isAdminAccess) ...[
              AppGap.xl,
              _Section(
                title: l10n.familyRoleSection,
                icon: AppIcons.designation,
                accent: AppAccent.amber,
                children: [
                  DesignationField(
                    controller: _designation,
                    enabled: !busy,
                    suggestions: DesignationSuggestion.forAgeGroup(
                      data.ageGroup,
                    ),
                    validator: _checked('designation'),
                  ),
                  if (access.canEditRole) ...[
                    AppGap.lg,
                    _FieldLabel(l10n.familyInfoRole),
                    lockable(
                      FamilyChoiceChips<MemberRole>(
                        options: MemberRole.values,
                        selected: _role,
                        label: (r) => r.label(l10n),
                        icon: (r) => r.icon,
                        accentOf: (r) => r.accent,
                        onSelected: (r) => setState(() => _role = r),
                      ),
                    ),
                    AppGap.sm,
                    Text(
                      _role.description(l10n),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ] else if (access == MemberFormAccess.adminEditSelf) ...[
                    AppGap.md,
                    FamilyInfoRow(
                      icon: _role.icon,
                      accent: _role.accent,
                      label: l10n.familyInfoRole,
                      value: _role.label(l10n),
                      detail: l10n.familyRoleChangeSelfNote,
                    ),
                  ],
                ],
              ),
            ],
            if (needsConsent) ...[
              AppGap.xl,
              GuardianConsentField(
                key: _consentKey,
                country: country,
                value: _consent,
                enabled: !busy,
                onChanged: (v) => setState(() => _consent = v),
              ),
            ],
            AppGap.xl,
            AppButton(
              label: access.isAdd ? l10n.familyAddMember : l10n.commonSave,
              icon: access.isAdd ? AppIcons.addMember : AppIcons.save,
              isLoading: busy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// A form section: [SectionHeader] with a thin accent icon above a
/// borderless [AppCard] holding the fields.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.accent,
    required this.children,
  });

  final String title;
  final IconData icon;
  final AppAccent accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: title, icon: icon, accent: accent),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}
