import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/habit_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/client_providers.dart";

/// Mirrors HabitTrackerPage.jsx (client-facing view) — streak/weekly-score
/// header, a Today/Yesterday toggle, tappable habit rows, and an
/// energy/motivation daily check-in.
class HabitTrackerScreen extends ConsumerStatefulWidget {
  const HabitTrackerScreen({super.key});

  @override
  ConsumerState<HabitTrackerScreen> createState() => _HabitTrackerScreenState();
}

class _HabitTrackerScreenState extends ConsumerState<HabitTrackerScreen> {
  late String _dateTab = isoToday();

  void _toggle(String habitId) {
    final canEdit = _dateTab == isoToday() || _dateTab == yesterdayIso();
    if (!canEdit) return;
    ref.read(clientRecordProvider.notifier).update((r) {
      final log = getHabitLog(r, _dateTab);
      final nextChecked = {...log.checked, habitId: !(log.checked[habitId] ?? false)};
      final nextMap = {...r.habitLogByDate, _dateTab: log.copyWith(checked: nextChecked)};
      return r.copyWith(habitLogByDate: nextMap);
    });
  }

  void _setRating(String field, int value) {
    ref.read(clientRecordProvider.notifier).update((r) {
      final log = getHabitLog(r, _dateTab);
      final next = field == "energy" ? log.copyWith(energy: value) : log.copyWith(motivation: value);
      final nextMap = {...r.habitLogByDate, _dateTab: next};
      return r.copyWith(habitLogByDate: nextMap);
    });
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(clientRecordProvider);
    final habits = getClientHabits(client);

    if (habits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text("\u{1F525}", style: TextStyle(fontSize: 32)),
              SizedBox(height: 10),
              Text("No habits yet", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              SizedBox(height: 6),
              Text(
                "Your coach hasn't set up any habits for you to track yet. Once they do, they'll show up here.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.mute, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    final log = getHabitLog(client, _dateTab);
    final canEdit = _dateTab == isoToday() || _dateTab == yesterdayIso();
    final streak = habitStreak(client);
    final weekScore = weeklyConsistencyScore(client);
    final doneToday = habits.where((h) => log.checked[h.id] == true).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatBox(value: "$streak", label: "Day Streak", color: AppColors.grn),
              const SizedBox(width: 8),
              _StatBox(value: "$weekScore%", label: "Weekly Score", color: AppColors.gold),
              const SizedBox(width: 8),
              _StatBox(value: "$doneToday/${habits.length}", label: "Today", color: AppColors.txt),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _DateTabButton(
                  label: "Today",
                  selected: _dateTab == isoToday(),
                  onTap: () => setState(() => _dateTab = isoToday()),
                ),
                _DateTabButton(
                  label: "Yesterday",
                  selected: _dateTab == yesterdayIso(),
                  onTap: () => setState(() => _dateTab = yesterdayIso()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionLabel("Habits — ${_niceDate(_dateTab)}"),
          ...habits.map((h) {
            final done = log.checked[h.id] == true;
            return InkWell(
              onTap: canEdit ? () => _toggle(h.id) : null,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: done ? AppColors.grn.withValues(alpha: 0.08) : AppColors.card,
                  border: Border.all(color: done ? AppColors.grn : AppColors.line),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Text(h.emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        h.label,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: done ? AppColors.grn : AppColors.txt),
                      ),
                    ),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: done ? AppColors.grn : Colors.transparent,
                        border: Border.all(color: done ? AppColors.grn : AppColors.line, width: 1.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: done ? const Icon(LucideIcons.check, size: 14, color: Colors.white) : null,
                    ),
                  ],
                ),
              ),
            );
          }),
          if (canEdit)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "DAILY CHECK-IN",
                    style: TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 12),
                  _RatingRow(label: "\u{26A1} Energy Level", value: log.energy, onChange: (v) => _setRating("energy", v)),
                  const SizedBox(height: 14),
                  _RatingRow(label: "\u{1F525} Motivation Level", value: log.motivation, onChange: (v) => _setRating("motivation", v)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _niceDate(String iso) {
  final d = DateTime.parse(iso);
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  return "${weekdays[d.weekday % 7]}, ${months[d.month - 1]} ${d.day}";
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label, required this.color});
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

class _DateTabButton extends StatelessWidget {
  const _DateTabButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: selected ? AppColors.gold : Colors.transparent, borderRadius: BorderRadius.circular(6)),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.mute)),
        ),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.label, required this.value, required this.onChange});
  final String label;
  final int? value;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: List.generate(10, (i) {
            final n = i + 1;
            final selected = value == n;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 9 ? 5 : 0),
                child: InkWell(
                  onTap: () => onChange(n),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.gold.withValues(alpha: 0.2) : AppColors.bg,
                      border: Border.all(color: selected ? AppColors.gold : AppColors.line),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "$n",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? AppColors.gold : AppColors.mute),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
