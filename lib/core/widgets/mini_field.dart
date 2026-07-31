import "package:flutter/material.dart";
import "../theme/app_colors.dart";

/// Mirrors FormPrimitives.jsx `MiniField` — a small labeled input used in
/// compact grids (calorie budget boxes, squad payment minimums).
class MiniField extends StatelessWidget {
  const MiniField({super.key, required this.label, required this.value, required this.onChange, this.ph});

  final String label;
  final String value;
  final ValueChanged<String> onChange;
  final String? ph;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.mute, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        const SizedBox(height: 3),
        TextField(
          controller: TextEditingController(text: value)..selection = TextSelection.collapsed(offset: value.length),
          onChanged: onChange,
          style: const TextStyle(color: AppColors.txt, fontSize: 13),
          decoration: InputDecoration(
            hintText: ph,
            hintStyle: const TextStyle(color: AppColors.mute),
            filled: true,
            fillColor: AppColors.bg,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.gold)),
          ),
        ),
      ],
    );
  }
}
