import "package:flutter/material.dart";
import "../theme/app_colors.dart";
import "app_text_field.dart";

/// Mirrors FormPrimitives.jsx `MiniField` — a small labeled input used in
/// compact grids (calorie budget boxes, squad payment minimums).
///
/// These boxes are nearly always numeric — sets, reps, calories, macros,
/// dollar minimums — so [kind] defaults to [FieldKind.decimal] and they
/// raise a number pad. The few that take a unit along with the number
/// ("30s", "1 mi") pass [FieldKind.measure] instead, which keeps letters
/// available.
class MiniField extends StatelessWidget {
  const MiniField({
    super.key,
    required this.label,
    required this.value,
    required this.onChange,
    this.ph,
    this.kind = FieldKind.decimal,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChange;
  final String? ph;
  final FieldKind kind;

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
          keyboardType: keyboardForKind(kind),
          textCapitalization: capitalizationForKind(kind),
          autocorrect: autocorrectForKind(kind),
          enableSuggestions: autocorrectForKind(kind),
          inputFormatters: formattersForKind(kind),
          // A number pad has no return key on iOS, so tapping outside is
          // the way out of it.
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
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
