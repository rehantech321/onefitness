import "package:flutter/material.dart";

/// Wraps [child] with a subtle scale-down-on-press effect. Uses a [Listener]
/// rather than a [GestureDetector] so it never competes in the gesture arena
/// — whatever tap handling [child] already does (InkWell, ElevatedButton,
/// AppCard's own GestureDetector, ...) keeps working exactly as before; this
/// widget only ever observes pointer events, it never claims them.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.scale = 0.97});

  final Widget child;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
