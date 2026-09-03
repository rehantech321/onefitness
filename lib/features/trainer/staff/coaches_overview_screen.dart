import "dart:math";

import "package:flutter/foundation.dart" show kIsWeb;
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/attention_utils.dart";
import "../../../core/utils/booking_utils.dart" show addDaysIso;
import "../../../core/utils/coach_merit_badge_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/report_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors CoachesOverview.jsx (owner-only) — a real coach-approval-code
/// generator backed by the `coach_approval_code` table (same singleton row
/// and mark_coach_code_used() RPC that CoachSignupScreen already checks
/// against) and a per-coach oversight list showing client counts and
/// outstanding flags.
class CoachesOverviewScreen extends ConsumerStatefulWidget {
  const CoachesOverviewScreen({super.key});

  @override
  ConsumerState<CoachesOverviewScreen> createState() => _CoachesOverviewScreenState();
}

class _CoachesOverviewScreenState extends ConsumerState<CoachesOverviewScreen> {
  Map<String, dynamic>? _codeRow;
  bool _loading = true;
  bool _busy = false;
  bool _justGenerated = false;
  bool _linkCopied = false;
  String? _openId;
  final _daysValid = TextEditingController(text: "7");

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _daysValid.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await SupabaseService.loadCoachApprovalCode();
      if (mounted) setState(() => _codeRow = row);
    } catch (_) {
      // No row yet (owner has never generated one) — fall back to the
      // same DEFAULT_COACH_CODE placeholder the web app shows.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    final days = max(1, int.tryParse(_daysValid.text.trim()) ?? 7);
    final code = (100000 + Random.secure().nextInt(900000)).toString();
    final generatedAt = isoToday();
    final expiresAt = addDaysIso(generatedAt, days);
    setState(() => _busy = true);
    try {
      await SupabaseService.saveCoachApprovalCode(code: code, expiresAt: expiresAt, generatedAt: generatedAt);
      if (!mounted) return;
      setState(() {
        _codeRow = {"code": code, "expires_at": expiresAt, "generated_at": generatedAt, "used_at": null};
        _justGenerated = true;
      });
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _justGenerated = false);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyJoinLink() async {
    final code = (_codeRow?["code"] as String?) ?? "000000";
    // Uri.base only resolves to a real, shareable http(s) URL on Flutter
    // web (matches web app's joinLink()); the native build has no hosted
    // page for a brand-new coach to land on, so the code itself — the
    // thing CoachSignupScreen actually asks them to type — is copied.
    final text = kIsWeb ? Uri.base.replace(queryParameters: {"coachCode": code}).toString() : code;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _linkCopied = true);
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _linkCopied = false);
    });
  }

  Future<void> _markReviewed(Trainer t) async {
    try {
      await SupabaseService.updateTrainerRow(t.id, reviewedByOwner: true);
    } catch (_) {
      return;
    }
    ref.read(trainersProvider.notifier).upsert(Trainer(
          id: t.id,
          name: t.name,
          photo: t.photo,
          phone: t.phone,
          email: t.email,
          locationName: t.locationName,
          locationAddress: t.locationAddress,
          locations: t.locations,
          bio: t.bio,
          beforeAfters: t.beforeAfters,
          availability: t.availability,
          commissionRate: t.commissionRate,
          disciplines: t.disciplines,
          sessionTypes: t.sessionTypes,
          reviewedByOwner: true,
          signupAt: t.signupAt,
          payoutMode: t.payoutMode,
          payoutRateCents: t.payoutRateCents,
          referralCommissionPercent: t.referralCommissionPercent,
          coachCode: t.coachCode,
          unavailability: t.unavailability,
        ));
  }

  Future<void> _deleteCoach(Trainer t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text("Delete coach?"),
        content: Text(
          "Delete ${t.name}? This permanently removes their profile and login, and stops every future session/availability of theirs from being offered or bookable — everywhere in the app, immediately. Their past sessions with clients are removed too. They can't be reactivated; to come back, they'd have to sign up again from scratch as a brand-new profile. This can't be undone.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Delete")),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await SupabaseService.deleteCoachAccount(t.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))));
      }
      return;
    }
    ref.read(trainersProvider.notifier).remove(t.id);
    // Best-effort freshness — the server-side cleanup already cleared every
    // client's dangling primary/referred trainer id, this just pulls that
    // down so the roster doesn't keep scoping a client out of an
    // "own"-scoped coach's view.
    try {
      final freshRoster = await SupabaseService.loadRoster();
      ref.read(trainerRosterProvider.notifier).setAll(freshRoster);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final trainers = ref.watch(trainersProvider);
    final newCount = trainers.where((t) => !t.reviewedByOwner).length;
    final roster = ref.watch(trainerRosterProvider);
    final records = ref.watch(trainerClientRecordsProvider);
    final bookings = ref.watch(allBookingsProvider);
    final prEvents = ref.watch(coachPrEventsProvider);
    final challenges = ref.watch(challengesProvider);
    final settings = ref.watch(platformSettingsProvider);

    final code = (_codeRow?["code"] as String?) ?? "000000";
    final expiresAt = _codeRow?["expires_at"] as String?;
    final isUsed = _codeRow?["used_at"] != null;
    final isExpired = expiresAt != null && isoToday().compareTo(expiresAt) > 0;
    final statusText = isUsed ? "Already used" : isExpired ? "Expired" : expiresAt != null ? "Expires ${niceDate(expiresAt)}" : "Never expires";
    final statusColor = isUsed || isExpired ? AppColors.errorText : AppColors.mute;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Coach Approval Code"),
          AppCard(
            borderColor: AppColors.goldDim,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Coach Approval Code", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                const Text(
                  "Give this code (or the link below) to a coach only after you've met them and approved them. "
                  "It works from their own device, no account needed yet — good for one signup, until it expires or you generate a new one.",
                  style: TextStyle(color: AppColors.mute, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 10),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold)),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        code,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 3, color: AppColors.gold, fontFamily: "monospace"),
                      ),
                      const SizedBox(width: 10),
                      Text(statusText, style: TextStyle(fontSize: 12, color: statusColor)),
                    ],
                  ),
                const SizedBox(height: 10),
                BtnGhost(
                  onPressed: _copyJoinLink,
                  full: true,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.link, size: 14),
                      const SizedBox(width: 8),
                      Text(_linkCopied ? "Link copied!" : "Copy join link"),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text("Valid for", style: TextStyle(fontSize: 12, color: AppColors.mute)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 60,
                      child: AppField(controller: _daysValid, keyboardType: TextInputType.number),
                    ),
                    const SizedBox(width: 8),
                    const Text("days", style: TextStyle(fontSize: 12, color: AppColors.mute)),
                  ],
                ),
                const SizedBox(height: 10),
                BtnGold(
                  onPressed: _busy ? null : _generate,
                  full: true,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.refreshCw, size: 15),
                      const SizedBox(width: 6),
                      Text(_busy ? "Generating…" : "Generate New Code"),
                    ],
                  ),
                ),
                if (_justGenerated)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      "✓ New code generated — old code no longer works",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const SectionLabel("All Coaches"),
              if (newCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.danger.withValues(alpha: 0.4))),
                  child: Text("$newCount new", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.danger)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (trainers.isEmpty) const HintBox(text: "No coaches yet."),
          ...trainers.map((t) {
            final myRoster = roster.where((c) => c.primaryTrainerId == t.id).toList();
            final flags = [...computeNeedsAttention(myRoster, records), ...computeUnloggedAttendance(myRoster, bookings)];
            final isNew = !t.reviewedByOwner;
            final open = _openId == t.id;
            return AppCard(
              onTap: () {
                setState(() => _openId = open ? null : t.id);
                if (isNew) _markReviewed(t);
              },
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
                            Row(
                              children: [
                                Flexible(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), overflow: TextOverflow.ellipsis)),
                                if (isNew) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(5), border: Border.all(color: AppColors.danger.withValues(alpha: 0.4))),
                                    child: const Text("New", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.danger)),
                                  ),
                                ],
                              ],
                            ),
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
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: const Icon(LucideIcons.chevronDown, size: 16, color: AppColors.mute),
                      ),
                    ],
                  ),
                  if (open) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: AppColors.line),
                    const SizedBox(height: 12),
                    Text("Email: ${t.email ?? '—'}", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                    const SizedBox(height: 4),
                    Text("Phone: ${t.phone ?? '—'}", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                    if (t.signupAt != null) ...[
                      const SizedBox(height: 4),
                      Text("Signed up: ${niceDate(t.signupAt!)}", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                    ],
                    const SizedBox(height: 10),
                    const Text("Coach Merit Badges — this month:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: computeAllCoachBadges(
                        coach: t,
                        roster: roster,
                        clientRecords: records,
                        bookings: bookings,
                        prEvents: prEvents,
                        challenges: challenges,
                        range: presetRange("month"),
                        habitPercent: settings.meritBadgeHabitPercent,
                        habitConsecutiveWeeks: settings.meritBadgeHabitWeeks,
                      ).map((b) => Tooltip(
                            message: "${b.label}: ${b.detail}",
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CoachBadgeShield(badgeKey: b.badgeKey, size: 30, grayscale: !b.qualifies),
                                const SizedBox(height: 2),
                                Text(b.label, style: TextStyle(fontSize: 9, color: b.qualifies ? AppColors.gold : AppColors.mute, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          )).toList(),
                    ),
                    if (flags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text("Needs attention on their roster:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ...flags.map((f) => Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text("• ${f.label}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                          )),
                    ],
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: () => _deleteCoach(t),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFC97F7F)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [Icon(LucideIcons.trash2, size: 13), SizedBox(width: 6), Text("Remove coach", style: TextStyle(fontSize: 12))],
                        ),
                      ),
                    ),
                  ] else if (flags.isNotEmpty) ...[
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
