import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/booking_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/platform_settings_provider.dart";

/// Mirrors UpcomingSessionCard.jsx — a compact expandable tile in the
/// upcoming-sessions grid with Reschedule/Cancel actions. Text scaling is
/// clamped so a device's larger-text accessibility setting can't blow up
/// this deliberately dense card (buttons would otherwise wrap to 2 lines
/// and overflow into the sibling widget below it).
class UpcomingSessionCard extends ConsumerStatefulWidget {
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
  ConsumerState<UpcomingSessionCard> createState() => _UpcomingSessionCardState();
}

class _UpcomingSessionCardState extends ConsumerState<UpcomingSessionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final trainerMatches = widget.trainers.where((t) => t.id == b.trainerId);
    final trainer = trainerMatches.isNotEmpty ? trainerMatches.first : null;
    final settings = ref.watch(platformSettingsProvider);
    final w = cancelWindow(b, lateCancellationHours: settings.lateCancellationHours);
    final charged = w != "free";
    final reschedulable = canReschedule(b, blockRescheduleInWindow: settings.blockRescheduleInWindow, lateCancellationHours: settings.lateCancellationHours);
    final d = DateTime.parse(b.date);
    final shortDate = "${_weekdayAbbr(d.weekday)} ${d.day}";

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15)),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: charged ? const Color(0xFFA8632F) : AppColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(shortDate, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.txt)),
                  const SizedBox(height: 1),
                  Text(
                    fmtSlot(b.slot),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.gold),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    trainer?.name ?? "Removed",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.mute),
                  ),
                  if (charged)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text("⚠ Fee window", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: Color(0xFFD68A4F), fontWeight: FontWeight.w700)),
                    ),
                  if (_expanded)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(disciplineLabel(b.discipline), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppColors.mute)),
                            if (b.locationName != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(b.locationName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppColors.gold, fontWeight: FontWeight.w600)),
                              ),
                            if (charged)
                              Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(
                                  "Within ${settings.lateCancellationHours} hrs — late window.${!reschedulable ? " Rescheduling is blocked this close to your session." : ""}",
                                  style: const TextStyle(fontSize: 10, color: AppColors.mute, height: 1.35),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              // Side by side (not stacked) — halves the vertical space the
              // action row needs vs. the old Reschedule-then-Cancel stack,
              // which is most of what made room for shrinking the card.
              child: Row(
                children: [
                  if (reschedulable) ...[
                    Expanded(
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
                        child: const Text("Reschedule", maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    // Plain "Cancel" only outside the fee window — inside it,
                    // the button itself says "Late Cancel" so the fee is
                    // obvious before they even tap it, not just buried in
                    // the confirm screen that follows.
                    child: OutlinedButton(
                      onPressed: () => widget.onCancel(b),
                      style: charged
                          ? OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFD68A4F),
                              backgroundColor: const Color(0x1AC9784A),
                              side: const BorderSide(color: Color(0xFFA8632F)),
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            )
                          : OutlinedButton.styleFrom(
                              foregroundColor: AppColors.errorText,
                              side: const BorderSide(color: AppColors.line),
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                      child: Text(charged ? "Late Cancel" : "Cancel", maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
String _weekdayAbbr(int dartWeekday) => _weekdayNames[dartWeekday - 1];
