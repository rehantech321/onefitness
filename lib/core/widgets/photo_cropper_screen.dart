import "dart:convert";
import "dart:math" as math;
import "dart:typed_data";
import "dart:ui" as ui;

import "package:flutter/foundation.dart" show compute;
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:image/image.dart" as img;
import "../theme/app_colors.dart";

/// Mirrors ImageEditors.jsx's `PhotoCropper` — a full-screen "drag to
/// reposition, pinch/scroll to zoom" circular crop UI shown right after
/// picking a profile photo, so the saved image is centered how the user
/// actually wants it instead of a raw center-crop.
///
/// Returns the cropped photo as a `data:image/jpeg;base64,...` string, or
/// null if the user cancelled.
class PhotoCropperScreen extends StatefulWidget {
  const PhotoCropperScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<PhotoCropperScreen> createState() => _PhotoCropperScreenState();
}

class _PhotoCropperScreenState extends State<PhotoCropperScreen> {
  static const double _circle = 260; // visible crop circle, logical px
  static const double _out = 400; // output image size, px

  double _natW = 0;
  double _natH = 0;
  double _scale = 1;
  Offset _offset = Offset.zero;
  double _startScale = 1;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width.toDouble();
    final h = frame.image.height.toDouble();
    frame.image.dispose();
    if (!mounted) return;
    final fit = math.max(_circle / w, _circle / h);
    setState(() {
      _natW = w;
      _natH = h;
      _scale = fit;
      _offset = Offset.zero;
      _loaded = true;
    });
  }

  Offset _clampOffset(Offset o, double scale) {
    final iw = _natW * scale;
    final ih = _natH * scale;
    final maxX = math.max(0.0, (iw - _circle) / 2);
    final maxY = math.max(0.0, (ih - _circle) / 2);
    return Offset(o.dx.clamp(-maxX, maxX), o.dy.clamp(-maxY, maxY));
  }

  void _applyZoom(double newScale) {
    if (!_loaded) return;
    final sc = newScale.clamp(0.1, 8.0);
    setState(() {
      _scale = sc;
      _offset = _clampOffset(_offset, sc);
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (!_loaded) return;
    final sc = (_startScale * d.scale).clamp(0.1, 8.0);
    setState(() {
      _scale = sc;
      _offset = _clampOffset(_offset + d.focalPointDelta, sc);
    });
  }

  void _onPointerScroll(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _applyZoom(_scale * (1 - event.scrollDelta.dy * 0.002));
    }
  }

  Future<void> _save() async {
    if (!_loaded || _saving) return;
    setState(() => _saving = true);
    // Same math as PhotoCropper.save(): the visible circle covers a
    // (CIRCLE / scale)-wide square of the *original* image, centered on
    // the image's own center and shifted opposite the pan offset.
    final cropSize = _circle / _scale;
    final left = _natW / 2 - (_circle / 2 + _offset.dx) / _scale;
    final top = _natH / 2 - (_circle / 2 + _offset.dy) / _scale;
    final result = await compute(_cropAndEncode, _CropJob(bytes: widget.bytes, left: left, top: top, size: cropSize, out: _out.round()));
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.94),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Position your photo", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 4),
                const Text("Drag to reposition · Pinch or scroll to zoom", style: TextStyle(fontSize: 12, color: AppColors.mute)),
                const SizedBox(height: 20),
                Listener(
                  onPointerSignal: _onPointerScroll,
                  child: GestureDetector(
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    child: Container(
                      width: _circle,
                      height: _circle,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.gold, width: 3), color: Colors.black),
                      clipBehavior: Clip.antiAlias,
                      child: !_loaded
                          ? const Center(child: Text("Loading…", style: TextStyle(color: AppColors.mute, fontSize: 12)))
                          : Stack(
                              children: [
                                Positioned(
                                  left: _circle / 2 - (_natW * _scale) / 2 + _offset.dx,
                                  top: _circle / 2 - (_natH * _scale) / 2 + _offset.dy,
                                  width: _natW * _scale,
                                  height: _natH * _scale,
                                  child: Image.memory(widget.bytes, fit: BoxFit.fill, gaplessPlayback: true),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ZoomButton(icon: Icons.remove, onTap: () => _applyZoom(_scale - 0.15)),
                    SizedBox(width: 52, child: Text(_loaded ? "${(_scale * 100).round()}%" : "—", textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.mute))),
                    _ZoomButton(icon: Icons.add, onTap: () => _applyZoom(_scale + 0.15)),
                  ],
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: math.min(300, MediaQuery.of(context).size.width - 40),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _loaded && !_saving ? _save : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            disabledBackgroundColor: AppColors.line,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: Text(_saving ? "Saving…" : "Use photo", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.mute,
                            side: const BorderSide(color: AppColors.line),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.card, border: Border.fromBorderSide(BorderSide(color: AppColors.line))),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }
}

class _CropJob {
  const _CropJob({required this.bytes, required this.left, required this.top, required this.size, required this.out});
  final Uint8List bytes;
  final double left;
  final double top;
  final double size;
  final int out;
}

/// Runs off the UI isolate (via `compute`) since decoding a full-resolution
/// phone photo can take long enough to visibly stall the "Saving…" state.
String? _cropAndEncode(_CropJob job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) return null;
  final cw = job.size.round().clamp(1, decoded.width);
  final ch = job.size.round().clamp(1, decoded.height);
  final lx = job.left.round().clamp(0, decoded.width - cw);
  final ty = job.top.round().clamp(0, decoded.height - ch);
  final cropped = img.copyCrop(decoded, x: lx, y: ty, width: cw, height: ch);
  final resized = img.copyResize(cropped, width: job.out, height: job.out);
  final jpg = img.encodeJpg(resized, quality: 85);
  return "data:image/jpeg;base64,${base64Encode(jpg)}";
}
