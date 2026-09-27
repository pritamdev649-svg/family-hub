import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/network/api_exception.dart';
import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/notices/application/notices_providers.dart';
import 'package:family_hub/features/notices/data/notices_repository.dart';
import 'package:family_hub/features/notices/domain/notice.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_photo_field.dart';
import 'package:family_hub/features/notices/presentation/widgets/notice_style.dart';
import 'package:family_hub/shared/json.dart';

/// `/notices/new` and `/notices/:id/edit`.
///
/// Title (≤ 100), message (≤ 2000, with counter), optional photo (uploaded
/// to the `notices` folder) and — for admins only — a "Pin to top" switch.
///
/// The edit route receives the [Notice] as `extra` when opened from the
/// board; otherwise (deep link, restored route) it is looked up by id. A
/// notice that no longer exists shows a "no longer available" state instead
/// of an error with a pointless retry.
class NoticeFormScreen extends ConsumerWidget {
  const NoticeFormScreen({super.key, this.noticeId, this.initial});

  /// `null` → create a notice.
  final String? noticeId;

  /// The notice to edit when already in memory.
  final Notice? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final id = noticeId;

    if (id == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.noticesNew)),
        body: const ResponsiveCenter(child: _NoticeForm()),
      );
    }

    final given = initial;
    final AsyncValue<Notice?> notice = given != null && given.id == id
        ? AsyncData(given)
        : _notFoundAsEmpty(ref.watch(noticeByIdProvider(id)));
    final permissions = ref.watch(noticePermissionsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.noticesEditTitle)),
      body: ResponsiveCenter(
        child: AsyncValueView<Notice?>(
          value: notice,
          onRetry: () => ref.invalidate(noticeByIdProvider(id)),
          isEmpty: (n) => n == null,
          empty: EmptyState(
            icon: AppIcons.noticeOutlined,
            title: l10n.noticesNotFoundTitle,
            message: l10n.noticesNotFoundMessage,
            action: AppButton(
              label: l10n.commonBack,
              expand: false,
              onPressed: () => _leave(context),
            ),
          ),
          data: (n) => switch (n) {
            final n? when permissions.canEdit(n) => _NoticeForm(
              key: ValueKey(n.id),
              initial: n,
            ),
            _ => EmptyState(
              icon: AppIcons.security,
              title: l10n.noticesEditNotAllowed,
              message: l10n.noticesEditNotAllowedMessage,
            ),
          },
        ),
      ),
    );
  }

  /// A deleted (or never existing) notice is an expected outcome — e.g. a
  /// link to a notice someone removed — not an error worth retrying.
  static AsyncValue<Notice?> _notFoundAsEmpty(AsyncValue<Notice> value) {
    final error = value.error;
    if (!value.hasValue &&
        !value.isLoading &&
        error is ApiException &&
        error.isNotFound) {
      return const AsyncData(null);
    }
    return value;
  }

  /// Back to wherever the member came from; the home tab when the screen
  /// was opened directly (restored route / link with nothing below it —
  /// `/notices` is a top-level route, so going there would leave no way
  /// back into the app's tabs).
  static void _leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }
}

class _NoticeForm extends ConsumerStatefulWidget {
  const _NoticeForm({super.key, this.initial});

  final Notice? initial;

  @override
  ConsumerState<_NoticeForm> createState() => _NoticeFormState();
}

class _NoticeFormState extends ConsumerState<_NoticeForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _body;
  String? _imageUrl;
  bool _pinned = false;

  bool _saving = false;
  bool _dirty = false;
  bool _submitted = false;

  /// A photo upload is running (saving now would post without it).
  bool _uploading = false;

  /// Field messages from a server `VALIDATION_ERROR` (cleared on edit).
  final Map<String, String> _serverErrors = {};

  /// The message field grows up to this many lines, then scrolls.
  static const int _bodyMaxLines = 10;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final n = widget.initial;
    _title = TextEditingController(text: n?.title ?? '')
      ..addListener(_updateDirty);
    _body = TextEditingController(text: n?.body ?? '')
      ..addListener(_updateDirty);
    _imageUrl = n?.imageUrl;
    _pinned = n?.pinned ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool _computeDirty() {
    final n = widget.initial;
    return _title.text.trim() != (n?.title ?? '') ||
        _body.text.trim() != (n?.body ?? '') ||
        _imageUrl != n?.imageUrl ||
        _pinned != (n?.pinned ?? false);
  }

  void _updateDirty() {
    final dirty = _computeDirty();
    if (dirty != _dirty && mounted) setState(() => _dirty = dirty);
  }

  void _clearServerError(String field) {
    if (_serverErrors.remove(field) != null) setState(() {});
  }

  FormFieldValidator<String> _serverError(String field) =>
      (_) => _serverErrors[field];

  Future<void> _confirmDiscard() async {
    final l10n = context.l10n;
    final discard = await showConfirmDialog(
      context,
      title: l10n.commonDiscardChangesTitle,
      message: l10n.commonDiscardChangesMessage,
      confirmLabel: l10n.commonDiscard,
      destructive: true,
    );
    if (discard && mounted) context.pop();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_uploading) {
      context.showInfo(context.l10n.noticesPhotoUploading);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _submitted = true;
      _serverErrors.clear();
    });
    if (!_validateAndReveal()) return;

    final l10n = context.l10n;
    final controller = ref.read(noticesControllerProvider.notifier);
    final canPin = ref.read(noticePermissionsProvider).canPin;
    final before = widget.initial;

    setState(() => _saving = true);
    try {
      if (before == null) {
        await controller.create(
          NoticeDraft(
            title: _title.text,
            body: _body.text,
            imageUrl: _imageUrl,
            pinned: canPin ? _pinned : null,
          ),
        );
        if (!mounted) return;
        context.showSuccess(l10n.noticesPosted);
      } else {
        final patch = NoticePatch.diff(
          before,
          title: _title.text,
          body: _body.text,
          imageUrl: _imageUrl,
          pinned: canPin ? _pinned : null,
        );
        if (!patch.isEmpty) {
          final updated = await controller.update(before, patch);
          // Another save of this notice is still running.
          if (updated == null || !mounted) return;
          context.showSuccess(l10n.noticesUpdated);
        }
      }
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (before != null && e.isNotFound) {
        // Deleted by someone else while being edited: nothing left to save
        // (the controller already dropped it from the board).
        context.showInfo(l10n.noticesGone);
        context.pop();
        return;
      }
      _applyServerErrors(e);
      context.showError(e);
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _applyServerErrors(ApiException e) {
    if (!e.isValidation) return;
    final details = e.details ?? const <String, dynamic>{};
    for (final field in const ['title', 'body', 'imageUrl']) {
      final message = asNonEmptyString(details[field]);
      if (message != null) _serverErrors[field] = message;
    }
    if (_serverErrors.isEmpty) return;
    setState(() {});
    _validateAndReveal();
  }

  /// Validates the form; when a field is invalid, scrolls the first one into
  /// view (the submit button is at the bottom of a form taller than most
  /// phone screens, so the message could otherwise be off screen).
  bool _validateAndReveal() {
    final form = _formKey.currentState;
    if (form == null) return false;
    final invalid = form.validateGranularly();
    if (invalid.isEmpty) return true;
    final target = invalid.first.context;
    if (target.mounted) {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      Scrollable.ensureVisible(
        target,
        duration: reduceMotion ? Duration.zero : AppDurations.normal,
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canPin = ref.watch(noticePermissionsProvider.select((p) => p.canPin));
    final imageError = _serverErrors['imageUrl'];

    return PopScope<Object?>(
      canPop: !_dirty && !_saving && !_uploading,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _saving) return;
        _confirmDiscard();
      },
      child: Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        // Not a lazy ListView: a field scrolled far out of view must stay
        // registered with the form, or it would be skipped by validation.
        child: SingleChildScrollView(
          // Clear of the system gesture / navigation area at the bottom.
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FormSection(
                title: l10n.noticesSectionMessage,
                icon: AppIcons.notice,
                children: [
                  AppTextField(
                    controller: _title,
                    label: l10n.noticesFieldTitle,
                    hint: l10n.noticesFieldTitleHint,
                    maxLength: Notice.titleMaxLength,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    enabled: !_saving,
                    onChanged: (_) => _clearServerError('title'),
                    validator: Validators.compose([
                      Validators.required(l10n),
                      Validators.maxLength(l10n, Notice.titleMaxLength),
                      _serverError('title'),
                    ]),
                  ),
                  AppGap.md,
                  AppTextField(
                    controller: _body,
                    label: l10n.noticesFieldBody,
                    hint: l10n.noticesFieldBodyHint,
                    maxLines: _bodyMaxLines,
                    maxLength: Notice.bodyMaxLength,
                    textCapitalization: TextCapitalization.sentences,
                    enabled: !_saving,
                    onChanged: (_) => _clearServerError('body'),
                    validator: Validators.compose([
                      Validators.required(l10n),
                      Validators.maxLength(l10n, Notice.bodyMaxLength),
                      _serverError('body'),
                    ]),
                  ),
                ],
              ),
              AppGap.lg,
              _FormSection(
                title: l10n.noticesFieldImage,
                icon: AppIcons.image,
                children: [
                  AppGap.sm,
                  Center(
                    child: NoticePhotoField(
                      imageUrl: _imageUrl,
                      label: l10n.noticesPhotoHint,
                      enabled: !_saving,
                      onUploadingChanged: (uploading) =>
                          setState(() => _uploading = uploading),
                      onChanged: (url) {
                        _serverErrors.remove('imageUrl');
                        setState(() => _imageUrl = url);
                        _updateDirty();
                      },
                    ),
                  ),
                  if (imageError != null) ...[
                    AppGap.sm,
                    Text(
                      imageError,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              if (canPin) ...[
                AppGap.lg,
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: SwitchListTile(
                    secondary: const IconBadge(
                      icon: AppIcons.pin,
                      accent: NoticeStyle.accent,
                      size: AppSizes.badgeSm,
                    ),
                    title: Text(l10n.noticesFieldPinned),
                    subtitle: Text(l10n.noticesFieldPinnedHint),
                    value: _pinned,
                    activeThumbColor: Colors.white,
                    activeTrackColor: context.accent(NoticeStyle.accent).base,
                    onChanged: _saving
                        ? null
                        : (v) {
                            setState(() => _pinned = v);
                            _updateDirty();
                          },
                  ),
                ),
              ],
              AppGap.lg,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      AppIcons.family,
                      size: AppSizes.iconSm,
                      color: scheme.onSurfaceVariant,
                    ),
                    AppGap.hSm,
                    Expanded(
                      child: Text(
                        l10n.noticesVisibleToFamily,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AppGap.xl,
              AppButton(
                label: _isEdit ? l10n.commonSave : l10n.noticesPost,
                icon: _isEdit ? AppIcons.save : AppIcons.notice,
                isLoading: _saving,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One borderless card of the form with an amber section header.
class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: title, icon: icon, accent: NoticeStyle.accent),
          AppGap.xs,
          ...children,
        ],
      ),
    );
  }
}
