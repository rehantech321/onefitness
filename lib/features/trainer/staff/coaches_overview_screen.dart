import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/attention_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors CoachesOverview.jsx (owner-only) — a coach-approval-code card
/// (mocked as a static invite code, since there's no real signup flow) and
/// a per-coach oversight list showing client counts and outstanding flags.
class CoachesOverviewScreen extends ConsumerWidget {
  const CoachesOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainers = ref.watch(trainersProvider);
    final roster = ref.watch(trainerRosterProvider);
    final records = ref.watch(trainerClientRecordsProvider);
    final bookings = ref.watch(allBookingsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Coach Approval Code"),
          AppCard(
            borderColor: AppColors.goldDim,
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("ONEFIT-7X2K", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 1)),
                      Text("Valid for 7 days · share with a new hire to self-signup", style: TextStyle(fontSize: 11, color: AppColors.mute)),
                    ],
                  ),
                ),
                TextButton(onPressed: () {}, child: const Text("Copy link", style: TextStyle(color: AppColors.gold, fontSize: 12))),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const SectionLabel("All Coaches"),
          ...trainers.map((t) {
            final myRoster = roster.where((c) => c.primaryTrainerId == t.id).toList();
            final flags = [...computeNeedsAttention(myRoster, records), ...computeUnloggedAttendance(myRoster, bookings)];
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Avatar(name: t.name, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            Text("${myRoster.length} client${myRoster.length == 1 ? '' : 's'}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                          ],
                        ),
                      ),
                      if (flags.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.flag, size: 11, color: AppColors.danger),
                              const SizedBox(width: 4),
                              Text("${flags.length}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.danger)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (flags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...flags.take(4).map((f) => Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text("• ${f.label}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                        )),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
