import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Places a (possibly empty) [banner] above [child] and hands the top system
/// inset (status bar / notch) to whichever of the two is at the top:
///
/// * banner hidden (zero height) -> [child] keeps the inset, so the tab's
///   `AppBar` extends under the status bar as usual;
/// * banner visible -> the slot pads the banner below the status bar and
///   removes the top inset from [child], so the tab's `AppBar` does not add a
///   second status-bar gap under the banner.
///
/// The banner is measured after layout; the switch happens one frame later.
/// The widget tree shape never changes, so [child]'s state (e.g. the tab
/// navigators) is preserved when the banner appears or disappears.
class TopBannerSlot extends StatefulWidget {
  const TopBannerSlot({super.key, required this.banner, required this.child});

  final Widget banner;
  final Widget child;

  @override
  State<TopBannerSlot> createState() => _TopBannerSlotState();
}

class _TopBannerSlotState extends State<TopBannerSlot> {
  bool _bannerVisible = false;

  void _onBannerHeight(double height) {
    final visible = height > 0;
    if (mounted && visible != _bannerVisible) {
      setState(() => _bannerVisible = visible);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(top: _bannerVisible ? topInset : 0),
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: _HeightReporter(
              onHeight: _onBannerHeight,
              child: widget.banner,
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: _bannerVisible,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

/// Reports its child's laid-out height (after the frame) whenever it changes.
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightReporter renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _lastHeight;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _lastHeight) return;
    _lastHeight = height;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onHeight(height);
    });
  }
}
