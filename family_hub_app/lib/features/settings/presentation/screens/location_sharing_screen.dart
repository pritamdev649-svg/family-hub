import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/services/location_service.dart';
import 'package:family_hub/core/utils/formatters.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/settings/application/settings_actions.dart';
import 'package:family_hub/features/settings/presentation/settings_labels.dart';
import 'package:family_hub/features/settings/presentation/widgets/no_family_view.dart';
import 'package:family_hub/features/settings/presentation/widgets/selection_check.dart';
import 'package:family_hub/features/settings/presentation/widgets/settings_page.dart';
import 'package:family_hub/shared/l10n/shared_labels.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/session/session_controller.dart';

/// Who can see my location: never / only during SOS / always, as three
/// option cards. Choosing "always" asks for location permission and shares a
/// first fix right away; while it is on, a solid teal card shows when the
/// location was last shared.
class LocationSharingScreen extends ConsumerStatefulWidget {
  const LocationSharingScreen({super.key});

  /// Accent of this screen (matches its row on the More tab).
  static const AppAccent accent = AppAccent.teal;

  @override
  ConsumerState<LocationSharingScreen> createState() =>
      _LocationSharingScreenState();
}

class _LocationSharingScreenState extends ConsumerState<LocationSharingScreen> {
  /// Mode being saved (shown selected while the request runs).
  LocationSharingMode? _pending;
  bool _sharing = false;

  /// Why "always" could not be turned on (permission problem), if any.
  LocationPermissionState? _permissionProblem;

  bool get _busy => _pending != null || _sharing;

  /// Notices the member returning from the phone settings.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkAlwaysPermission(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  bool get _sharesAlways =>
      ref.read(currentMemberProvider)?.locationSharing.sharesAlways ?? false;

  /// "Always share" is on but location permission was taken away (e.g. in
  /// the phone settings): explain it and offer the fix instead of implying
  /// the family sees a current location. Never prompts.
  Future<void> _checkAlwaysPermission() async {
    if (!mounted || _busy || _permissionProblem != null || !_sharesAlways) {
      return;
    }
    final state = await ref.read(locationServiceProvider).checkPermission();
    if (!mounted || state.isGranted || _busy || _permissionProblem != null) {
      return;
    }
    if (_sharesAlways) setState(() => _permissionProblem = state);
  }

  /// Back from the phone settings: with permission granted, finish what the
  /// member started (turning on "always" or sharing now); otherwise check
  /// whether "always" lost its permission meanwhile.
  Future<void> _onResume() async {
    if (_busy) return;
    if (_permissionProblem == null) return _checkAlwaysPermission();
    final state = await ref.read(locationServiceProvider).checkPermission();
    if (!mounted || !state.isGranted || _permissionProblem == null) return;
    setState(() => _permissionProblem = null);
    await _retryWithPermission();
  }

  /// Retries the action that needed location permission.
  Future<void> _retryWithPermission() {
    final current = ref.read(currentMemberProvider)?.locationSharing;
    return current == LocationSharingMode.always
        ? _shareNow()
        : _select(LocationSharingMode.always);
  }

  Future<void> _select(LocationSharingMode mode) async {
    final current = ref.read(currentMemberProvider)?.locationSharing;
    if (_busy || mode == current) return;
    final l10n = context.l10n;
    setState(() {
      _pending = mode;
      _permissionProblem = null;
    });
    try {
      final result = await ref
          .read(settingsActionsProvider)
          .setLocationSharing(mode);
      if (!mounted) return;
      _report(result, l10n.settingsLocationSaved);
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  Future<void> _shareNow() async {
    if (_busy) return;
    final l10n = context.l10n;
    setState(() {
      _sharing = true;
      _permissionProblem = null;
    });
    try {
      final result = await ref.read(settingsActionsProvider).shareLocationNow();
      if (!mounted) return;
      _report(result, l10n.settingsLocationUpdated);
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _report(LocationSharingResult result, String successMessage) {
    final l10n = context.l10n;
    switch (result.outcome) {
      case LocationSharingOutcome.saved:
      case LocationSharingOutcome.shared:
        context.showSuccess(successMessage);
      case LocationSharingOutcome.noFix:
        context.showInfo(l10n.settingsLocationFixUnavailable);
      case LocationSharingOutcome.permissionDenied:
        setState(() => _permissionProblem = result.permission);
    }
  }

  Future<void> _fixPermission(LocationPermissionState state) async {
    if (state.needsSettings) {
      final opened = await ref.read(locationServiceProvider).openSettings();
      if (!opened && mounted) {
        context.showInfo(context.l10n.settingsOpenSettingsFailed);
      }
      return;
    }
    await _retryWithPermission();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final member = ref.watch(currentMemberProvider);

    if (member == null) {
      return SettingsPage(
        title: l10n.settingsLocationSharing,
        child: const NoFamilyView(),
      );
    }

    final selected = _pending ?? member.locationSharing;
    final problem = _permissionProblem;

    return SettingsPage(
      title: l10n.settingsLocationSharing,
      child: SettingsListView(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpacing.xs),
            child: Text(
              l10n.settingsLocationIntro,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          AppGap.lg,
          if (member.locationSharing.sharesAlways && _pending == null) ...[
            _SharingIndicator(
              lastSharedAt: member.lastLocation?.recordedAt,
              busy: _sharing,
              onShareNow: _busy ? null : _shareNow,
            ),
            AppGap.lg,
          ],
          for (final mode in LocationSharingMode.values) ...[
            if (mode.index > 0) AppGap.sm,
            _ModeCard(
              mode: mode,
              selected: mode == selected,
              saving: _pending == mode,
              enabled: !_busy,
              onTap: () => _select(mode),
            ),
          ],
          if (problem != null) ...[
            AppGap.lg,
            _PermissionNotice(
              state: problem,
              onFix: _busy ? null : () => _fixPermission(problem),
            ),
          ],
          AppGap.xl,
          SectionHeader(
            title: l10n.settingsLocationHowItWorks,
            icon: AppIcons.info,
            accent: LocationSharingScreen.accent,
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Note(
                  icon: AppIcons.liveLocation,
                  accent: _ModeCard.accentOf(LocationSharingMode.always),
                  text: l10n.settingsLocationAlwaysNote,
                ),
                AppGap.lg,
                _Note(
                  icon: AppIcons.sosAlert,
                  accent: _ModeCard.accentOf(LocationSharingMode.sosOnly),
                  text: l10n.settingsLocationSosNote,
                ),
                AppGap.lg,
                _Note(
                  icon: AppIcons.locationOff,
                  accent: _ModeCard.accentOf(LocationSharingMode.never),
                  text: l10n.settingsLocationNeverNote,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One sharing option: a solid icon badge in the option's accent, its name
/// and a one-line description. The chosen card is tinted and checked; the
/// card being saved shows a spinner instead of its badge.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.saving,
    required this.enabled,
    required this.onTap,
  });

  final LocationSharingMode mode;
  final bool selected;
  final bool saving;
  final bool enabled;
  final VoidCallback onTap;

  /// Colour of each option (teal = location, red = SOS).
  static AppAccent accentOf(LocationSharingMode mode) => switch (mode) {
    LocationSharingMode.never => AppAccent.indigo,
    LocationSharingMode.sosOnly => AppAccents.sos,
    LocationSharingMode.always => LocationSharingScreen.accent,
  };

  static const double _dimmedOpacity = 0.6;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final accent = accentOf(mode);
    final shades = context.accent(accent);

    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        enabled: enabled,
        child: Opacity(
          opacity: enabled || selected ? 1 : _dimmedOpacity,
          child: AppCard(
            accent: selected ? accent : null,
            onTap: enabled ? onTap : null,
            child: Row(
              children: [
                if (saving)
                  const SizedBox.square(
                    dimension: AppSizes.badgeMd,
                    child: Center(
                      child: SizedBox.square(
                        dimension: AppSizes.spinnerSm,
                        child: CircularProgressIndicator(
                          strokeWidth: AppSizes.spinnerStroke,
                        ),
                      ),
                    ),
                  )
                else
                  IconBadge(icon: mode.icon, accent: accent),
                AppGap.hMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.label(l10n),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: selected
                              ? shades.onContainer
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      AppGap.xxs,
                      Text(
                        mode.description(l10n),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                AppGap.hSm,
                SelectionCheck(selected: selected, accent: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Solid teal highlight card: "Your family can see your location", when it
/// was last shared and a frosted "Share now" button.
class _SharingIndicator extends ConsumerWidget {
  const _SharingIndicator({
    required this.lastSharedAt,
    required this.busy,
    required this.onShareNow,
  });

  final DateTime? lastSharedAt;
  final bool busy;
  final VoidCallback? onShareNow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final fmt = ref.watch(fmtProvider);
    final at = lastSharedAt;
    const accent = LocationSharingScreen.accent;

    return Semantics(
      container: true,
      liveRegion: true,
      child: GradientCard(
        gradient: AppGradients.of(accent),
        glowColor: accent.base,
        padding: AppSpacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _FrostedIcon(icon: AppIcons.myLocation),
                AppGap.hMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.settingsLocationSharedNow,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      AppGap.xxs,
                      Text(
                        at == null
                            ? l10n.settingsLocationNotSharedYet
                            : l10n.settingsLocationLastShared(
                                fmt.relative(at, l10n),
                              ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            AppGap.lg,
            _GlassButton(
              label: l10n.settingsLocationShareNow,
              icon: AppIcons.myLocation,
              isLoading: busy,
              onPressed: onShareNow,
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin white icon on a frosted square, for use on gradients.
class _FrostedIcon extends StatelessWidget {
  const _FrostedIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSizes.badgeMd,
      height: AppSizes.badgeMd,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: AppRadius.brMd,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: AppSizes.iconMd, color: Colors.white),
    );
  }
}

/// Frosted white button for use on a gradient card. Shows a spinner and is
/// disabled while [isLoading] (no double submit).
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      value: isLoading ? context.l10n.commonLoading : null,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.22),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.14),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.75),
          shadowColor: Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox.square(
                dimension: AppSizes.spinnerSm,
                child: CircularProgressIndicator(
                  strokeWidth: AppSizes.spinnerStroke,
                  color: Colors.white,
                ),
              )
            else
              Icon(icon, size: AppSizes.iconSm),
            AppGap.hSm,
            Flexible(child: Text(label, softWrap: true)),
          ],
        ),
      ),
    );
  }
}

/// Explains a missing permission and offers the fix (prompt again or open
/// the phone settings).
class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice({required this.state, required this.onFix});

  final LocationPermissionState state;
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Semantics(
      liveRegion: true,
      container: true,
      child: AppCard(
        accent: AppAccents.warning,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IconBadge(
              icon: AppIcons.warning,
              accent: AppAccents.warning,
              size: AppSizes.badgeSm,
            ),
            AppGap.hMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(state.message(l10n), style: theme.textTheme.bodyMedium),
                  AppGap.md,
                  AppButton(
                    label: state.needsSettings
                        ? l10n.servicesOpenSettings
                        : l10n.servicesLocationAllow,
                    icon: state.needsSettings
                        ? AppIcons.settings
                        : AppIcons.location,
                    variant: AppButtonVariant.secondary,
                    expand: false,
                    onPressed: onFix,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One "how it works" line: a soft icon badge and the explanation.
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.accent, required this.text});

  final IconData icon;
  final AppAccent accent;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconBadge(
          icon: icon,
          accent: accent,
          size: AppSizes.badgeSm,
          soft: true,
        ),
        AppGap.hMd,
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
