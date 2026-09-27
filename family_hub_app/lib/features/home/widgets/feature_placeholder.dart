// STUB SUPPORT - only used by the "// STUB - replaced by feature agent"
// files. Delete this file together with the `homePlaceholder*` keys in
// l10n_parts/home.arb once no stub imports it any more.
import 'package:family_hub/core/config/app_config.dart';
import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/network/mock/mock_seed.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/shared/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Temporary screen for a feature that is not built yet: an app bar with
/// [title] and a localized "coming soon" state, optionally with an [action].
class FeaturePlaceholderScreen extends StatelessWidget {
  const FeaturePlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
    this.action,
  });

  final String title;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: ResponsiveCenter(
          child: EmptyState(
            icon: icon,
            title: l10n.homePlaceholderTitle,
            message: l10n.homePlaceholderMessage,
            action: action,
          ),
        ),
      ),
    );
  }
}

/// Signs out through the session controller; the router then returns to
/// the welcome screen.
class PlaceholderSignOutButton extends StatelessWidget {
  const PlaceholderSignOutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return _PlaceholderActionButton(
      label: context.l10n.homePlaceholderSignOut,
      icon: AppIcons.logout,
      variant: AppButtonVariant.secondary,
      action: (ref) => ref.read(sessionControllerProvider.notifier).logout(),
    );
  }
}

/// Mock mode only: signs in with the seeded demo admin
/// ([MockSeed.demoEmail]) so the app shell can be tried before the auth
/// screens exist. Renders nothing against a real API.
class PlaceholderDemoSignInButton extends StatelessWidget {
  const PlaceholderDemoSignInButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.useMockApi) return const SizedBox.shrink();
    return _PlaceholderActionButton(
      label: context.l10n.homePlaceholderDemoSignIn,
      icon: AppIcons.family,
      action: (ref) => ref
          .read(sessionControllerProvider.notifier)
          .login(email: MockSeed.demoEmail, password: MockSeed.demoPassword),
    );
  }
}

/// Button that runs [action] once at a time: shows a spinner while busy,
/// ignores taps meanwhile and reports failures with a localized snackbar.
class _PlaceholderActionButton extends ConsumerStatefulWidget {
  const _PlaceholderActionButton({
    required this.label,
    required this.icon,
    required this.action,
    this.variant = AppButtonVariant.primary,
  });

  final String label;
  final IconData icon;
  final AppButtonVariant variant;
  final Future<void> Function(WidgetRef ref) action;

  @override
  ConsumerState<_PlaceholderActionButton> createState() =>
      _PlaceholderActionButtonState();
}

class _PlaceholderActionButtonState
    extends ConsumerState<_PlaceholderActionButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.action(ref);
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: widget.label,
      icon: widget.icon,
      variant: widget.variant,
      isLoading: _busy,
      expand: false,
      onPressed: _busy ? null : _run,
    );
  }
}
