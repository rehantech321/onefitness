import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/challenge_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/challenge.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors CoachChallengesPage.jsx + CoachChallengeDetail.jsx — the coach
/// side of the client-facing Challenges feature: create/delete challenges
/// and view the full roster leaderboard for one.
class CoachChallengesScreen extends ConsumerStatefulWidget {
  const CoachChallengesScreen({super.key});

  @override
  ConsumerState<CoachChallengesScreen> createState() =>
      _CoachChallengesScreenState();
}

class _CoachChallengesScreenState extends ConsumerState<CoachChallengesScreen> {
  String? _viewId;
  bool _creating = false;

  @override
  Widget build(BuildContext context) {
    final challenges = ref.watch(challengesProvider);
    final trainerAuth = ref.watch(trainerAuthProvider);

    if (_creating) {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _creating = false),
        child: _CreateChallengeForm(
          onCancel: () => setState(() => _creating = false),
          onSave: (c) async {
            try {
              await SupabaseService.insertChallenge(
                c,
                createdBy: trainerAuth ?? "",
              );
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Couldn't create — check your connection and try again.",
                    ),
                  ),
                );
              }
              return;
            }
            ref.read(challengesProvider.notifier).add(c);
            setState(() => _creating = false);
          },
        ),
      );
    }

    if (_viewId != null) {
      final matches = challenges.where((c) => c.id == _viewId);
      if (matches.isNotEmpty) {
        return LocalBackScope(
          isOpen: true,
          onBack: () => setState(() => _viewId = null),
          child: _CoachChallengeDetail(
            challenge: matches.first,
            onBack: () => setState(() => _viewId = null),
            onDelete: () async {
              final id = _viewId!;
              try {
                await SupabaseService.deleteChallenge(id);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Couldn't delete — check your connection and try again.",
                      ),
                    ),
                  );
                }
                return;
              }
              ref.read(challengesProvider.notifier).remove(id);
              setState(() => _viewId = null);
            },
          ),
        );
      }
    }

    final now = isoToday();
    final active = challenges
        .where((c) => c.endDate.compareTo(now) >= 0)
        .toList();
    final past = challenges.where((c) => c.endDate.compareTo(now) < 0).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel("Challenges"),
              TextButton.icon(
                onPressed: () => setState(() => _creating = true),
                icon: const Icon(
                  LucideIcons.plus,
                  size: 14,
                  color: AppColors.gold,
                ),
                label: const Text(
                  "Create",
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (active.isEmpty && past.isEmpty)
            const HintBox(
              text: "No challenges yet — tap Create to launch one.",
            ),
          ...active.map(
            (c) => _ChallengeRow(
              challenge: c,
              onTap: () => setState(() => _viewId = c.id),
            ),
          ),
          if (past.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              "PAST",
              style: TextStyle(
                fontSize: 10,
                color: AppColors.mute,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            ...past.map(
              (c) => _ChallengeRow(
                challenge: c,
                onTap: () => setState(() => _viewId = c.id),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChallengeRow extends StatelessWidget {
  const _ChallengeRow({required this.challenge, required this.onTap});
  final Challenge challenge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tpl = templateMeta(challenge.template);
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Text(tpl.emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  challenge.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  "${challenge.startDate} → ${challenge.endDate} · ${challenge.participantIds.length} registered",
                  style: const TextStyle(fontSize: 11, color: AppColors.mute),
                ),
              ],
            ),
          ),
          const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
        ],
      ),
    );
  }
}

class _CoachChallengeDetail extends ConsumerWidget {
  const _CoachChallengeDetail({
    required this.challenge,
    required this.onBack,
    required this.onDelete,
  });
  final Challenge challenge;
  final VoidCallback onBack;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(trainerRosterProvider);
    final records = ref.watch(trainerClientRecordsProvider);
    final bookings = ref.watch(allBookingsProvider);
    final tpl = templateMeta(challenge.template);

    final leaderboard = [
      for (final id in challenge.participantIds)
        if (roster.where((c) => c.id == id).isNotEmpty)
          LeaderboardEntry(
            clientId: id,
            name: roster.firstWhere((c) => c.id == id).name,
            score: calcChallengeScore(id, challenge, records[id], bookings),
          ),
      ...challenge.otherLeaderboard,
    ]..sort((a, b) => b.score.compareTo(a.score));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: onBack, title: "All challenges"),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(tpl.emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      challenge.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      "${tpl.label} · ${challenge.startDate} → ${challenge.endDate}",
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.mute,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (challenge.description != null)
            AppCard(
              child: Text(
                challenge.description!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.txt,
                  height: 1.5,
                ),
              ),
            ),
          SectionLabel("Leaderboard (${leaderboard.length})"),
          if (leaderboard.isEmpty)
            const HintBox(text: "No one has registered yet.")
          else
            ...leaderboard.asMap().entries.map(
              (e) => AppCard(
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text(
                        "#${e.key + 1}",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: e.key < 3 ? AppColors.gold : AppColors.mute,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        e.value.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      e.value.score % 1 == 0
                          ? e.value.score.toInt().toString()
                          : "${e.value.score}",
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onDelete,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFC97F7F),
            ),
            child: const Text("Delete challenge"),
          ),
        ],
      ),
    );
  }
}

class _CreateChallengeForm extends StatefulWidget {
  const _CreateChallengeForm({required this.onCancel, required this.onSave});
  final VoidCallback onCancel;
  final ValueChanged<Challenge> onSave;

  @override
  State<_CreateChallengeForm> createState() => _CreateChallengeFormState();
}

class _CreateChallengeFormState extends State<_CreateChallengeForm> {
  final _name = TextEditingController();
  String _template = "attendance";
  final _metric = TextEditingController(text: "sessions");
  final _start = TextEditingController(text: isoToday());
  final _end = TextEditingController();
  final _description = TextEditingController();
  final _prize = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _metric.dispose();
    _start.dispose();
    _end.dispose();
    _description.dispose();
    _prize.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onCancel, title: "Create Challenge"),
          const SizedBox(height: 12),
          FieldLabeled(
            label: "Name",
            child: AppField(controller: _name),
          ),
          const SizedBox(height: 10),
          const Text(
            "TEMPLATE",
            style: TextStyle(
              fontSize: 10,
              color: AppColors.mute,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: kChallengeTemplates.entries.map((e) {
              final selected = _template == e.key;
              return InkWell(
                onTap: () => setState(() {
                  _template = e.key;
                  _metric.text = e.key == "attendance" ? "sessions" : "lbs";
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.gold.withValues(alpha: 0.15)
                        : AppColors.card,
                    border: Border.all(
                      color: selected ? AppColors.gold : AppColors.line,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "${e.value.emoji} ${e.value.label}",
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? AppColors.gold : AppColors.txt,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Metric label",
            child: AppField(controller: _metric),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FieldLabeled(
                  label: "Start (YYYY-MM-DD)",
                  child: AppField(controller: _start),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FieldLabeled(
                  label: "End (YYYY-MM-DD)",
                  child: AppField(controller: _end),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Description (optional)",
            child: AppField(controller: _description),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Prize (optional)",
            child: AppField(controller: _prize),
          ),
          const SizedBox(height: 16),
          BtnGold(
            full: true,
            onPressed: _name.text.trim().isEmpty || _end.text.trim().isEmpty
                ? null
                : () => widget.onSave(
                    Challenge(
                      id: "challenge-${DateTime.now().microsecondsSinceEpoch}",
                      name: _name.text.trim(),
                      template: _template,
                      metric: _metric.text.trim().isEmpty
                          ? "score"
                          : _metric.text.trim(),
                      startDate: _start.text.trim(),
                      endDate: _end.text.trim(),
                      description: _description.text.trim().isEmpty
                          ? null
                          : _description.text.trim(),
                      prize: _prize.text.trim().isEmpty
                          ? null
                          : _prize.text.trim(),
                    ),
                  ),
            child: const Text("Create challenge"),
          ),
        ],
      ),
    );
  }
}
