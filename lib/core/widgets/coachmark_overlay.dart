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
    final media = MediaQuery.of(context);
    final screen = media.size;
    final rect = _rect;
    // Width follows the screen (narrow phones get nearly full width, big ones
    // stop at 320) instead of a fixed 250 that cramped the text.
    final bubbleW = (screen.width - 24).clamp(220.0, 320.0);
    // The box must stay inside what's actually visible — clear of the
    // notch/status bar and the iPhone home bar — or its border gets cut.
    final safe = media.padding;

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
            Positioned.fill(
              child: CustomSingleChildLayout(
                // Positioned from the box's real measured height, not a
                // guessed one — a longer description made the old fixed
                // estimate place it partly off the bottom of the screen.
                delegate: _BubbleLayout(target: rect, width: bubbleW, safe: safe),
                child: IgnorePointer(
                ignoring: false,
                child: GestureDetector(
                  onTap: () {}, // absorb taps so tapping the bubble itself doesn't also advance via the backdrop
                  child: Container(
                    constraints: BoxConstraints(maxHeight: screen.height - safe.top - safe.bottom - 24),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      border: Border.all(color: AppColors.goldDim),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 8))],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("${_i + 1} of ${widget.steps.length}", style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
                        const SizedBox(height: 6),
                        // Grows with each step — short on the first, full on
                        // the last — so it's clear how far through the tour is.
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (_i + 1) / widget.steps.length,
                            minHeight: 4,
                            backgroundColor: AppColors.line,
                            valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(step.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white, decoration: TextDecoration.none)),
                        const SizedBox(height: 4),
                        Text(step.desc, style: const TextStyle(fontSize: 12, color: Colors.white, height: 1.4, decoration: TextDecoration.none)),
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
              ),
            ),
        ],
      ),
    );
  }
}

/// Places the bubble below the spotlighted widget when it fits, otherwise
/// above it, using the bubble's real laid-out size, and always keeps all
/// four edges inside the safe area.
class _BubbleLayout extends SingleChildLayoutDelegate {
  _BubbleLayout({required this.target, required this.width, required this.safe});
  final Rect target;
  final double width;
  final EdgeInsets safe;

  static const _gap = 12.0;
  static const _margin = 12.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(minWidth: width, maxWidth: width, maxHeight: constraints.maxHeight);

  @override
  Offset getPositionForChild(Size size, Size child) {
    final minTop = safe.top + _margin;
    final maxTop = size.height - safe.bottom - _margin - child.height;
    final below = target.bottom + _gap;
    final above = target.top - _gap - child.height;
    final fitsBelow = below + child.height <= size.height - safe.bottom - _margin;
    var top = fitsBelow ? below : above;
    top = top.clamp(minTop, maxTop < minTop ? minTop : maxTop);
    final left = target.left.clamp(_margin, size.width - width - _margin);
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(covariant _BubbleLayout old) => old.target != target || old.width != width || old.safe != safe;
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
