import "dart:convert";
import "dart:typed_data";
import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../theme/app_colors.dart";

/// Renders a product photo stored as a base64 data URL (same convention as
/// progress photos). Decoding is memoised per instance because a shop grid
/// rebuilds constantly while scrolling, and re-decoding a full-size image on
/// every frame is what makes such a grid stutter.
///
/// Falls back to a neutral placeholder rather than an error box: a product
/// with a missing or corrupt photo should still be shoppable.
class ProductPhoto extends StatefulWidget {
  const ProductPhoto({super.key, required this.dataUrl, this.width, this.height, this.fit = BoxFit.cover});

  final String? dataUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  State<ProductPhoto> createState() => _ProductPhotoState();
}

class _ProductPhotoState extends State<ProductPhoto> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant ProductPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataUrl != widget.dataUrl) _decode();
  }

  void _decode() {
    final raw = widget.dataUrl;
    if (raw == null || raw.isEmpty) {
      _bytes = null;
      return;
    }
    try {
      final comma = raw.indexOf(",");
      _bytes = base64Decode(comma >= 0 ? raw.substring(comma + 1) : raw);
    } catch (_) {
      _bytes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: AppColors.card,
        alignment: Alignment.center,
        child: const Icon(LucideIcons.image, size: 20, color: AppColors.line),
      );
    }
    return Image.memory(
      bytes,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) => Container(
        width: widget.width,
        height: widget.height,
        color: AppColors.card,
        alignment: Alignment.center,
        child: const Icon(LucideIcons.image, size: 20, color: AppColors.line),
      ),
    );
  }
}
