import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// A dot with a soft pulsing halo: the "live" indicator while a location is
/// shared / an alert is active.
///
/// Static (dot + soft halo) when [animate] is false — e.g. in list tiles
/// that appear on screens which wait for animations to settle — or when the
/// platform asks to reduce motion (`MediaQuery.disableAnimations`).
class SosPulsingDot extends StatefulWidget {
  const SosPulsingDot({
    super.key,
    required this.color,
    this.size = AppSizes.iconXs,
    this.animate = true,
  });

  final Color color;

  /// Diameter of the halo; the dot is half of it.
  final double size;

  final bool animate;

  @override
  State<SosPulsingDot> createState() => _SosPulsingDotState();
}

class _SosPulsingDotState extends State<SosPulsingDot>
    with SingleTickerProviderStateMixin {
  /// Halo phase shown while the dot does not pulse: visible but calm.
  static const double _staticPhase = 0.4;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    // One slow breath: long enough to feel calm, short enough to read "live".
    duration: AppDurations.slow * 3,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SosPulsingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _sync();
  }

  void _sync() {
    final animate = widget.animate && !MediaQuery.disableAnimationsOf(context);
    if (!animate) {
      _controller
        ..stop()
        ..value = _staticPhase;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: 0.5 + t * 0.5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withValues(
                        alpha: (1 - t) * AppColors.scrimOpacity,
                      ),
                    ),
                    child: SizedBox.square(dimension: widget.size),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color,
                  ),
                  child: SizedBox.square(dimension: widget.size / 2),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
