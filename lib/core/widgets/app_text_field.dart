import "package:flutter/material.dart";
import "../theme/app_colors.dart";

/// Mirrors FormPrimitives.jsx `Field` — dark bordered text input.
class AppField extends StatelessWidget {
  const AppField({
    super.key,
    this.controller,
    this.placeholder,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final int? minLines;
  final int? maxLines;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final singleLine = (maxLines ?? 1) == 1;
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onChanged: onChanged,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      // Ways out of the keyboard, since a phone/number pad has no return
      // key on iOS: tapping anywhere outside the field closes it, and so
      // does the keyboard's own Done/return key on a single-line field.
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      textInputAction: singleLine ? TextInputAction.done : null,
      onSubmitted: singleLine ? (_) => FocusManager.instance.primaryFocus?.unfocus() : null,
      buildCounter: maxLength == null ? null : (context, {required currentLength, required isFocused, maxLength}) => null,
      style: const TextStyle(color: AppColors.txt, fontSize: 14),
      cursorColor: AppColors.gold,
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: const TextStyle(color: AppColors.mute, fontSize: 14),
        filled: true,
        fillColor: AppColors.bg,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
      ),
    );
  }
}

/// Mirrors FormPrimitives.jsx `FieldLabeled` — small muted label above a field.
class FieldLabeled extends StatelessWidget {
  const FieldLabeled({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.mute, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}
