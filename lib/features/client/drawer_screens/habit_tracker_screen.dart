import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/habit_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/client_providers.dart";

/// Mirrors HabitTrackerPage.jsx (client-facing view) — streak/weekly-score
/// header, a Today/Yesterday toggle, tappable habit rows, and an
/// energy/motivation daily check-in. Every toggle/rating change persists to
/// client_records.data.habitLogs for real (SupabaseService.updateClientHabitLog),
/// same as the web's `saveHabitLog` → `persist` → `sb.upsertClientRecord`;
/// a completed habit also fires the same opportunistic merit-badge
/// eligibility check the web does (awardMeritBadge), silently ignoring
/// "not eligible yet".
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
    final record = ref.read(clientRecordProvider);
    final log = getHabitLog(record, _dateTab);
    final nextChecked = {...log.checked, habitId: !(log.checked[habitId] ?? false)};
    final nextEntry = log.copyWith(checked: nextChecked);
    ref.read(clientRecordProvider.notifier).update((r) => r.copyWith(habitLogByDate: {...r.habitLogByDate, _dateTab: nextEntry}));

    final clientId = ref.read(clientInfoProvider).id;
    SupabaseService.updateClientHabitLog(clientId, _dateTab, nextEntry).catchError((Object _) {});
    SupabaseService.awardMeritBadge(clientId, "habit").catchError((Object _) => <String, dynamic>{});
  }

  void _setRating(String field, int value) {
    final record = ref.read(clientRecordProvider);
    final log = getHabitLog(record, _dateTab);
    final nextEntry = field == "energy" ? log.copyWith(energy: value) : log.copyWith(motivation: value);
    ref.read(clientRecordProvider.notifier).update((r) => r.copyWith(habitLogByDate: {...r.habitLogByDate, _dateTab: nextEntry}));

    final clientId = ref.read(clientInfoProvider).id;
    SupabaseService.updateClientHabitLog(clientId, _dateTab, nextEntry).catchError((Object _) {});
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
              HabitStatBox(value: "$streak", label: "Day Streak", color: AppColors.grn),
              const SizedBox(width: 8),
              HabitStatBox(value: "$weekScore%", label: "Weekly Score", color: AppColors.gold),
              const SizedBox(width: 8),
              HabitStatBox(value: "$doneToday/${habits.length}", label: "Today", color: AppColors.txt),
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
                HabitDateTabButton(label: "Today", selected: _dateTab == isoToday(), onTap: () => setState(() => _dateTab = isoToday())),
                HabitDateTabButton(label: "Yesterday", selected: _dateTab == yesterdayIso(), onTap: () => setState(() => _dateTab = yesterdayIso())),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionLabel("Habits — ${niceHabitDate(_dateTab)}"),
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
                  HabitRatingRow(label: "\u{26A1} Energy Level", value: log.energy, onChange: (v) => _setRating("energy", v)),
                  const SizedBox(height: 14),
                  HabitRatingRow(label: "\u{1F525} Motivation Level", value: log.motivation, onChange: (v) => _setRating("motivation", v)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
