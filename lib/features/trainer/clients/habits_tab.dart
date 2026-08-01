import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/habit_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors HabitTrackerPage.jsx's `isCoach` mode (read-only habit log) plus
/// HabitSettingsPanel (configuring which habits this client tracks).
class HabitsTab extends ConsumerWidget {
  const HabitsTab({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(trainerRosterProvider);
    final matches = roster.where((c) => c.id == clientId);
    if (matches.isEmpty) return const SizedBox.shrink();
    final name = matches.first.name;
    final records = ref.watch(trainerClientRecordsProvider);
    final record = records[clientId];
    if (record == null) return const SizedBox.shrink();

    final habits = getClientHabits(record);
    final log = getHabitLog(record, DateTime.now().toIso8601String().substring(0, 10));
    final streak = habitStreak(record);
    final weekScore = weeklyConsistencyScore(record);
    final doneToday = habits.where((h) => log.checked[h.id] == true).length;

    void updateRecord(void Function(_RecMut m) mutate) {
      ref.read(trainerClientRecordsProvider.notifier).update(clientId, (r) {
        final m = _RecMut(r.habits, r.customHabits);
        mutate(m);
        return r.copyWith(habits: m.enabled, customHabits: m.custom);
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel("Habit Tracker — $name"),
          if (habits.isNotEmpty) ...[
            AppCard(
              child: Text(
                "Weekly score: $weekScore% · Streak: $streak days",
                style: const TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700),
              ),
            ),
            Row(
              children: [
                _StatBox(value: "$streak", label: "Day Streak", color: AppColors.grn),
                const SizedBox(width: 8),
                _StatBox(value: "$weekScore%", label: "Weekly Score", color: AppColors.gold),
                const SizedBox(width: 8),
                _StatBox(value: "$doneToday/${habits.length}", label: "Today", color: AppColors.txt),
              ],
            ),
            const SizedBox(height: 16),
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
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: HintBox(text: "This client has no habits configured yet. Turn some on below."),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 12),
            child: Text(
              "Coach view — read-only. Use the settings below to assign/remove habits.",
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
                const Text("DEFAULT HABITS", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kDefaultHabits.map((h) {
                    final on = record.habits.contains(h.id);
                    return InkWell(
                      onTap: () => updateRecord((m) => on ? m.enabled.remove(h.id) : m.enabled.add(h.id)),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: on ? AppColors.gold.withValues(alpha: 0.12) : AppColors.card,
                          border: Border.all(color: on ? AppColors.gold : AppColors.line),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text("${h.emoji} ${h.label}", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? AppColors.gold : AppColors.txt)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                const Text("CUSTOM HABITS", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
                const SizedBox(height: 8),
                ...record.customHabits.map((h) => AppCard(
                      child: Row(
                        children: [
                          Text(h.emoji, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(h.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                          IconButton(
                            onPressed: () => updateRecord((m) => m.custom.removeWhere((x) => x.id == h.id)),
                            icon: const Icon(LucideIcons.trash2, size: 15, color: Color(0xFF6B3B3B)),
                          ),
                        ],
                      ),
                    )),
                _AddCustomHabitRow(onAdd: (label, emoji) => updateRecord((m) => m.custom.add(HabitDef(id: DateTime.now().microsecondsSinceEpoch.toString(), label: label, emoji: emoji)))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecMut {
  _RecMut(List<String> habits, List<HabitDef> custom) : enabled = [...habits], custom = [...custom];
  final List<String> enabled;
  final List<HabitDef> custom;
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
        decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.mute)),
          ],
        ),
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
          Expanded(child: AppField(controller: _label, placeholder: "New habit label…")),
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
