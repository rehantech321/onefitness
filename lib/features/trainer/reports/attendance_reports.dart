import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/scheduling_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/report_range.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
import "../../../core/utils/booking_utils.dart" show kAttendanceOptions;

/// Mirrors AttendanceReports.jsx's AttendanceSummaryReport — count of
/// bookings per attendance status (+ an "unmarked" bucket) in range.
class AttendanceSummaryReport extends ConsumerWidget {
  const AttendanceSummaryReport({super.key, required this.range});
  final ReportRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(allBookingsProvider).where((b) => range.includes(b.date)).toList();
    final rows = <(String, int)>[
      for (final opt in kAttendanceOptions) (opt.label, bookings.where((b) => b.attendanceStatus == opt.key).length),
      ("Unmarked", bookings.where((b) => b.attendanceStatus == null).length),
    ];
    final total = bookings.length;

    if (total == 0) return const HintBox(text: "No sessions booked in this range.");

    return Column(
      children: [
        ...rows.map((r) => AppCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(r.$1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text("${r.$2}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.gold)),
                ],
              ),
            )),
        AppCard(
          borderColor: AppColors.goldDim,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Total booked", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              Text("$total", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Mirrors AttendanceReports.jsx's SessionUtilizationReport — per-trainer
/// available slots vs booked, in range.
class SessionUtilizationReport extends ConsumerWidget {
  const SessionUtilizationReport({super.key, required this.range});
  final ReportRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainers = ref.watch(trainersProvider);
    final bookings = ref.watch(allBookingsProvider);
    final start = DateTime.parse(range.start);
    final end = DateTime.parse(range.end);

    final rows = trainers.map((t) {
      var capacity = 0;
      var booked = 0;
      for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        final weekday = d.weekday % 7;
        capacity += trainerOfferings(t, weekday).length;
      }
      booked = bookings.where((b) => b.trainerId == t.id && b.status != "cancelled" && range.includes(b.date)).length;
      final pct = capacity > 0 ? (booked / capacity * 100).round() : null;
      return (t.name, capacity, booked, pct);
    }).toList()
      ..sort((a, b) => b.$3.compareTo(a.$3));

    return Column(
      children: rows
          .map((r) => AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.$1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          Text("${r.$2} available · ${r.$3} booked", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                        ],
                      ),
                    ),
                    Text(r.$4 != null ? "${r.$4}%" : "—", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.gold)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}
