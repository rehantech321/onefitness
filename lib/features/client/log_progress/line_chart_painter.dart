import "package:flutter/material.dart";

/// One series (a list of y-values, already aligned to a shared x-axis) to
/// draw as a polyline — mirrors the inline SVG `<polyline>` charts in
/// LogProgressPage.jsx (no charting package needed for a few line series).
class ChartSeries {
  const ChartSeries({required this.values, required this.color});
  final List<double?> values; // null = no data point at that x position
  final Color color;
}

class LineChartPainter extends CustomPainter {
  const LineChartPainter({required this.series, required this.minY, required this.maxY});

  final List<ChartSeries> series;
  final double minY;
  final double maxY;

  @override
  void paint(Canvas canvas, Size size) {
    final range = (maxY - minY).abs() < 0.0001 ? 1.0 : (maxY - minY);
    for (final s in series) {
      final points = <Offset>[];
      final n = s.values.length;
      for (var i = 0; i < n; i++) {
        final v = s.values[i];
        if (v == null) continue;
        final x = n > 1 ? (i / (n - 1)) * size.width : size.width / 2;
        final y = size.height - ((v - minY) / range) * size.height;
        points.add(Offset(x, y));
      }
      if (points.length < 2) continue;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant LineChartPainter oldDelegate) =>
      oldDelegate.series != series || oldDelegate.minY != minY || oldDelegate.maxY != maxY;
}
