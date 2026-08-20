import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/earned_badge.dart";
import "../../../data/models/merit_badge_def.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

// Gym Citizen is no longer directly one-click-awardable — it's derived from
// the 10 sub-badges (see the dedicated entry card / _GymCitizenChecklist
// below) — so it's excluded from the generic "Award a badge" panel.
final _coachAwardable = kMeritBadges.where((b) => b.category == "coach" && b.key != "gym_citizen").toList();

/// Mirrors MeritBadgesTab.jsx — coach/owner client-profile tab (More →
/// Badges). Award a coach-category badge, remove an active coach-awarded
/// one, an owner-only "force assign any badge" override, an Active grid, a
/// History section for removed coach-awarded badges, and a full-catalog
/// reference. Automatic badges are never awarded here — this mock build
/// has no eligibility engine, so they only ever appear via mock seed data.
class MeritBadgesTab extends ConsumerStatefulWidget {
  const MeritBadgesTab({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<MeritBadgesTab> createState() => _MeritBadgesTabState();
}

class _MeritBadgesTabState extends ConsumerState<MeritBadgesTab> {
  String? _forcePick;
  bool _showGymCitizen = false;
  String? _expiryCheckedForId;

  @override
  void initState() {
    super.initState();
    _checkGymCitizenExpiry();
  }

  @override
  void didUpdateWidget(covariant MeritBadgesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientId != widget.clientId) _checkGymCitizenExpiry();
  }

  // A coach opening this tab is also "someone looking" — catches expiry for
  // a client who never opens their own dashboard. Mirrors the identical
  // opportunistic calls on the client's own dashboard/profile screens.
  Future<void> _checkGymCitizenExpiry() async {
    if (_expiryCheckedForId == widget.clientId) return;
    _expiryCheckedForId = widget.clientId;
    try {
      final r = await SupabaseService.checkGymCitizenExpiry(widget.clientId);
      final expired = (r["expiredCount"] as num?) ?? 0;
      if (expired > 0 && mounted) await _refreshBadgesAndPoints();
    } catch (_) {}
  }

  Future<void> _refreshBadgesAndPoints() async {
    // grant/force-award/revoke all resync points_ledger server-side too
    // (active-badge-count points) — see syncMeritBadgePoints.
    final freshBadges = await SupabaseService.loadMeritBadgesFor(widget.clientId);
    ref.read(earnedBadgesProvider.notifier).replaceForClient(widget.clientId, freshBadges);
    final freshPoints = await SupabaseService.loadPointsLedgerFor(widget.clientId);
    ref.read(pointsLedgerProvider.notifier).replaceForClient(widget.clientId, freshPoints);
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(trainerRosterProvider);
    final matches = roster.where((c) => c.id == widget.clientId);
    if (matches.isEmpty) return const SizedBox.shrink();
    final info = matches.first;
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final trainers = ref.watch(trainersProvider);
    final staffNames = {for (final t in trainers) t.id: t.name};

    final all = ref.watch(earnedBadgesProvider);
    final myBadges = all.where((b) => b.clientId == widget.clientId).toList();
    // Gym Citizen's 10 sub-badge rows live in the same table but aren't real
    // catalog badges — excluded here so they never leak into these two
    // generic grids with a broken icon/raw slug name; they get their own
    // dedicated rendering in _GymCitizenChecklist instead.
    final activeBadges = myBadges.where((b) => b.isActive && kMeritBadges.any((m) => m.key == b.badgeKey)).toList()
      ..sort((a, b) => b.earnedAt.compareTo(a.earnedAt));
    final historyBadges = myBadges.where((b) => !b.isActive && kMeritBadges.any((m) => m.key == b.badgeKey)).toList()
      ..sort((a, b) => (b.revokedAt ?? "").compareTo(a.revokedAt ?? ""));
    final activeKeys = activeBadges.map((b) => b.badgeKey).toSet();
    final awardable = _coachAwardable.where((b) => !activeKeys.contains(b.key)).toList();
    final forceAssignable = kMeritBadges.where((b) => !activeKeys.contains(b.key)).toList();
    final gymCitizenActiveSubCount = myBadges.where((b) => b.isActive && kGymCitizenSubBadgeKeys.contains(b.badgeKey)).length;

    if (_showGymCitizen) {
      return _GymCitizenChecklist(
        clientId: widget.clientId,
        staffNames: staffNames,
        onBack: () => setState(() => _showGymCitizen = false),
      );
    }

    Future<void> refreshBadgesAndPoints() => _refreshBadgesAndPoints();

    void showFailure(Object e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))));
      }
    }

    void award(MeritBadgeDef badge) async {
      final confirmed = await _confirm(context, 'Award "${badge.name}" to ${info.name}?');
      if (!confirmed || !context.mounted) return;
      final note = await _promptText(context, "Optional note (or leave blank):");
      try {
        await SupabaseService.grantMeritBadge(widget.clientId, badge.key, note?.trim().isEmpty == true ? null : note?.trim());
        await refreshBadgesAndPoints();
      } catch (e) {
        showFailure(e);
      }
    }

    void revoke(EarnedBadge badge, String name) async {
      final confirmed = await _confirm(context, 'Remove "$name" from ${info.name}? It moves to History and can be awarded again later.');
      if (!confirmed) return;
      try {
        await SupabaseService.revokeMeritBadge(badge.id);
        await refreshBadgesAndPoints();
      } catch (e) {
        showFailure(e);
      }
    }

    void forceAward() async {
      final pick = _forcePick;
      if (pick == null) return;
      final meta = meritBadgeByKey(pick);
      final confirmed = await _confirm(context, 'Force-assign "${meta?.name ?? pick}" to ${info.name}? This bypasses normal eligibility checks.');
      if (!confirmed || !context.mounted) return;
      final note = await _promptText(context, "Optional note (or leave blank):");
      try {
        await SupabaseService.forceAwardMeritBadge(widget.clientId, pick, note?.trim().isEmpty == true ? null : note?.trim());
        await refreshBadgesAndPoints();
        setState(() => _forcePick = null);
      } catch (e) {
        showFailure(e);
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel("Merit Badges — ${info.name}"),
          InkWell(
            onTap: () => setState(() => _showGymCitizen = true),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x1433733F),
                border: Border.all(color: AppColors.goldDim),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  if (gymCitizenActiveSubCount > 0 && gymCitizenActiveSubCount < 10)
                    GymCitizenProgressRing(
                      activeCount: gymCitizenActiveSubCount,
                      size: 30,
                      child: const MeritBadgeShield(badgeKey: "gym_citizen", size: 20, grayscale: true),
                    )
                  else
                    MeritBadgeShield(badgeKey: "gym_citizen", size: 30, grayscale: gymCitizenActiveSubCount < 10),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Gym Citizen — $gymCitizenActiveSubCount/10 verified", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gold)),
                        const Text("Check off the 10 sub-badges — the badge itself awards automatically at 10/10.", style: TextStyle(fontSize: 11, color: AppColors.mute)),
                      ],
                    ),
                  ),
                  const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mute),
                ],
              ),
            ),
          ),
          if (isOwner && forceAssignable.isNotEmpty)
            AppCard(
              borderColor: AppColors.gold,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(LucideIcons.shieldAlert, size: 13, color: AppColors.gold),
                    SizedBox(width: 6),
                    Text("OWNER OVERRIDE — ASSIGN ANY BADGE", style: TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    "Bypasses normal eligibility checks. A normally-automatic badge assigned this way can still be automatically removed later if it turns out the client doesn't actually qualify.",
                    style: TextStyle(fontSize: 11, color: AppColors.mute),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _forcePick,
                          dropdownColor: AppColors.card,
                          isExpanded: true,
                          style: const TextStyle(fontSize: 13, color: AppColors.txt),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: AppColors.bg,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
                          ),
                          hint: const Text("Choose a badge…", style: TextStyle(fontSize: 13, color: AppColors.mute)),
                          items: forceAssignable.map((b) => DropdownMenuItem(value: b.key, child: Text("${b.name} (${b.category == 'coach' ? 'Coach Awarded' : 'Automatic'})"))).toList(),
                          onChanged: (v) => setState(() => _forcePick = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      BtnGold(onPressed: _forcePick == null ? null : forceAward, child: const Text("Assign")),
                    ],
                  ),
                ],
              ),
            ),
          if (awardable.isNotEmpty) ...[
            const Text("AWARD A BADGE", style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            ...awardable.map((b) => AppCard(
                  borderColor: AppColors.gold,
                  onTap: () => award(b),
                  child: Row(
                    children: [
                      MeritBadgeShield(badgeKey: b.key, size: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gold)),
                            Text(b.description, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                          ],
                        ),
                      ),
                      const Icon(LucideIcons.award, size: 15, color: AppColors.gold),
                    ],
                  ),
                )),
          ],
          SectionLabel("Active (${activeBadges.length})"),
          if (activeBadges.isEmpty)
            const HintBox(text: "No Merit Badges earned yet.")
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: activeBadges.map((b) {
                final meta = meritBadgeByKey(b.badgeKey);
                return Container(
                  width: 148,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      MeritBadgeShield(badgeKey: b.badgeKey, size: 64),
                      const SizedBox(height: 4),
                      Text(meta?.name ?? b.badgeKey, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      Text(b.earnedMethod == "coach" ? "COACH AWARDED" : "AUTOMATIC", style: const TextStyle(fontSize: 9, color: AppColors.gold, fontWeight: FontWeight.w700)),
                      Text(b.earnedAt, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                      if (b.earnedMethod == "coach" && b.grantedByUserId != null) Text("by ${staffNames[b.grantedByUserId] ?? 'a coach'}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                      if (b.note != null) Text('"${b.note}"', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.mute, fontStyle: FontStyle.italic)),
                      if (b.earnedMethod == "coach")
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: OutlinedButton(
                            onPressed: () => revoke(b, meta?.name ?? b.badgeKey),
                            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC97F7F), side: const BorderSide(color: Color(0xFF6B3B3B)), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), minimumSize: Size.zero),
                            child: const Text("Remove", style: TextStyle(fontSize: 10)),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          if (historyBadges.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionLabel("History (${historyBadges.length})"),
            ...historyBadges.map((b) {
              final meta = meritBadgeByKey(b.badgeKey);
              return Opacity(
                opacity: 0.7,
                child: AppCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MeritBadgeShield(badgeKey: b.badgeKey, size: 34, grayscale: true),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(meta?.name ?? b.badgeKey, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            Text(
                              "Earned ${b.earnedAt} · ${b.earnedMethod == 'coach' ? 'Awarded by ${staffNames[b.grantedByUserId] ?? 'a coach'}' : 'Earned automatically'}",
                              style: const TextStyle(fontSize: 11, color: AppColors.mute),
                            ),
                            Text(
                              "Removed ${b.revokedAt}${b.revokedByUserId != null ? ' by ${staffNames[b.revokedByUserId] ?? 'a coach'}' : ' automatically'}",
                              style: const TextStyle(fontSize: 11, color: Color(0xFFC97F7F)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: 16),
          const SectionLabel("All Merit Badges — Reference"),
          ...kMeritBadges.map((b) {
            final earned = activeBadges.where((m) => m.badgeKey == b.key);
            final isEarned = earned.isNotEmpty;
            return AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      MeritBadgeShield(badgeKey: b.key, size: 34, grayscale: !isEarned),
                      if (!isEarned) const Icon(LucideIcons.lock, size: 12, color: Colors.white),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(b.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: isEarned ? AppColors.gold : AppColors.txt)),
                          Text(b.category == "coach" ? "COACH AWARDED" : "AUTOMATIC", style: const TextStyle(fontSize: 10, color: AppColors.mute, fontWeight: FontWeight.w700)),
                        ]),
                        Text(b.description, style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4)),
                        if (isEarned) Text("Earned ${earned.first.earnedAt}", style: const TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700)),
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
}

Future<bool> _confirm(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      content: Text(message, style: const TextStyle(fontSize: 14)),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
        TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Confirm")),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> _promptText(BuildContext context, String label) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      content: AppField(controller: controller),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(""), child: const Text("Skip")),
        TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text("OK")),
      ],
    ),
  );
}

const _monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

String _fmtBadgeDate(String? iso) {
  if (iso == null) return "—";
  final d = DateTime.tryParse(iso);
  if (d == null) return "—";
  return "${_monthNames[d.month - 1]} ${d.day}, ${d.year}";
}

/// Mirrors GymCitizenChecklist.jsx — coach-facing checklist behind
/// MeritBadgesTab's "Gym Citizen" entry card. Each row is its own
/// award/revoke call (grant-merit-badge/revoke-merit-badge, same edge
/// functions every other coach badge uses) — deliberately no confirm dialog
/// or note prompt on either action, unlike the single-badge award/revoke
/// flow above: this is meant to be checked off quickly, live, during a
/// session. The parent "gym_citizen" badge is awarded/revoked server-side
/// automatically as the active count crosses 10 — this screen only ever
/// touches the 10 sub-badge rows directly.
class _GymCitizenChecklist extends ConsumerStatefulWidget {
  const _GymCitizenChecklist({required this.clientId, required this.staffNames, required this.onBack});

  final String clientId;
  final Map<String, String> staffNames;
  final VoidCallback onBack;

  @override
  ConsumerState<_GymCitizenChecklist> createState() => _GymCitizenChecklistState();
}

class _GymCitizenChecklistState extends ConsumerState<_GymCitizenChecklist> {
  String? _busyKey;

  Future<void> _toggle(SubBadgeDef sub, EarnedBadge? active) async {
    setState(() => _busyKey = sub.key);
    try {
      if (active != null) {
        await SupabaseService.revokeMeritBadge(active.id);
      } else {
        await SupabaseService.grantMeritBadge(widget.clientId, sub.key, null);
      }
      final freshBadges = await SupabaseService.loadMeritBadgesFor(widget.clientId);
      ref.read(earnedBadgesProvider.notifier).replaceForClient(widget.clientId, freshBadges);
      final freshPoints = await SupabaseService.loadPointsLedgerFor(widget.clientId);
      ref.read(pointsLedgerProvider.notifier).replaceForClient(widget.clientId, freshPoints);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))));
      }
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  // Expiry is computed here purely for display — the real 6-month sweep
  // runs server-side (check-gym-citizen-expiry), this just shows the coach
  // when it'll happen.
  String _fmtExpiry(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return "—";
    return _fmtBadgeDate(DateTime(d.year, d.month + 6, d.day).toIso8601String());
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(earnedBadgesProvider);
    final myBadges = all.where((b) => b.clientId == widget.clientId && b.isActive).toList();
    final activeCount = kGymCitizenSubBadges.where((sub) => myBadges.any((b) => b.badgeKey == sub.key)).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: widget.onBack,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.mute,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(LucideIcons.chevronLeft, size: 15),
            label: const Text("Back", style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(height: 14),
          SectionLabel("Gym Citizen Progress: $activeCount/10"),
          const SizedBox(height: 4),
          const Text(
            "Check off each behavior as you verify it. The Gym Citizen badge itself is awarded automatically once all 10 are checked, and removed automatically if any drop back off.",
            style: TextStyle(fontSize: 12, color: AppColors.mute, height: 1.5),
          ),
          const SizedBox(height: 14),
          ...kGymCitizenSubBadges.map((sub) {
            final matches = myBadges.where((b) => b.badgeKey == sub.key);
            final row = matches.isEmpty ? null : matches.first;
            final busy = _busyKey == sub.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Opacity(
                opacity: busy ? 0.6 : 1,
                child: AppCard(
                  borderColor: row != null ? AppColors.gold : AppColors.line,
                  onTap: busy ? null : () => _toggle(sub, row),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SubBadgeIcon(subBadgeKey: sub.key, size: 36, earned: row != null),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(sub.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: row != null ? AppColors.gold : AppColors.txt)),
                            Text(sub.description, style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.5)),
                            if (row != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  "Verified ${_fmtBadgeDate(row.earnedAt)} by ${widget.staffNames[row.grantedByUserId] ?? 'a coach'} · expires ${_fmtExpiry(row.earnedAt)}",
                                  style: const TextStyle(fontSize: 11, color: AppColors.mute),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: row != null ? AppColors.gold : AppColors.line, width: 1.5),
                          color: row != null ? AppColors.gold : Colors.transparent,
                        ),
                        child: row != null ? const Icon(LucideIcons.check, size: 14, color: Colors.white) : null,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
