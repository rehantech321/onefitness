import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/challenge_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/challenge.dart";
import "../../../data/providers/client_providers.dart";

/// Mirrors ClientChallengeDetail.jsx — description/prize, a manual-progress
/// logger for templates that need one, my score, and the leaderboard.
class ChallengeDetailScreen extends ConsumerStatefulWidget {
  const ChallengeDetailScreen({super.key, required this.challenge, required this.onBack});

  final Challenge challenge;
  final VoidCallback onBack;

  @override
  ConsumerState<ChallengeDetailScreen> createState() => _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends ConsumerState<ChallengeDetailScreen> {
  final _progressController = TextEditingController();

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final challenge = widget.challenge;
    final info = ref.watch(clientInfoProvider);
    final client = ref.watch(clientRecordProvider);
    final bookings = ref.watch(clientBookingsProvider);
    final tpl = templateMeta(challenge.template);

    final myScore = calcChallengeScore(info.id, challenge, client, bookings);
    final registered = isClientRegistered(challenge, info.id);
    final now = isoToday();
    final regOpen = registrationOpensDate(challenge);
    final canJoin = !registered && now.compareTo(regOpen) >= 0 && now.compareTo(challenge.startDate) <= 0;
    final isEnded = challenge.endDate.compareTo(now) < 0;
    final needsManualLog = challenge.template == "progressive-overload" || challenge.template == "fat-loss";

    final leaderboard = [
      LeaderboardEntry(clientId: info.id, name: info.name, score: myScore),
      ...challenge.otherLeaderboard,
    ]..sort((a, b) => b.score.compareTo(a.score));
    var rank = 1;
    final ranked = <(LeaderboardEntry, int)>[];
    for (var i = 0; i < leaderboard.length; i++) {
      if (i > 0 && leaderboard[i].score < leaderboard[i - 1].score) rank = i + 1;
      ranked.add((leaderboard[i], rank));
    }

    void logEntry() {
      final v = double.tryParse(_progressController.text);
      if (v == null || v < 0) return;
      ref.read(clientRecordProvider.notifier).update((r) {
        final prev = r.challengeProgress[challenge.id] ?? const [];
        final nextMap = {...r.challengeProgress, challenge.id: [...prev, ChallengeProgressEntry(value: v, loggedAt: stamp())]};
        return r.copyWith(challengeProgress: nextMap);
      });
      _progressController.clear();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onBack, title: "All challenges"),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tpl.emoji, style: const TextStyle(fontSize: 36)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(challenge.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        "${tpl.label} · ${challenge.startDate} → ${challenge.endDate}",
                        style: const TextStyle(fontSize: 12, color: AppColors.mute),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (challenge.prize != null)
            AppCard(
              borderColor: AppColors.goldDim,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("\u{1F381} PRIZE", style: TextStyle(fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(challenge.prize!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          if (challenge.description != null)
            AppCard(child: Text(challenge.description!, style: const TextStyle(fontSize: 13, color: AppColors.txt, height: 1.5))),
          if (canJoin)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: BtnGold(
                onPressed: () => ref.read(challengesProvider.notifier).join(challenge.id, info.id),
                full: true,
                child: const Text("Join Challenge"),
              ),
            ),
          if (registered && !isEnded && needsManualLog)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "LOG MY ${challenge.metric.toUpperCase()}",
                    style: const TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: AppField(
                          controller: _progressController,
                          placeholder: "Enter ${challenge.metric}…",
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 42,
                        child: BtnGold(onPressed: logEntry, child: const Text("Log")),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 12, color: AppColors.mute),
                        children: [
                          const TextSpan(text: "My best: "),
                          TextSpan(text: _fmtNum(myScore), style: const TextStyle(color: AppColors.txt, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (registered)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "MY SCORE",
                    style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 1),
                  ),
                  const SizedBox(height: 4),
                  Text(_fmtNum(myScore), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.gold)),
                  Text(challenge.metric, style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                ],
              ),
            ),
          SectionLabel("Leaderboard (${challenge.participantIds.length} participants)"),
          if (ranked.isEmpty)
            const HintBox(text: "Be the first to join!")
          else
            ...ranked.map((entry) {
              final (e, r) = entry;
              final isMe = e.clientId == info.id;
              return AppCard(
                borderColor: isMe ? AppColors.gold : AppColors.line,
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text(
                        "#$r",
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: r <= 3 ? AppColors.gold : AppColors.mute),
                      ),
                    ),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.txt),
                          children: [
                            TextSpan(text: e.name),
                            if (isMe) const TextSpan(text: " (you)", style: TextStyle(color: AppColors.gold)),
                          ],
                        ),
                      ),
                    ),
                    if (challenge.winnerClientId == e.clientId) const Padding(padding: EdgeInsets.only(right: 8), child: Text("\u{1F3C6}")),
                    Text(_fmtNum(e.score), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.txt)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

String _fmtNum(double n) => n % 1 == 0 ? n.toInt().toString() : n.toString();
