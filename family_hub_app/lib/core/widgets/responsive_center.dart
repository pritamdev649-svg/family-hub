import 'package:flutter/widgets.dart';

import 'package:family_hub/core/design/design.dart';

/// Caps content at [maxWidth] and centres it horizontally (tablets,
/// landscape, desktop). On phones the child simply fills the width.
///
/// Every screen body is wrapped in it:
/// `body: ResponsiveCenter(child: AsyncValueView(...))`.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = AppSizes.maxContentWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
