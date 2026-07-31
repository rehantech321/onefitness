import "dart:io";
import "package:flutter/material.dart";
import "../theme/app_colors.dart";

/// Mirrors FormPrimitives.jsx `Avatar` — circular photo or initials fallback,
/// with a gold ring when `active` is true.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    this.src,
    required this.name,
    this.size = 32,
    this.active = false,
  });

  final String? src;
  final String name;
  final double size;
  final bool active;

  String get _initials {
    final words = name.trim().isEmpty ? ["?"] : name.trim().split(RegExp(r"\s+"));
    return words.take(2).map((w) => w.isNotEmpty ? w[0] : "").join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = active ? AppColors.gold : AppColors.line;
    final decoration = BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: borderColor, width: 1.5),
      color: AppColors.gold.withValues(alpha: 0.15),
    );

    if (src != null && src!.isNotEmpty) {
      ImageProvider provider;
      if (src!.startsWith("http")) {
        provider = NetworkImage(src!);
      } else {
        provider = FileImage(File(src!));
      }
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 1.5),
          image: DecorationImage(image: provider, fit: BoxFit.cover),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: decoration,
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          color: AppColors.gold,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.38,
        ),
      ),
    );
  }
}
