import "../../data/models/client_record.dart";
import "../../data/models/habit_def.dart";
import "../../data/models/habit_log_entry.dart";
import "date_utils.dart";

export "../../data/models/habit_def.dart";

/// Mirrors habitHelpers.js `getClientHabits` — default habits a coach has
/// explicitly enabled, plus any client-specific custom habits (those are
/// always active once created — no separate enable/disable step for them).
List<HabitDef> getClientHabits(ClientRecord record) => [
      ...kDefaultHabits.where((h) => record.habits.contains(h.id)),
      ...record.customHabits,
    ];

/// Mirrors habitHelpers.js `yesterday()`.
String yesterdayIso() => isoDate(DateTime.parse(isoToday()).subtract(const Duration(days: 1)));

/// Mirrors habitHelpers.js `getHabitLog` for a given date.
HabitLogEntry getHabitLog(ClientRecord record, String date) =>
    record.habitLogByDate[date] ?? const HabitLogEntry();

/// Mirrors habitHelpers.js `habitStreak` — consecutive days with at least
/// one habit completed, allowing today to be incomplete without breaking it.
int habitStreak(ClientRecord record) {
  var streak = 0;
  final habits = getClientHabits(record);
  var d = DateTime.parse(isoToday());
  for (var i = 0; i < 365; i++) {
    if (i > 0) d = d.subtract(const Duration(days: 1));
    final date = isoDate(d);
    final log = getHabitLog(record, date);
    final done = habits.any((h) => log.checked[h.id] == true);
    if (done) {
      streak++;
    } else if (i > 0) {
      break;
    }
  }
  return streak;
}

/// Mirrors habitHelpers.js `weeklyConsistencyScore` — average of the last 7
/// days' completion percentage, 0 if no habits are configured.
int weeklyConsistencyScore(ClientRecord record) => weeklyScoreForWindow(record, isoToday());

/// Arbitrary-end-date sibling of [weeklyConsistencyScore] (mirrors the
/// server's `weeklyScoreForWindow` in award-merit-badge/index.ts) — the
/// 7-day window ending on [endDate] instead of always today, so a finalized
/// past month's weekly windows can be scored too (Coach Merit Badge
/// System's Habit Coach badge).
int weeklyScoreForWindow(ClientRecord record, String endDate) {
  final habits = getClientHabits(record);
  if (habits.isEmpty) return 0;
  var total = 0;
  final d = DateTime.parse(endDate);
  for (var i = 0; i < 7; i++) {
    final date = isoDate(d.subtract(Duration(days: i)));
    final log = getHabitLog(record, date);
    final done = habits.where((h) => log.checked[h.id] == true).length;
    total += ((done / habits.length) * 100).round();
  }
  return (total / 7).round();
}
