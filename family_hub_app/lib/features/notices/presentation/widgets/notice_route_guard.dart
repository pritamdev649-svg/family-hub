import 'package:flutter/widgets.dart';

/// Whether the route showing [context] is the top-most one.
///
/// A second tap that lands while the sheet, dialog or page opened by the
/// first tap is still animating in must not open it again (two forms, two
/// sheets, two photo viewers). Call it before opening anything from the
/// notice board.
bool isNoticeRouteCurrent(BuildContext context) =>
    ModalRoute.of(context)?.isCurrent ?? true;
