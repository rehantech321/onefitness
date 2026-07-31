import "package:flutter/material.dart";
import "../../../core/theme/app_colors.dart";
import "nutrition_tab.dart";
import "workout_tab.dart";

/// Mirrors ClientPlans (ClientNutritionEditor.jsx) — a two-tab view: Workout
/// Program and Nutrition Program.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  String _tab = "workout";

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(
            children: [
              _TabButton(label: "Workout Program", selected: _tab == "workout", onTap: () => setState(() => _tab = "workout")),
              _TabButton(label: "Nutrition Program", selected: _tab == "nutrition", onTap: () => setState(() => _tab = "nutrition")),
            ],
          ),
        ),
        Expanded(child: _tab == "workout" ? const WorkoutTab() : const NutritionTab()),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? AppColors.gold : Colors.transparent, width: 2)),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? AppColors.gold : AppColors.mute),
          ),
        ),
      ),
    );
  }
}
