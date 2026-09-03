import "dart:convert";
import "dart:typed_data";
import "dart:ui" as ui;
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "../theme/app_colors.dart";
import "app_buttons.dart";

class _Stroke {
  _Stroke(this.points);
  final List<Offset> points;
}

/// Freehand draw-or-type capture for an initials/signature box — Variable &
/// Signature Capture spec §3 ("draw once, reuse everywhere"): either mode
/// rasterizes to a PNG data URL so every capture (drawn or typed) is stored
/// the same way. [onCaptured] fires with that data URL, or null while the
/// pad is empty/cleared.
class SignaturePad extends StatefulWidget {
  const SignaturePad({
    super.key,
    required this.onCaptured,
    this.height = 140,
    this.initialTypedText,
  });

  final ValueChanged<String?> onCaptured;
  final double height;
  final String? initialTypedText;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final _repaintKey = GlobalKey();
  final _strokes = <_Stroke>[];
  bool _typedMode = false;
  late final TextEditingController _typedController = TextEditingController(text: widget.initialTypedText ?? "");

  bool get _hasContent => _typedMode ? _typedController.text.trim().isNotEmpty : _strokes.isNotEmpty;

  void _clear() {
    setState(() {
      _strokes.clear();
      _typedController.clear();
    });
    widget.onCaptured(null);
  }

  Future<void> _capture() async {
    if (!_hasContent) {
      widget.onCaptured(null);
      return;
    }
    // A frame must land after the last draw/type update before the
    // RepaintBoundary reflects it — schedule the capture just after.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final b64 = base64Encode(bytes.buffer.asUint8List());
      if (mounted) widget.onCaptured("data:image/png;base64,$b64");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepaintBoundary(
          key: _repaintKey,
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line),
            ),
            child: _typedMode
                ? Center(
                    child: TextField(
                      controller: _typedController,
                      textAlign: TextAlign.center,
                      onChanged: (_) {
                        setState(() {});
                        _capture();
                      },
                      style: const TextStyle(
                        fontFamily: "cursive",
                        fontStyle: FontStyle.italic,
                        fontSize: 28,
                        color: Colors.black,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "Type your name",
                        hintStyle: TextStyle(fontSize: 16, color: Colors.black38),
                      ),
                    ),
                  )
                : GestureDetector(
                    onPanStart: (d) => setState(() => _strokes.add(_Stroke([d.localPosition]))),
                    onPanUpdate: (d) => setState(() => _strokes.last.points.add(d.localPosition)),
                    onPanEnd: (_) => _capture(),
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _SignaturePainter(_strokes),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() {
                _typedMode = !_typedMode;
                _strokes.clear();
                _typedController.clear();
              }),
              child: Text(_typedMode ? "Draw instead" : "Type instead", style: const TextStyle(fontSize: 12)),
            ),
            const Spacer(),
            if (_hasContent)
              OutlinedButton(
                onPressed: _clear,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
                child: const Text("Clear and redraw", style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.strokes);
  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      for (var i = 0; i < stroke.points.length - 1; i++) {
        canvas.drawLine(stroke.points[i], stroke.points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

/// Compact preview of an already-captured signature/initials image, with a
/// "Change" action — used once a document has an adopted image on file so
/// the client doesn't have to redraw every time (still requires a fresh tap
/// to confirm placement per document — see WaiverInitialTapRow).
class AdoptedSignaturePreview extends StatelessWidget {
  const AdoptedSignaturePreview({super.key, required this.imageDataUrl, required this.onChange, this.height = 70});
  final String imageDataUrl;
  final VoidCallback onChange;
  final double height;

  @override
  Widget build(BuildContext context) {
    final b64 = imageDataUrl.split(",").last;
    final bytes = base64Decode(b64);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
      child: Row(
        children: [
          Expanded(child: SizedBox(height: height, child: Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain))),
          const SizedBox(width: 8),
          BtnGhost(onPressed: onChange, child: const Text("Change")),
        ],
      ),
    );
  }
}
