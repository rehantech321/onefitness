import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/challenge_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/challenge.dart";
import "../../../data/providers/client_providers.dart";
import "challenge_detail_screen.dart";

/// Mirrors ClientChallengesPage.jsx: joined/available challenge lists that
/// drill into ChallengeDetailScreen.
class ChallengesScreen extends ConsumerStatefulWidget {
  const ChallengesScreen({super.key});

  @override
  ConsumerState<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends ConsumerState<ChallengesScreen> {
  String? _viewId;

  @override
  Widget build(BuildContext context) {
    final challenges = ref.watch(challengesProvider);
    final info = ref.watch(clientInfoProvider);

    if (_viewId != null) {
      final matches = challenges.where((c) => c.id == _viewId);
      if (matches.isNotEmpty) {
        return ChallengeDetailScreen(challenge: matches.first, onBack: () => setState(() => _viewId = null));
      }
    }

    final now = isoToday();
    final joined = challenges.where((c) => isClientRegistered(c, info.id)).toList();
    final available = challenges.where((c) => !isClientRegistered(c, info.id) && c.endDate.compareTo(now) >= 0).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Challenges"),
          if (joined.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text("YOU'RE IN", style: TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
            ...joined.map((c) => _ChallengeCard(challenge: c, showJoin: false, onTap: () => setState(() => _viewId = c.id), onJoin: null)),
            const SizedBox(height: 12),
          ],
          if (available.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text("AVAILABLE TO JOIN", style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
            ...available.map((c) => _ChallengeCard(
                  challenge: c,
                  showJoin: true,
                  onTap: () => setState(() => _viewId = c.id),
                  onJoin: () {
                    ref.read(challengesProvider.notifier).join(c.id, info.id);
                    setState(() => _viewId = c.id);
                  },
                )),
          ],
          if (challenges.isEmpty) const HintBox(text: "No challenges running right now. Check back soon!"),
          if (challenges.isNotEmpty && joined.isEmpty && available.isEmpty)
            const HintBox(text: "No challenges available to join right now."),
        ],
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({required this.challenge, required this.showJoin, required this.onTap, required this.onJoin});
  final Challenge challenge;
  final bool showJoin;
  final VoidCallback onTap;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    final tpl = templateMeta(challenge.template);
    final now = isoToday();
    final daysLeft = DateTime.parse(challenge.endDate).difference(DateTime.parse(now)).inDays + 1;
    final regOpen = registrationOpensDate(challenge);
    final canJoin = showJoin && now.compareTo(regOpen) >= 0 && now.compareTo(challenge.startDate) <= 0;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tpl.emoji, style: const TextStyle(fontSize: 28, height: 1)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(challenge.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        "${tpl.label} · ${challenge.participantIds.length} registered",
                        style: const TextStyle(fontSize: 11, color: AppColors.mute),
                      ),
                    ),
                    if (daysLeft > 0)
                      Text("$daysLeft day${daysLeft != 1 ? 's' : ''} left", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                    if (challenge.prize != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text("\u{1F381} Prize: ${challenge.prize}", style: const TextStyle(fontSize: 11, color: AppColors.gold)),
                      ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.mute,
                  side: const BorderSide(color: AppColors.line),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                child: const Text("View", style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (canJoin)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onJoin,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    backgroundColor: AppColors.gold.withValues(alpha: 0.1),
                    side: const BorderSide(color: AppColors.goldDim),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text("Join Challenge", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
