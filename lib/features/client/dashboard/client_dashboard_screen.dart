import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/habit_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/client_record.dart";
import "sessions_remaining_badge.dart";
import "workout_calendar.dart";

/// Mirrors ClientDashboard.jsx — the client's home tab.
class ClientDashboardScreen extends StatelessWidget {
  const ClientDashboardScreen({
    super.key,
    required this.client,
    required this.info,
    required this.bookings,
    required this.onGoBooking,
    required this.onLogWorkout,
    required this.onPickDate,
    required this.onGoHabits,
  });

  final ClientRecord client;
  final ClientInfo info;
  final List<Booking> bookings;
  final VoidCallback onGoBooking;
  final VoidCallback onLogWorkout;
  final ValueChanged<String> onPickDate;
  final VoidCallback onGoHabits;

  Booking? get _next {
    final todayStr = isoToday();
    final upcoming = bookings.where((b) => b.clientId == info.id && b.date.compareTo(todayStr) >= 0).toList()
      ..sort((a, b) => (a.date + a.slot.toString().padLeft(4, '0'))
          .compareTo(b.date + b.slot.toString().padLeft(4, '0')));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  bool get _loggedToday => client.loggedOn(isoToday());
  bool get _hasSessionToday => bookings.any((b) => b.clientId == info.id && b.date == isoToday());

  @override
  Widget build(BuildContext context) {
    final firstName = info.name.split(" ").first;
    final habits = getClientHabits(client);
    final todayLog = getHabitLog(client, isoToday());
    final done = habits.where((h) => todayLog.checked[h.id] == true).length;
    final showHabitTile = habits.isNotEmpty && done < habits.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Hey $firstName, it's ${_hasSessionToday ? "lifting day!" : "a rest day"}",
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(dayLabel(isoToday()), style: const TextStyle(fontSize: 13, color: AppColors.mute)),
          ),

          SessionsRemainingBadge(info: info, bookings: bookings),

          if (showHabitTile)
            AppCard(
              borderColor: AppColors.goldDim,
              onTap: onGoHabits,
              child: Row(
                children: [
                  const Text("\u{1F525}", style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Habits — $done/${habits.length} done today",
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(height: 1),
                        Text(
                          "${habitStreak(client)} day streak · ${((done / habits.length) * 100).round()}% today",
                          style: const TextStyle(fontSize: 11, color: AppColors.mute),
                        ),
                      ],
                    ),
                  ),
                  const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
                ],
              ),
            ),

          WorkoutCalendar(client: client, info: info, bookings: bookings, onPickDate: onPickDate),

          const SizedBox(height: 4),
          AppCard(
            borderColor: AppColors.goldDim,
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "NEXT SESSION",
                  style: TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700, letterSpacing: 1),
                ),
                const SizedBox(height: 8),
                if (_next != null) ...[
                  Text(
                    "${dayLabel(_next!.date)} · ${fmtSlot(_next!.slot)}",
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  if (_next!.locationName != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(LucideIcons.mapPin, size: 12, color: AppColors.gold),
                        const SizedBox(width: 4),
                        Text(_next!.locationName!, style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: onGoBooking,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.gold,
                      side: const BorderSide(color: AppColors.line),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text("Manage sessions", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ] else ...[
                  const Text("No upcoming sessions booked.", style: TextStyle(fontSize: 13, color: AppColors.mute)),
                  const SizedBox(height: 10),
                  BtnGold(onPressed: onGoBooking, child: const Text("Book a session", style: TextStyle(fontSize: 13))),
                ],
              ],
            ),
          ),

          AppCard(
            onTap: onLogWorkout,
            child: Row(
              children: [
                Icon(LucideIcons.check, size: 20, color: _loggedToday ? AppColors.gold : AppColors.mute),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Today's workout", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      Text(
                        _loggedToday ? "Logged — tap to review or edit" : "Tap to log your session",
                        style: const TextStyle(fontSize: 12, color: AppColors.mute),
                      ),
                    ],
                  ),
                ),
                const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mute),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
