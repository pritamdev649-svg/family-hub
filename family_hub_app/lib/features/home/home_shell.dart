import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/settings/text_scale.dart';
import 'package:family_hub/core/widgets/offline_banner.dart';
import 'package:family_hub/features/home/widgets/app_nav_bar.dart';
import 'package:family_hub/features/home/widgets/top_banner_slot.dart';
import 'package:family_hub/features/settings/application/background_sync.dart';
import 'package:family_hub/features/sos/presentation/widgets/sos_status_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The signed-in app frame: the SOS status banner and the offline banner on
/// top, the current tab in the middle and the bottom [AppNavBar]
/// (Home / Tasks / SOS / Money / More). Tab order matches `AppRoutes.tabs`
/// and the router's branches.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _homeIndex = 0;

  void _onDestinationSelected(int index) {
    // Re-selecting the current tab pops it back to its root screen.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps "always share" location fresh while the app is in use.
    ref.watch(backgroundSyncProvider);

    final l10n = context.l10n;
    final currentIndex = navigationShell.currentIndex;

    return PopScope(
      // Android back on another tab's root goes to Home instead of exiting.
      canPop: currentIndex == _homeIndex,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onDestinationSelected(_homeIndex);
      },
      child: Scaffold(
        body: Builder(
          builder: (context) {
            // The floating nav bar hovers over the content, which scrolls
            // behind it. Tab screens get the bar's height as bottom padding
            // *and* view padding, so scroll views, FABs and snack bars all
            // stay clear of it automatically.
            final mq = MediaQuery.of(context);
            final navSpace = AppNavBar.occupiedHeight(context);
            return Stack(
              children: [
                MediaQuery(
                  data: mq.copyWith(
                    padding: mq.padding.copyWith(bottom: navSpace),
                    viewPadding: mq.viewPadding.copyWith(bottom: navSpace),
                  ),
                  child: TopBannerSlot(
                    // Both collapse to zero height when idle. An active SOS
                    // matters most, so it sits above the offline notice.
                    banner: const Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [SosStatusBanner(), OfflineBanner()],
                    ),
                    child: navigationShell,
                  ),
                ),
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  bottom: 0,
                  // Labels are short fixed chrome: cap their scale so they
                  // never overflow the bar at the largest text settings.
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: AppTextScale.largeTextMin,
                    child: AppNavBar(
                      selectedIndex: currentIndex,
                      onSelected: _onDestinationSelected,
                      destinations: [
                        AppNavDestination(
                          icon: AppIcons.home,
                          label: l10n.navHome,
                        ),
                        AppNavDestination(
                          icon: AppIcons.tasks,
                          label: l10n.navTasks,
                        ),
                        AppNavDestination(
                          icon: AppIcons.sos,
                          label: l10n.navSos,
                          tooltip: l10n.navSosTooltip,
                          isSos: true,
                        ),
                        AppNavDestination(
                          icon: AppIcons.money,
                          label: l10n.navMoney,
                        ),
                        AppNavDestination(
                          icon: AppIcons.more,
                          label: l10n.navMore,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
