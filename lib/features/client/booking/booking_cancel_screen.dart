import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/booking_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/platform_settings_provider.dart";

/// Mirrors BookSession.jsx's cancelConfirm screen.
class BookingCancelScreen extends ConsumerWidget {
  const BookingCancelScreen({
    super.key,
    required this.booking,
    required this.trainers,
    required this.onBack,
    required this.onConfirmCancel,
  });

  final Booking booking;
  final List<Trainer> trainers;
  final VoidCallback onBack;
  final VoidCallback onConfirmCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = trainers.where((t) => t.id == booking.trainerId);
    final trainer = matches.isNotEmpty ? matches.first : null;
    final settings = ref.watch(platformSettingsProvider);
    final w = cancelWindow(booking, lateCancellationHours: settings.lateCancellationHours);
    final charged = w != "free";

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: onBack),
          const SizedBox(height: 10),
          const SectionLabel("Cancel session"),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${dayLabel(booking.date)} · ${fmtSlot(booking.slot)}", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(trainer?.name ?? "Trainer", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: charged ? const Color(0x1AC9784A) : AppColors.gold.withValues(alpha: 0.08),
              border: Border.all(color: charged ? const Color(0xFFA8632F) : AppColors.goldDim),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (charged)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text("Late cancellation", style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFD68A4F))),
                  ),
                Text(
                  charged
                      ? "This is within ${settings.lateCancellationHours} hours of your session — a late cancellation. You'll be charged ${lateCancellationFeeLabel(feeCents: settings.lateCancellationFeeCents)}."
                      : "You're outside the ${settings.lateCancellationHours}-hour window — no charge.",
                  style: const TextStyle(fontSize: 13, color: AppColors.txt, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: BtnGold(
                  onPressed: onConfirmCancel,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.check, size: 15, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(charged ? "Cancel anyway" : "Confirm cancel"),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              BtnGhost(onPressed: onBack, child: const Text("Keep it")),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mirrors BookSession.jsx's `denied` screen — shown when a booking attempt
/// is blocked (no membership, over budget, slot just filled, etc).
class BookingDeniedScreen extends StatelessWidget {
  const BookingDeniedScreen({
    super.key,
    required this.check,
    required this.onBack,
    required this.onGoMemberships,
    required this.onGoSignatures,
  });

  final BookingCheck check;
  final VoidCallback onBack;
  final VoidCallback onGoMemberships;
  final VoidCallback onGoSignatures;

  @override
  Widget build(BuildContext context) {
    final isLimitHit = check.reason == "capacity" || check.reason == "trainer-conflict";
    final isConflict = check.reason == "conflict";
    final needsWaiver = check.reason == "waiver-required";
    final title = isConflict
        ? "Session conflict"
        : check.reason == "capacity"
            ? "Session full"
            : check.reason == "trainer-conflict"
                ? "Not actually available"
                : needsWaiver
                    ? "Signature needed"
                    : "Can't book this session";

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 50, 18, 18),
      child: Column(
        children: [
          Icon(
            isConflict || isLimitHit ? LucideIcons.calendarCheck : LucideIcons.circleSlash,
            size: 36,
            color: isConflict || isLimitHit ? AppColors.gold : const Color(0xFFD68A4F),
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              check.msg ?? check.reason ?? "",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.mute, height: 1.6),
            ),
          ),
          const SizedBox(height: 26),
          if (needsWaiver)
            BtnGold(
              onPressed: onGoSignatures,
              full: true,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.fileSignature, size: 15, color: Colors.white),
                  SizedBox(width: 6),
                  Text("Go to Signatures"),
                ],
              ),
            )
          else if (!isConflict && !isLimitHit)
            BtnGold(
              onPressed: onGoMemberships,
              full: true,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.creditCard, size: 15, color: Colors.white),
                  SizedBox(width: 6),
                  Text("Go to Membership Hub"),
                ],
              ),
            ),
          const SizedBox(height: 10),
          BtnGhost(onPressed: onBack, full: true, child: const Text("Back to schedule")),
        ],
      ),
    );
  }
}
