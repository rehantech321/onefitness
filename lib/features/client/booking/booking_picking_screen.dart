import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/trainer.dart";

class PendingPick {
  const PendingPick({required this.trainer, required this.sessionType, required this.discipline, required this.slot});
  final Trainer trainer;
  final String sessionType;
  final String discipline;
  final int slot;
}

/// Mirrors the `picking` step of BookSession.jsx — trainer/time summary,
/// location (single location here, so it's shown but not chosen), and the
/// final Confirm booking action.
class BookingPickingScreen extends StatelessWidget {
  const BookingPickingScreen({
    super.key,
    required this.pick,
    required this.date,
    required this.onBack,
    required this.onConfirm,
    this.busy = false,
    this.error,
  });

  final PendingPick pick;
  final String date;
  final VoidCallback onBack;
  final VoidCallback onConfirm;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = pick.trainer;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: onBack),
          const SizedBox(height: 10),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Avatar(src: t.photo, name: t.name, size: 40, active: true),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          "${disciplineLabel(pick.discipline)} · ${sessionTypeLabel(pick.sessionType)}",
                          style: const TextStyle(fontSize: 12, color: AppColors.mute),
                        ),
                      ],
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    "${dayLabel(date)} · ${fmtSlot(pick.slot)}",
                    style: const TextStyle(fontSize: 13, color: AppColors.gold),
                  ),
                ),
              ],
            ),
          ),
          if (t.locationName != null) ...[
            const SectionLabel("Location"),
            AppCard(
              borderColor: AppColors.gold,
              margin: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.mapPin, size: 13, color: AppColors.gold),
                      const SizedBox(width: 6),
                      Text(t.locationName!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    ],
                  ),
                  if (t.locationAddress != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(t.locationAddress!, style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                    ),
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              pick.sessionType == "semi-private" ? "Semi-private — up to 4 share the floor." : "One-on-one — just you.",
              style: const TextStyle(fontSize: 12, color: AppColors.mute),
            ),
          ),
          if (error != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.errorText.withValues(alpha: 0.1),
                border: Border.all(color: AppColors.errorText.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(error!, style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
            ),
          ],
          BtnGold(
            onPressed: busy ? null : onConfirm,
            full: true,
            child: busy
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                      ),
                      SizedBox(width: 8),
                      Text("Booking…"),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.check, size: 15, color: Colors.white),
                      SizedBox(width: 6),
                      Text("Confirm booking"),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
