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

/// Mirrors CoachChallengesPage.jsx + CreateChallengeForm + CoachChallengeDetail.jsx
/// — the coach side of the client-facing Challenges feature: create/manage
/// challenges, pick winners (when winnerMode is coach-judged), award badges,
/// and view the full roster leaderboard for one.
class CoachChallengesScreen extends ConsumerStatefulWidget {
  const CoachChallengesScreen({super.key});

  @override
  ConsumerState<CoachChallengesScreen> createState() => _CoachChallengesScreenState();
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
              await SupabaseService.insertChallenge(c, createdBy: trainerAuth ?? "");
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Couldn't create — check your connection and try again.")),
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
            challengeId: _viewId!,
            onBack: () => setState(() => _viewId = null),
          ),
        );
      }
    }

    final now = isoToday();
    final sorted = [...challenges]..sort((a, b) => b.startDate.compareTo(a.startDate));
    final active = sorted.where((c) => c.startDate.compareTo(now) <= 0 && c.endDate.compareTo(now) >= 0).toList();
    final upcoming = sorted.where((c) => c.startDate.compareTo(now) > 0).toList();
    final ended = sorted.where((c) => c.endDate.compareTo(now) < 0).toList();

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
                icon: const Icon(LucideIcons.plus, size: 14, color: AppColors.gold),
                label: const Text(
                  "Create",
                  style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (challenges.isEmpty)
            const HintBox(text: "No challenges yet. Create one to engage your clients."),
          _ChallengeSection(title: "Active", items: active, onTap: (id) => setState(() => _viewId = id)),
          _ChallengeSection(title: "Upcoming", items: upcoming, onTap: (id) => setState(() => _viewId = id)),
          _ChallengeSection(title: "Ended", items: ended, onTap: (id) => setState(() => _viewId = id)),
        ],
      ),
    );
  }
}

class _ChallengeSection extends StatelessWidget {
  const _ChallengeSection({required this.title, required this.items, required this.onTap});
  final String title;
  final List<Challenge> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(title),
          const SizedBox(height: 6),
          ...items.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ChallengeRow(challenge: c, onTap: () => onTap(c.id)),
            ),
          ),
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
    final end = DateTime.parse("${challenge.endDate}T00:00:00");
    final daysLeft = (end.difference(DateTime.now()).inMilliseconds / 86400000).ceil();
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tpl.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(challenge.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  "${tpl.label} · ${challenge.participantIds.length} registered",
                  style: const TextStyle(fontSize: 11, color: AppColors.mute),
                ),
                Text(
                  "${challenge.startDate} → ${challenge.endDate}${daysLeft > 0 ? " · ${daysLeft}d left" : " · Ended"}",
                  style: const TextStyle(fontSize: 11, color: AppColors.mute),
                ),
                if (challenge.prize != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      "\u{1F381} ${challenge.prize}",
                      style: const TextStyle(fontSize: 11, color: AppColors.gold),
                    ),
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

/// Mirrors CoachChallengeDetail.jsx — info card, coach-picks-winner section
/// (only when applicable), award-badges action, ranked leaderboard, delete.
class _CoachChallengeDetail extends ConsumerStatefulWidget {
  const _CoachChallengeDetail({required this.challengeId, required this.onBack});
  final String challengeId;
  final VoidCallback onBack;

  @override
  ConsumerState<_CoachChallengeDetail> createState() => _CoachChallengeDetailState();
}

class _CoachChallengeDetailState extends ConsumerState<_CoachChallengeDetail> {
  bool _awarding = false;

  Future<void> _pickWinner(String clientId) async {
    try {
      await SupabaseService.updateChallengeRow(widget.challengeId, winnerClientId: clientId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save — check your connection and try again.")),
        );
      }
      return;
    }
    ref.read(challengesProvider.notifier).update(widget.challengeId, (c) => c.copyWith(winnerClientId: clientId));
  }

  Future<bool> _patchBadge(String clientId, String badgeId, String name, String awardedAt) async {
    final rec = ref.read(trainerClientRecordsProvider)[clientId];
    if (rec == null) return true;
    final next = [
      ...rec.challengeBadges.where((b) => b.challengeId != badgeId),
      ChallengeBadge(challengeId: badgeId, name: name, awardedAt: awardedAt),
    ];
    try {
      await SupabaseService.updateClientChallengeBadges(clientId, next);
    } catch (e) {
      return false;
    }
    ref.read(trainerClientRecordsProvider.notifier).update(clientId, (r) => r.copyWith(challengeBadges: next));
    return true;
  }

  Future<void> _awardBadges(Challenge challenge, List<RankedParticipant> ranked) async {
    final winnerId = challenge.winnerMode == "auto"
        ? (ranked.isNotEmpty ? ranked.first.clientId : null)
        : challenge.winnerClientId;
    if (winnerId == null && challenge.participantIds.isEmpty) return;
    setState(() => _awarding = true);
    final awardedAt = stamp();
    var ok = true;
    if (winnerId != null) ok = await _patchBadge(winnerId, challenge.id, challenge.name, awardedAt) && ok;
    for (final cid in challenge.participantIds) {
      ok = await _patchBadge(cid, "complete-${challenge.id}", "Completed: ${challenge.name}", awardedAt) && ok;
    }
    if (!mounted) return;
    setState(() => _awarding = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? "Badges awarded." : "Some badges couldn't be saved — check your connection and try again."),
      ),
    );
  }

  Future<void> _confirmAndDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        content: const Text("Delete this challenge?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Delete")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.deleteChallenge(widget.challengeId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't delete — check your connection and try again.")),
        );
      }
      return;
    }
    ref.read(challengesProvider.notifier).remove(widget.challengeId);
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final challenges = ref.watch(challengesProvider);
    final matches = challenges.where((c) => c.id == widget.challengeId);
    if (matches.isEmpty) return const SizedBox.shrink();
    final challenge = matches.first;

    final roster = ref.watch(trainerRosterProvider);
    final records = ref.watch(trainerClientRecordsProvider);
    final bookings = ref.watch(allBookingsProvider);

    final tpl = templateMeta(challenge.template);
    final now = isoToday();
    final isEnded = challenge.endDate.compareTo(now) < 0;
    final isActive = challenge.startDate.compareTo(now) <= 0 && !isEnded;
    final ranked = rankChallengeParticipants(challenge, roster, records, bookings);
    final showPickWinner = (isEnded || isActive) && challenge.winnerMode == "coach";
    final showPercent =
        challenge.template == "30-day" || challenge.template == "community" || challenge.template == "body-fat";

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
              Text(tpl.emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(challenge.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    Text(
                      "${tpl.label} · ${isEnded ? "Ended" : isActive ? "Active" : "Upcoming"}",
                      style: const TextStyle(fontSize: 12, color: AppColors.mute),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoLine(label: "Dates:", value: "${challenge.startDate} → ${challenge.endDate}"),
                _InfoLine(label: "Metric:", value: challenge.metric),
                _InfoLine(
                  label: "Winner:",
                  value: challenge.winnerMode == "auto" ? "Auto (highest score)" : "Coach picks",
                ),
                if (challenge.prize != null)
                  _InfoLine(label: "Prize:", value: challenge.prize!, labelColor: AppColors.gold),
                if (challenge.description != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      challenge.description!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.mute,
                        fontStyle: FontStyle.italic,
                        height: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (showPickWinner) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.goldDim),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "PICK WINNER",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.gold),
                  ),
                  const SizedBox(height: 8),
                  if (ranked.isEmpty)
                    const Text("No one registered yet.", style: TextStyle(fontSize: 12, color: AppColors.mute))
                  else
                    ...ranked.map((e) {
                      final isWinner = challenge.winnerClientId == e.clientId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          onTap: () => _pickWinner(e.clientId),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isWinner ? AppColors.gold.withValues(alpha: 0.15) : Colors.transparent,
                              border: Border.all(color: isWinner ? AppColors.gold : AppColors.line),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(LucideIcons.trophy, size: 14, color: isWinner ? AppColors.gold : AppColors.mute),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                ),
                                if (isWinner) const Tag(text: "Winner ✓", gold: true),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
          if (isEnded) ...[
            const SizedBox(height: 14),
            BtnGold(
              full: true,
              onPressed: _awarding ? null : () => _awardBadges(challenge, ranked),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.award, size: 15),
                  const SizedBox(width: 6),
                  Text(_awarding ? "Awarding…" : "Award badges to all participants"),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SectionLabel("Leaderboard (${ranked.length} registered)"),
          const SizedBox(height: 6),
          if (ranked.isEmpty)
            const HintBox(text: "No clients registered yet.")
          else
            ...ranked.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: AppCard(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 30,
                        child: Text(
                          "#${e.rank}",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: e.rank <= 3 ? AppColors.gold : AppColors.mute,
                          ),
                        ),
                      ),
                      Avatar(name: e.name, size: 32),
                      const SizedBox(width: 10),
                      Expanded(child: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                      if (e.isWinner)
                        const Padding(padding: EdgeInsets.only(right: 8), child: Text("\u{1F3C6}", style: TextStyle(fontSize: 16))),
                      Text(
                        "${_fmtScore(e.score)}${showPercent ? "%" : ""}",
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.txt),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.only(top: 14),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: OutlinedButton(
              onPressed: _confirmAndDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFC97F7F),
                side: const BorderSide(color: Color(0xFF6B3B3B)),
              ),
              child: const Text("Delete challenge"),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtScore(double score) => score % 1 == 0 ? score.toInt().toString() : score.toString();

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value, this.labelColor = AppColors.txt});
  final String label;
  final String value;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: AppColors.mute, height: 1.6),
          children: [
            TextSpan(text: "$label ", style: TextStyle(color: labelColor, fontWeight: FontWeight.w700)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

/// Mirrors CreateChallengeForm — a two-step wizard: choose a template (all
/// 8, matching CHALLENGE_TEMPLATES exactly), then fill in its details.
class _CreateChallengeForm extends StatefulWidget {
  const _CreateChallengeForm({required this.onCancel, required this.onSave});
  final VoidCallback onCancel;
  final ValueChanged<Challenge> onSave;

  @override
  State<_CreateChallengeForm> createState() => _CreateChallengeFormState();
}

class _CreateChallengeFormState extends State<_CreateChallengeForm> {
  String? _templateKey;
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _prize = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  String _winnerMode = "auto";
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _prize.dispose();
    super.dispose();
  }

  void _selectTemplate(String key) {
    final tpl = templateMeta(key);
    setState(() {
      _templateKey = key;
      _name.text = tpl.label;
      _description.text = tpl.description;
      _winnerMode = tpl.winnerMode;
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = (isStart ? _startDate : _endDate) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  void _save() {
    final tplKey = _templateKey;
    if (tplKey == null) {
      setState(() => _error = "Choose a challenge type.");
      return;
    }
    if (_name.text.trim().isEmpty) {
      setState(() => _error = "Name is required.");
      return;
    }
    if (_startDate == null) {
      setState(() => _error = "Start date is required.");
      return;
    }
    if (_endDate == null) {
      setState(() => _error = "End date is required.");
      return;
    }
    final startIso = isoDate(_startDate!);
    final endIso = isoDate(_endDate!);
    if (endIso.compareTo(startIso) <= 0) {
      setState(() => _error = "End date must be after start date.");
      return;
    }
    setState(() => _error = null);
    widget.onSave(
      Challenge(
        id: "challenge-${DateTime.now().microsecondsSinceEpoch}",
        template: tplKey,
        name: _name.text.trim(),
        description: _description.text.trim().isEmpty ? null : _description.text.trim(),
        prize: _prize.text.trim().isEmpty ? null : _prize.text.trim(),
        metric: templateMeta(tplKey).metric,
        winnerMode: _winnerMode,
        startDate: startIso,
        endDate: endIso,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tplKey = _templateKey;

    if (tplKey == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BackBar(onBack: widget.onCancel),
            const SizedBox(height: 10),
            const SectionLabel("Choose a challenge type"),
            const SizedBox(height: 10),
            ...kChallengeTemplates.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: () => _selectTemplate(e.key),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.value.emoji, style: const TextStyle(fontSize: 32)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.value.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            const SizedBox(height: 3),
                            Text(
                              e.value.description,
                              style: const TextStyle(fontSize: 12, color: AppColors.mute, height: 1.4),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Tracked: ${e.value.metric} · Winner: ${e.value.winnerMode == "auto" ? "Auto" : "Coach picks"}",
                              style: const TextStyle(fontSize: 11, color: AppColors.gold),
                            ),
                          ],
                        ),
                      ),
                      const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final tpl = templateMeta(tplKey);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: () => setState(() => _templateKey = null),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.mute,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(LucideIcons.chevronLeft, size: 15),
            label: const Text("Choose type", style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(tpl.emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 10),
              Expanded(child: SectionLabel("Set up ${tpl.label}")),
            ],
          ),
          const SizedBox(height: 16),
          FieldLabeled(label: "Challenge name *", child: AppField(controller: _name)),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Description — clients will see this when registering *",
            child: AppField(
              controller: _description,
              minLines: 4,
              maxLines: 4,
              placeholder: "Describe what the challenge is, how it works, what clients need to do to win…",
            ),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Prize \u{1F381} (what does the winner get?)",
            child: AppField(controller: _prize, placeholder: "e.g. Free month of training, ONE Fitness gear, Gift card…"),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FieldLabeled(
                  label: "Start date *",
                  child: _DateField(date: _startDate, onTap: () => _pickDate(isStart: true)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FieldLabeled(
                  label: "End date *",
                  child: _DateField(date: _endDate, onTap: () => _pickDate(isStart: false)),
                ),
              ),
            ],
          ),
          if (_startDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                "Registration opens ${isoDate(_startDate!.subtract(const Duration(days: 6)))} · Closes on start date",
                style: const TextStyle(fontSize: 11, color: AppColors.mute),
              ),
            ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Winner determination",
            child: Row(
              children: [
                Expanded(
                  child: _WinnerModeOption(
                    label: "Auto (highest score wins)",
                    selected: _winnerMode == "auto",
                    onTap: () => setState(() => _winnerMode = "auto"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _WinnerModeOption(
                    label: "Coach picks winner",
                    selected: _winnerMode == "coach",
                    onTap: () => setState(() => _winnerMode = "coach"),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _winnerMode == "auto"
                  ? 'Auto: highest "${tpl.metric}" at end date wins.'
                  : "Coach picks winner manually after the challenge ends.",
              style: const TextStyle(fontSize: 11, color: AppColors.mute),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFE05555), fontSize: 13)),
            ),
          const SizedBox(height: 16),
          BtnGold(full: true, onPressed: _save, child: const Text("Create Challenge")),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onTap});
  final DateTime? date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(8)),
        child: Text(
          date != null ? isoDate(date!) : "Select date",
          style: TextStyle(fontSize: 14, color: date != null ? AppColors.txt : AppColors.mute),
        ),
      ),
    );
  }
}

class _WinnerModeOption extends StatelessWidget {
  const _WinnerModeOption({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg,
          border: Border.all(color: selected ? AppColors.gold : AppColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.gold : AppColors.mute,
          ),
        ),
      ),
    );
  }
}
