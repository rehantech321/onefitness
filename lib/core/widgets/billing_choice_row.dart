import "package:flutter/material.dart";
import "../theme/app_colors.dart";

/// A two-option Yes/No picker for "will this Squad share a membership or
/// session package?" — shared by the client's create-squad form
/// (squad_dashboard_screen.dart) and the coach's (squad_tab.dart), since
/// both need the exact same explicit, no-default choice. [value] is null
/// until the user picks — callers should gate their confirm button on
/// that, not assume a default.
class BillingChoiceRow extends StatelessWidget {
  const BillingChoiceRow({super.key, required this.value, required this.onChanged});

  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _Option(label: "Yes", selected: value == true, onTap: () => onChanged(true))),
        const SizedBox(width: 8),
        Expanded(child: _Option(label: "No", selected: value == false, onTap: () => onChanged(false))),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.gold.withValues(alpha: 0.12) : AppColors.card,
          border: Border.all(color: selected ? AppColors.gold : AppColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? AppColors.gold : AppColors.mute),
        ),
      ),
    );
  }
}
