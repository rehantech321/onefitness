import "dart:math" as math;
import "package:flutter/material.dart";
import "../theme/app_colors.dart";

/// Mirrors GymCitizenProgressRing.jsx — staged progress message for the
/// Gym Citizen sub-badge count.
String? gymCitizenProgressMessage(int activeCount) {
  if (activeCount >= 10) return null;
  if (activeCount == 9) return "One More!";
  if (activeCount == 8) return "Almost There";
  if (activeCount >= 5) return "Keep Going";
  if (activeCount >= 1) return "Getting There";
  return "Get Started";
}

/// Mirrors GymCitizenProgressLabel.jsx.
class GymCitizenProgressLabel extends StatelessWidget {
  const GymCitizenProgressLabel({super.key, required this.activeCount});
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    if (activeCount >= 10) return const SizedBox.shrink();
    final msg = gymCitizenProgressMessage(activeCount);
    return Text("$msg · $activeCount/10", style: const TextStyle(fontSize: 11, color: AppColors.mute));
  }
}

/// Mirrors GymCitizenProgressRing.jsx — a circular progress ring around
/// [child] (typically badge artwork), filling clockwise from 12 o'clock.
class GymCitizenProgressRing extends StatelessWidget {
  const GymCitizenProgressRing({super.key, required this.activeCount, this.total = 10, this.size = 56, this.child});

  final int activeCount;
  final int total;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final pct = (math.min(total, activeCount) / total).clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(pct: pct),
          ),
          if (child != null) Padding(padding: const EdgeInsets.all(6), child: child),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.pct});
  final double pct;
  static const _stroke = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - _stroke) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final bg = Paint()
      ..color = AppColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    canvas.drawCircle(center, radius, bg);
    if (pct <= 0) return;
    final fg = Paint()
      ..color = AppColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, 2 * math.pi * pct, false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.pct != pct;
}
