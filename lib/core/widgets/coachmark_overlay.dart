import "package:flutter/material.dart";
import "../theme/app_colors.dart";
import "../../data/models/tour_step.dart";

/// Mirrors Coachmark.jsx — a full-screen walkthrough overlay that spotlights
/// one real on-screen widget at a time (via its GlobalKey) with a gold ring
/// + darkened backdrop, and a floating tooltip bubble (step counter, title,
/// description, Skip / Next·Got it). Tapping anywhere advances to the next
/// step. Meant to be inserted via `Overlay.of(context, rootOverlay: true)`
/// so its own coordinate space is the real screen — matching each target's
/// `RenderBox.localToGlobal` directly, and letting it sit above content
/// that's otherwise width-constrained (e.g. a Drawer panel).
class CoachmarkOverlay extends StatefulWidget {
  const CoachmarkOverlay({super.key, required this.steps, required this.keys, required this.onDone});

  final List<TourStep> steps;
  final Map<String, GlobalKey> keys;
  final VoidCallback onDone;

  @override
  State<CoachmarkOverlay> createState() => _CoachmarkOverlayState();
}

class _CoachmarkOverlayState extends State<CoachmarkOverlay> {
  int _i = 0;
  Rect? _rect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final step = widget.steps.isNotEmpty && _i < widget.steps.length ? widget.steps[_i] : null;
    final key = step != null ? widget.keys[step.key] : null;
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    final next = box != null && box.attached ? (box.localToGlobal(Offset.zero) & box.size) : null;
    if (next != _rect) setState(() => _rect = next);
    // Catches late layout (e.g. drawer sliding in) — same 60ms fallback as
    // the web's setTimeout(measure, 60).
    Future.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      final retryBox = key?.currentContext?.findRenderObject() as RenderBox?;
      final retryRect = retryBox != null && retryBox.attached ? (retryBox.localToGlobal(Offset.zero) & retryBox.size) : null;
      if (retryRect != _rect) setState(() => _rect = retryRect);
    });
  }

  void _advance() {
    if (widget.steps.isEmpty) return;
    if (_i >= widget.steps.length - 1) {
      widget.onDone();
    } else {
      setState(() {
        _i++;
        _rect = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();
    final step = widget.steps[_i];
    final last = _i == widget.steps.length - 1;
    final screen = MediaQuery.of(context).size;
    final rect = _rect;

    const bubbleW = 250.0;
    double top = 0, left = 0;
    if (rect != null) {
      final spaceBelow = screen.height - rect.bottom;
      top = spaceBelow > 150 ? rect.bottom + 12 : rect.top - 132;
      top = top.clamp(10, screen.height - 142);
      left = rect.left.clamp(12, screen.width - bubbleW - 12);
    }

    return GestureDetector(
      onTap: _advance,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _SpotlightPainter(rect: rect)),
            ),
          ),
          if (rect != null)
            Positioned(
              top: top,
              left: left,
              width: bubbleW,
              child: IgnorePointer(
                ignoring: false,
                child: GestureDetector(
                  onTap: () {}, // absorb taps so tapping the bubble itself doesn't also advance via the backdrop
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      border: Border.all(color: AppColors.goldDim),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 8))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("${_i + 1} of ${widget.steps.length}", style: const TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(step.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.txt)),
                        const SizedBox(height: 4),
                        Text(step.desc, style: const TextStyle(fontSize: 12, color: AppColors.mute, height: 1.4)),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: widget.onDone,
                              style: TextButton.styleFrom(foregroundColor: AppColors.mute, padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                              child: const Text("Skip", style: TextStyle(fontSize: 11)),
                            ),
                            ElevatedButton(
                              onPressed: _advance,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.gold,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(last ? "Got it" : "Next", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Punches a rounded-rect hole out of a full-screen dark scrim at [rect],
/// then draws the gold spotlight ring on top — the Flutter-native
/// equivalent of the web's `box-shadow: 0 0 0 9999px …` trick.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.rect});
  final Rect? rect;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = const Color(0xCC060607);
    if (rect == null) {
      canvas.drawRect(Offset.zero & size, scrim);
      return;
    }
    final hole = RRect.fromRectAndRadius(rect!.inflate(6), const Radius.circular(14));
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(hole);
    canvas.drawPath(path, scrim);
    canvas.drawRRect(
      hole,
      Paint()
        ..color = AppColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) => oldDelegate.rect != rect;
}
