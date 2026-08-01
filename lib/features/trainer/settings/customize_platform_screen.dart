import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/platform_settings_provider.dart";

const _tabs = [("scheduling", "Scheduling"), ("coaches", "Coaches"), ("clients", "Clients"), ("payments", "Payments"), ("workouts", "Workouts")];

/// Mirrors CustomizePlatform.jsx (owner-only) — 5 tabs of gym-wide config.
/// Trimmed to a representative subset of each tab's settings (the source
/// ships ~30 fields total, several of which — custom profile fields, a
/// full payment-fee-structure builder — don't feed any other screen in
/// this port and would be inert toggles).
class CustomizePlatformScreen extends ConsumerStatefulWidget {
  const CustomizePlatformScreen({super.key});

  @override
  ConsumerState<CustomizePlatformScreen> createState() => _CustomizePlatformScreenState();
}

class _CustomizePlatformScreenState extends ConsumerState<CustomizePlatformScreen> {
  String _tab = "scheduling";

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(platformSettingsProvider);
    void update(PlatformSettings Function(PlatformSettings) f) => ref.read(platformSettingsProvider.notifier).update(f);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          child: SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _tabs.map((t) {
                final selected = _tab == t.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () => setState(() => _tab = t.$1),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card, border: Border.all(color: selected ? AppColors.gold : AppColors.line), borderRadius: BorderRadius.circular(16)),
                      child: Text(t.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? AppColors.gold : AppColors.mute)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_tab == "scheduling") ...[
                  _NumberRow(label: "Late cancellation window (hours)", value: settings.lateCancellationHours, onChange: (v) => update((s) => s.copyWith(lateCancellationHours: v))),
                  _NumberRow(label: "Max booking horizon (days)", value: settings.maxBookingHorizonDays, onChange: (v) => update((s) => s.copyWith(maxBookingHorizonDays: v))),
                  _NumberRow(label: "Min booking lead time (hours)", value: settings.minBookingLeadHours, onChange: (v) => update((s) => s.copyWith(minBookingLeadHours: v))),
                  _NumberRow(label: "Semi-private capacity", value: settings.semiPrivateCap, onChange: (v) => update((s) => s.copyWith(semiPrivateCap: v))),
                ],
                if (_tab == "coaches") ...[
                  _ChoiceRow(label: "Two-factor requirement", value: settings.twoFactorRequirement, options: const [("off", "Off"), ("staff", "Staff"), ("everyone", "Everyone")], onChange: (v) => update((s) => s.copyWith(twoFactorRequirement: v))),
                  _ChoiceRow(label: "Coach client scope", value: settings.coachClientScope, options: const [("own", "Own clients only"), ("all", "All clients")], onChange: (v) => update((s) => s.copyWith(coachClientScope: v))),
                  _ToggleRow(label: "Coaches can view revenue", value: settings.coachCanViewRevenue, onChange: (v) => update((s) => s.copyWith(coachCanViewRevenue: v))),
                  _ToggleRow(label: "Coaches can see other schedules", value: settings.coachCanSeeOtherSchedules, onChange: (v) => update((s) => s.copyWith(coachCanSeeOtherSchedules: v))),
                  _ToggleRow(label: "Coaches can edit client workouts", value: settings.coachCanEditClientWorkouts, onChange: (v) => update((s) => s.copyWith(coachCanEditClientWorkouts: v))),
                ],
                if (_tab == "clients") ...[
                  _ToggleRow(label: "Require waiver at signup", value: settings.requireWaiverAtSignup, onChange: (v) => update((s) => s.copyWith(requireWaiverAtSignup: v))),
                  _ToggleRow(label: "Clients can message any coach", value: settings.clientsCanMessageAnyCoach, onChange: (v) => update((s) => s.copyWith(clientsCanMessageAnyCoach: v))),
                  _ChoiceRow(label: "Message identity", value: settings.messageIdentity, options: const [("self", "From the coach"), ("business", "From the business")], onChange: (v) => update((s) => s.copyWith(messageIdentity: v))),
                ],
                if (_tab == "payments") ...[
                  _ToggleRow(label: "Card processing fee enabled", value: settings.processingFeeEnabled, onChange: (v) => update((s) => s.copyWith(processingFeeEnabled: v))),
                  if (settings.processingFeeEnabled) _NumberRow(label: "Fee percent", value: settings.feePercent.toInt(), onChange: (v) => update((s) => s.copyWith(feePercent: v))),
                ],
                if (_tab == "workouts") ...[
                  _ToggleRow(label: "Auto carry over last weight", value: settings.autoCarryOverLastWeight, onChange: (v) => update((s) => s.copyWith(autoCarryOverLastWeight: v))),
                  _ChoiceRow(label: "Default weight unit", value: settings.defaultWeightUnit, options: const [("lb", "lb"), ("kg", "kg")], onChange: (v) => update((s) => s.copyWith(defaultWeightUnit: v))),
                  _ToggleRow(label: "Clients can swap exercises", value: settings.clientsCanSwapExercises, onChange: (v) => update((s) => s.copyWith(clientsCanSwapExercises: v))),
                  const SizedBox(height: 4),
                  FieldLabeled(label: "Business name", child: AppField(controller: TextEditingController(text: settings.businessName), onChanged: (v) => update((s) => s.copyWith(businessName: v)))),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.label, required this.value, required this.onChange});
  final String label;
  final bool value;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => onChange(!value),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          Icon(value ? LucideIcons.toggleRight : LucideIcons.toggleLeft, size: 30, color: value ? AppColors.gold : AppColors.mute),
        ],
      ),
    );
  }
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({required this.label, required this.value, required this.onChange});
  final String label;
  final int value;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          SizedBox(
            width: 70,
            child: AppField(controller: TextEditingController(text: "$value"), keyboardType: TextInputType.number, onChanged: (v) => onChange(int.tryParse(v) ?? value)),
          ),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.label, required this.value, required this.options, required this.onChange});
  final String label;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: options.map((o) {
              final selected = value == o.$1;
              return InkWell(
                onTap: () => onChange(o.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg, border: Border.all(color: selected ? AppColors.gold : AppColors.line), borderRadius: BorderRadius.circular(7)),
                  child: Text(o.$2, style: TextStyle(fontSize: 11, color: selected ? AppColors.gold : AppColors.txt)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
