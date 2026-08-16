import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/merit_badge_def.dart";
import "../../../data/providers/client_providers.dart";
import "sub_badge_detail_screen.dart";

final _badgeDateFmt = DateFormat("MMM d, yyyy");

/// Mirrors BadgeGallery.jsx — the full badge catalog, earned or not, with
/// what it takes to earn each one. Distinct from MeritBadgeRow (only shows
/// already-earned badges compactly). Gym Citizen/Progress Tracker are built
/// on a 10/3-sub-badge pattern (SubBadgeDetailScreen) rather than a single
/// award — this screen shows their live progress and links into the detail.
class BadgeGalleryScreen extends ConsumerStatefulWidget {
  const BadgeGalleryScreen({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<BadgeGalleryScreen> createState() => _BadgeGalleryScreenState();
}

class _BadgeGalleryScreenState extends ConsumerState<BadgeGalleryScreen> {
  String? _openSubBadges; // null | "gym_citizen" | "progress_tracker"

  @override
  Widget build(BuildContext context) {
    final clientId = widget.clientId;
    final earnedBadges = ref.watch(earnedBadgesProvider);
    final earnedByKey = {
      for (final b in earnedBadges.where((b) => b.clientId == clientId && b.isActive)) b.badgeKey: b,
    };

    if (_openSubBadges == "gym_citizen") {
      return SubBadgeDetailScreen(
        clientId: clientId,
        earnedBadges: earnedBadges,
        subBadges: kGymCitizenSubBadges,
        title: "Gym Citizen",
        blurb: "Your coach checks off each of these as they see you demonstrate it. Once all 10 are verified, the Gym Citizen Merit Badge is awarded automatically.",
        onBack: () => setState(() => _openSubBadges = null),
      );
    }
    if (_openSubBadges == "progress_tracker") {
      return SubBadgeDetailScreen(
        clientId: clientId,
        earnedBadges: earnedBadges,
        subBadges: kProgressTrackerSubBadges,
        title: "Progress Tracker",
        blurb: "These are earned automatically the moment you log a progress photo, a measurement, or a workout — no coach action needed. Once all 3 are active, the Progress Tracker Merit Badge is awarded automatically.",
        onBack: () => setState(() => _openSubBadges = null),
      );
    }

    final myBadgeKeys = earnedBadges.where((b) => b.clientId == clientId && b.isActive).map((b) => b.badgeKey).toSet();
    final gymCitizenSubCount = myBadgeKeys.where(kGymCitizenSubBadgeKeys.contains).length;
    final progressTrackerSubCount = myBadgeKeys.where(kProgressTrackerSubBadgeKeys.contains).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Merit Badges"),
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 13, color: AppColors.mute, height: 1.6),
                children: [
                  TextSpan(
                    text: "Merit Badges recognize your consistency, progress, and involvement at One Fitness. Earn badges by completing challenges, tracking your progress, building healthy habits, and being an active part of our community. Collect five or more active Merit Badges to earn a +5 Merit Badge points bonus. ",
                  ),
                  TextSpan(text: "Automatic", style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w700)),
                  TextSpan(text: " badges are awarded by the app the moment you qualify. "),
                  TextSpan(text: "Coach Awarded", style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w700)),
                  TextSpan(text: " badges are given by your coach or the gym owner."),
                ],
              ),
            ),
          ),
          ...kMeritBadges.map((b) {
            final earned = earnedByKey[b.key];
            final isGymCitizen = b.key == "gym_citizen";
            final isProgressTracker = b.key == "progress_tracker";
            final subCount = isGymCitizen ? gymCitizenSubCount : (isProgressTracker ? progressTrackerSubCount : 0);
            final subTotal = isGymCitizen ? kGymCitizenSubBadges.length : kProgressTrackerSubBadges.length;
            final inProgress = (isGymCitizen || isProgressTracker) && earned == null && subCount > 0;
            final onTap = isGymCitizen
                ? () => setState(() => _openSubBadges = "gym_citizen")
                : isProgressTracker
                    ? () => setState(() => _openSubBadges = "progress_tracker")
                    : null;
            return AppCard(
              onTap: onTap,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (inProgress)
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 56,
                            height: 56,
                            child: CircularProgressIndicator(
                              value: subCount / subTotal,
                              strokeWidth: 3,
                              backgroundColor: AppColors.line,
                              valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                            ),
                          ),
                          MeritBadgeShield(badgeKey: b.key, size: 38, grayscale: true),
                        ],
                      ),
                    )
                  else
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        MeritBadgeShield(badgeKey: b.key, size: 56, grayscale: earned == null),
                        if (earned == null) const Icon(LucideIcons.lock, size: 16, color: Colors.white),
                      ],
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: earned != null ? AppColors.gold : AppColors.txt)),
                        Text(
                          b.category == "coach" ? "COACH AWARDED" : "AUTOMATIC",
                          style: const TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 0.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        if (inProgress)
                          Text(
                            isGymCitizen ? _gymCitizenProgressLabel(subCount) : "$subCount/$subTotal sub-badges verified",
                            style: const TextStyle(fontSize: 10, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                          )
                        else
                          Text(b.description, style: const TextStyle(fontSize: 12, color: AppColors.mute, height: 1.4)),
                        if (earned != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              "Earned ${earned.earnedAt.isEmpty ? '' : _badgeDateFmt.format(DateTime.parse(earned.earnedAt))}",
                              style: const TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700),
                            ),
                          ),
                        if (isGymCitizen || isProgressTracker)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("View $subTotal sub-badges", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gold)),
                                const Icon(LucideIcons.chevronRight, size: 11, color: AppColors.gold),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Mirrors GymCitizenProgressRing.jsx `gymCitizenProgressMessage` — staged
  /// messaging as the coach checks off more sub-badges.
  String _gymCitizenProgressLabel(int activeCount) {
    final msg = activeCount >= 9
        ? "One More!"
        : activeCount == 8
            ? "Almost There"
            : activeCount >= 5
                ? "Keep Going"
                : activeCount >= 1
                    ? "Getting There"
                    : "Get Started";
    return "$msg · $activeCount/10";
  }
}
