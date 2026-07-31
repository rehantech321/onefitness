import "package:flutter/material.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/booking_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/utils/platform_settings.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/trainer.dart";

/// Mirrors UpcomingSessionCard.jsx — a compact expandable tile in the
/// upcoming-sessions grid with Reschedule/Cancel actions.
class UpcomingSessionCard extends StatefulWidget {
  const UpcomingSessionCard({
    super.key,
    required this.booking,
    required this.trainers,
    required this.onReschedule,
    required this.onCancel,
  });

  final Booking booking;
  final List<Trainer> trainers;
  final ValueChanged<Booking> onReschedule;
  final ValueChanged<Booking> onCancel;

  @override
  State<UpcomingSessionCard> createState() => _UpcomingSessionCardState();
}

class _UpcomingSessionCardState extends State<UpcomingSessionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final trainerMatches = widget.trainers.where((t) => t.id == b.trainerId);
    final trainer = trainerMatches.isNotEmpty ? trainerMatches.first : null;
    final w = cancelWindow(b);
    final charged = w != "free";
    final reschedulable = canReschedule(b);
    final d = DateTime.parse(b.date);
    final shortDate = "${_weekdayAbbr(d.weekday)} ${d.day}";

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: charged ? const Color(0xFFA8632F) : AppColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shortDate, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.txt)),
                  const SizedBox(height: 1),
                  Text(
                    fmtSlot(b.slot),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.gold),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    trainer?.name ?? "Removed",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9.5, color: AppColors.mute),
                  ),
                  if (charged)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text("⚠ Fee window", style: TextStyle(fontSize: 8.5, color: Color(0xFFD68A4F), fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(disciplineLabel(b.discipline), style: const TextStyle(fontSize: 10, color: AppColors.mute)),
                    if (b.locationName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(b.locationName!, style: const TextStyle(fontSize: 10, color: AppColors.gold, fontWeight: FontWeight.w600)),
                      ),
                    if (charged)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          "Within $kLateCancellationHours hrs — late window.${!reschedulable ? " Rescheduling is blocked this close to your session." : ""}",
                          style: const TextStyle(fontSize: 10, color: AppColors.mute, height: 1.4),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Column(
              children: [
                if (reschedulable)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => widget.onReschedule(b),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.gold,
                        backgroundColor: AppColors.gold.withValues(alpha: 0.12),
                        side: const BorderSide(color: AppColors.goldDim),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text("Reschedule", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                const SizedBox(height: 3),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => widget.onCancel(b),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.errorText,
                      side: const BorderSide(color: AppColors.line),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text("Cancel", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
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

const _weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
String _weekdayAbbr(int dartWeekday) => _weekdayNames[dartWeekday - 1];
