import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/habit_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors HabitTrackerPage.jsx's `isCoach` mode (read-only habit log, with
/// a genuinely non-interactive Daily Check-In — matches the web's
/// `disabled={isCoach}` on every rating button) plus HabitSettingsPanel
/// (configuring which habits this client tracks). Every toggle/add/remove
/// below writes to client_records.data.habitSettings for real via
/// SupabaseService.updateClientHabitSettings, same as the web's
/// `persist({...client, habitSettings})`.
class HabitsTab extends ConsumerStatefulWidget {
  const HabitsTab({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<HabitsTab> createState() => _HabitsTabState();
}

class _HabitsTabState extends ConsumerState<HabitsTab> {
  late String _dateTab = isoToday();

  Future<void> _writeHabitSettings(List<String> enabled, List<HabitDef> custom) async {
    ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId, (r) => r.copyWith(habits: enabled, customHabits: custom));
    try {
      await SupabaseService.updateClientHabitSettings(widget.clientId, enabled: enabled, custom: custom);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(trainerRosterProvider);
    final matches = roster.where((c) => c.id == widget.clientId);
    if (matches.isEmpty) return const SizedBox.shrink();
    final name = matches.first.name;
    final records = ref.watch(trainerClientRecordsProvider);
    final record = records[widget.clientId];
    if (record == null) return const SizedBox.shrink();

    final habits = getClientHabits(record);
    final log = getHabitLog(record, _dateTab);
    final streak = habitStreak(record);
    final weekScore = weeklyConsistencyScore(record);
    final doneToday = habits.where((h) => log.checked[h.id] == true).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel("Habit Tracker — $name"),
          AppCard(
            child: Text(
              "Weekly score: $weekScore% · Streak: $streak days",
              style: const TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700),
            ),
          ),
          Row(
            children: [
              HabitStatBox(value: "$streak", label: "Day Streak", color: AppColors.grn),
              const SizedBox(width: 8),
              HabitStatBox(value: "$weekScore%", label: "Weekly Score", color: AppColors.gold),
              const SizedBox(width: 8),
              HabitStatBox(value: "$doneToday/${habits.length}", label: "Today", color: AppColors.txt),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                HabitDateTabButton(label: "Today", selected: _dateTab == isoToday(), onTap: () => setState(() => _dateTab = isoToday())),
                HabitDateTabButton(label: "Yesterday", selected: _dateTab == yesterdayIso(), onTap: () => setState(() => _dateTab = yesterdayIso())),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionLabel("Habits — ${niceHabitDate(_dateTab)}"),
          if (habits.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 8),
              child: HintBox(text: "No habits assigned yet. A coach can assign habits from the client profile."),
            )
          else
            ...habits.map((h) {
              final done = log.checked[h.id] == true;
              return Container(
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
                    Expanded(child: Text(h.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: done ? AppColors.grn : AppColors.txt))),
                    Icon(done ? LucideIcons.checkCircle2 : LucideIcons.circle, size: 18, color: done ? AppColors.grn : AppColors.line),
                  ],
                ),
              );
            }),
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("DAILY CHECK-IN", style: TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                const SizedBox(height: 12),
                HabitRatingRow(label: "\u{26A1} Energy Level", value: log.energy, onChange: (_) {}, disabled: true),
                const SizedBox(height: 14),
                HabitRatingRow(label: "\u{1F525} Motivation Level", value: log.motivation, onChange: (_) {}, disabled: true),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              "Coach view — read-only. To assign/remove habits, use the settings below.",
              style: TextStyle(fontSize: 11, color: AppColors.mute, fontStyle: FontStyle.italic),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.only(top: 14),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel("Manage Habits for This Client"),
                const Text(
                  "Turn on the habits you want this client to track. Only the habits you designate here will appear on their dashboard — if none are on, they'll see no habit tile. You can also create custom habits below.",
                  style: TextStyle(fontSize: 12, color: AppColors.mute, height: 1.5),
                ),
                const SizedBox(height: 12),
                const Text("DEFAULT HABITS", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
                const SizedBox(height: 8),
                ...kDefaultHabits.map((h) {
                  final on = record.habits.contains(h.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () => _writeHabitSettings(
                        on ? (record.habits.where((x) => x != h.id).toList()) : [...record.habits, h.id],
                        record.customHabits,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: on ? AppColors.grn.withValues(alpha: 0.08) : AppColors.card,
                          border: Border.all(color: on ? AppColors.grn : AppColors.line),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Text(h.emoji, style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(h.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                            Text(on ? "ON" : "OFF", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? AppColors.grn : AppColors.mute)),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                const Text("CUSTOM HABITS", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
                const SizedBox(height: 8),
                ...record.customHabits.map((h) => AppCard(
                      child: Row(
                        children: [
                          Text(h.emoji, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(h.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                          IconButton(
                            onPressed: () => _writeHabitSettings(record.habits, record.customHabits.where((x) => x.id != h.id).toList()),
                            icon: const Icon(LucideIcons.trash2, size: 15, color: Color(0xFF6B3B3B)),
                          ),
                        ],
                      ),
                    )),
                _AddCustomHabitRow(
                  onAdd: (label, emoji) => _writeHabitSettings(
                    record.habits,
                    [...record.customHabits, HabitDef(id: "${DateTime.now().microsecondsSinceEpoch}", label: label, emoji: emoji)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddCustomHabitRow extends StatefulWidget {
  const _AddCustomHabitRow({required this.onAdd});
  final void Function(String label, String emoji) onAdd;

  @override
  State<_AddCustomHabitRow> createState() => _AddCustomHabitRowState();
}

class _AddCustomHabitRowState extends State<_AddCustomHabitRow> {
  final _emoji = TextEditingController(text: "⭐");
  final _label = TextEditingController();

  @override
  void dispose() {
    _emoji.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(width: 52, child: AppField(controller: _emoji)),
          const SizedBox(width: 8),
          Expanded(child: AppField(controller: _label, placeholder: "Custom habit name…")),
          const SizedBox(width: 8),
          BtnGhost(
            onPressed: () {
              if (_label.text.trim().isEmpty) return;
              widget.onAdd(_label.text.trim(), _emoji.text.trim().isEmpty ? "⭐" : _emoji.text.trim());
              _label.clear();
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }
}
