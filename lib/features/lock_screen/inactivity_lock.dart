import 'dart:async';

import 'package:flutter/material.dart';

/// Locks the app after a period without pointer or keyboard activity.
class InactivityLock extends StatefulWidget {
  const InactivityLock({
    super.key,
    required this.enabled,
    required this.onTimeout,
    required this.child,
    this.timeout = const Duration(minutes: 5),
  });

  final bool enabled;
  final VoidCallback onTimeout;
  final Widget child;
  final Duration timeout;

  @override
  State<InactivityLock> createState() => _InactivityLockState();
}

class _InactivityLockState extends State<InactivityLock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleTimeout();
  }

  @override
  void didUpdateWidget(covariant InactivityLock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _timer?.cancel();
      _timer = null;
    } else if (!oldWidget.enabled || oldWidget.timeout != widget.timeout) {
      _scheduleTimeout();
    }
  }

  void _registerActivity() {
    if (widget.enabled) _scheduleTimeout();
  }

  void _scheduleTimeout() {
    _timer?.cancel();
    if (!widget.enabled) return;

    _timer = Timer(widget.timeout, () {
      _timer = null;
      if (mounted && widget.enabled) widget.onTimeout();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (_, event) {
        _registerActivity();
        return KeyEventResult.ignored;
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _registerActivity(),
        onPointerMove: (_) => _registerActivity(),
        onPointerHover: (_) => _registerActivity(),
        onPointerSignal: (_) => _registerActivity(),
        child: widget.child,
      ),
    );
  }
}
