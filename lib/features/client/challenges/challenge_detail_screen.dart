import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/supabase/supabase_service.dart";
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

  /// The standings, fetched from the server — a client may only read their
  /// own record, so everyone else's score has to be worked out there. Null
  /// while loading, so the board doesn't flash "no one has joined" first.
  List<LeaderboardEntry>? _board;
  bool _boardFailed = false;

  @override
  void initState() {
    super.initState();
    _loadBoard();
  }

  Future<void> _loadBoard() async {
    try {
      final entries = await SupabaseService.loadChallengeLeaderboard(widget.challenge.id);
      if (!mounted) return;
      setState(() {
        _board = entries;
        _boardFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _boardFailed = true);
    }
  }

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
    final tpl = challengeDisplay(challenge, ref.watch(challengeTemplatesProvider));

    final myScore = calcChallengeScore(info.id, challenge, client, bookings);
    final registered = isClientRegistered(challenge, info.id);
    final now = isoToday();
    final canJoin = !registered && canJoinChallenge(challenge, now);
    final isEnded = challenge.endDate.compareTo(now) < 0;
    final needsManualLog = needsClientLoggedScore(challenge);

    // The server's standings when they arrive. The old board was "me, plus
    // challenge.otherLeaderboard" — a field nothing but sample data ever
    // filled — so a real challenge always showed one person, and showed them
    // even when they hadn't joined: a leaderboard of one, ranked #1, under a
    // heading saying 0 participants.
    //
    // While it loads, fall back to the client's own score if they're in the
    // challenge, so their number is there immediately rather than appearing
    // a beat later.
    final board = _board ??
        (registered ? [LeaderboardEntry(clientId: info.id, name: info.name, score: myScore)] : const <LeaderboardEntry>[]);
    var rank = 1;
    final ranked = <(LeaderboardEntry, int)>[];
    for (var i = 0; i < board.length; i++) {
      if (i > 0 && board[i].score < board[i - 1].score) rank = i + 1;
      ranked.add((board[i], rank));
    }

    void logEntry() async {
      final v = double.tryParse(_progressController.text);
      if (v == null || v < 0) return;
      final prev = client.challengeProgress[challenge.id] ?? const [];
      final nextMap = {...client.challengeProgress, challenge.id: [...prev, ChallengeProgressEntry(value: v, loggedAt: stamp())]};
      try {
        await SupabaseService.updateClientChallengeProgress(info.id, nextMap);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't log that — check your connection and try again.")));
        }
        return;
      }
      ref.read(clientRecordProvider.notifier).update((r) => r.copyWith(challengeProgress: nextMap));
      _progressController.clear();
      // The logged number is this client's score, so their place on the
      // board may have just changed.
      _loadBoard();
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
                        "${tpl.typeLabel} · ${challenge.startDate} → ${challenge.endDate}",
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
                onPressed: () async {
                  try {
                    await SupabaseService.joinChallenge(challenge.id);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't join — check your connection and try again.")));
                    }
                    return;
                  }
                  ref.read(challengesProvider.notifier).join(challenge.id, info.id);
                  // Joining is what entitles them to see the standings, so
                  // fetch them now rather than leaving the board empty until
                  // the screen is reopened.
                  _loadBoard();
                },
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
          SectionLabel(
            "Leaderboard (${challenge.participantIds.length} participant${challenge.participantIds.length == 1 ? "" : "s"})",
          ),
          if (ranked.isEmpty)
            // Four different reasons for an empty board, and "Be the first to
            // join!" was shown for all of them — including to someone looking
            // at a challenge eleven people had already joined.
            HintBox(
              text: _boardFailed
                  ? "Couldn't load the standings just now. Pull back and open the challenge again."
                  : _board == null
                      ? "Loading the standings…"
                      : challenge.participantIds.isEmpty
                          ? "Be the first to join!"
                          : "Join this challenge to see how you compare.",
            )
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
