import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/features/sos/application/sos_runtime.dart';

/// Rebuilds [builder] every [interval] with the current time (countdowns,
/// "updated 5 seconds ago"). Stops ticking while [enabled] is false or the
/// widget is not visible (e.g. covered by another route).
class SosTicker extends ConsumerStatefulWidget {
  const SosTicker({
    super.key,
    required this.builder,
    this.interval = everySecond,
    this.enabled = true,
  });

  /// Default tick: countdowns and "5 seconds ago" change every second.
  static const Duration everySecond = Duration(seconds: 1);

  final Widget Function(BuildContext context, DateTime now) builder;
  final Duration interval;
  final bool enabled;

  @override
  ConsumerState<SosTicker> createState() => _SosTickerState();
}

class _SosTickerState extends ConsumerState<SosTicker> {
  Timer? _timer;
  ValueListenable<bool>? _tickerMode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mode = TickerMode.getNotifier(context);
    if (!identical(mode, _tickerMode)) {
      _tickerMode?.removeListener(_sync);
      _tickerMode = mode..addListener(_sync);
    }
    _sync();
  }

  @override
  void didUpdateWidget(SosTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval != widget.interval) _timer?.cancel();
    if (oldWidget.interval != widget.interval ||
        oldWidget.enabled != widget.enabled) {
      _timer = null;
      _sync();
    }
  }

  void _sync() {
    final run = widget.enabled && (_tickerMode?.value ?? true);
    if (!run) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tickerMode?.removeListener(_sync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, ref.read(sosClockProvider)());
}
