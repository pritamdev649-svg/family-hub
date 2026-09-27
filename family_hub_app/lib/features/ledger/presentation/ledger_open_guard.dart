import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Stops rapid repeated taps from opening the same screen or sheet twice
/// (e.g. a double tap on a goal card pushing two detail screens).
///
/// A tap is ignored while
/// * an earlier open from this widget is still being processed (until the
///   end of the next frame — go_router adds pushed pages on that frame), or
/// * this widget's route is covered by another route (a sheet or dialog is
///   open, or a pushed page is still animating in).
///
/// No timers are involved, and the guard never waits for the opened route
/// to close: go_router only completes a push future on pop, so a guard
/// waiting for it would stay locked after a `go`.
mixin LedgerOpenGuard<T extends StatefulWidget> on State<T> {
  bool _opening = false;

  /// Runs [open] (a `push` / `show…Sheet` call) unless the tap should be
  /// ignored. Returns whether it ran.
  bool guardedOpen(VoidCallback open) {
    if (_opening || !mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    _opening = true;
    final scheduler = SchedulerBinding.instance;
    scheduler.addPostFrameCallback((_) => _opening = false);
    scheduler.ensureVisualUpdate();
    open();
    return true;
  }
}
