import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/earned_badge.dart";
import "../../../data/models/merit_badge_def.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

final _coachAwardable = kMeritBadges.where((b) => b.category == "coach").toList();

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
    final activeBadges = myBadges.where((b) => b.isActive).toList()..sort((a, b) => b.earnedAt.compareTo(a.earnedAt));
    final historyBadges = myBadges.where((b) => !b.isActive).toList()..sort((a, b) => (b.revokedAt ?? "").compareTo(a.revokedAt ?? ""));
    final activeKeys = activeBadges.map((b) => b.badgeKey).toSet();
    final awardable = _coachAwardable.where((b) => !activeKeys.contains(b.key)).toList();
    final forceAssignable = kMeritBadges.where((b) => !activeKeys.contains(b.key)).toList();

    void award(MeritBadgeDef badge) async {
      final confirmed = await _confirm(context, 'Award "${badge.name}" to ${info.name}?');
      if (!confirmed || !context.mounted) return;
      final note = await _promptText(context, "Optional note (or leave blank):");
      ref.read(earnedBadgesProvider.notifier).award(EarnedBadge(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            clientId: widget.clientId,
            badgeKey: badge.key,
            earnedAt: DateTime.now().toIso8601String().substring(0, 10),
            earnedMethod: "coach",
            grantedByUserId: trainerAuth,
            note: note?.trim().isEmpty == true ? null : note?.trim(),
          ));
    }

    void revoke(EarnedBadge badge, String name) async {
      final confirmed = await _confirm(context, 'Remove "$name" from ${info.name}? It moves to History and can be awarded again later.');
      if (!confirmed) return;
      ref.read(earnedBadgesProvider.notifier).revoke(badge.id, revokedAt: DateTime.now().toIso8601String().substring(0, 10), revokedByUserId: trainerAuth);
    }

    void forceAward() async {
      final pick = _forcePick;
      if (pick == null) return;
      final meta = meritBadgeByKey(pick);
      final confirmed = await _confirm(context, 'Force-assign "${meta?.name ?? pick}" to ${info.name}? This bypasses normal eligibility checks.');
      if (!confirmed || !context.mounted) return;
      final note = await _promptText(context, "Optional note (or leave blank):");
      ref.read(earnedBadgesProvider.notifier).award(EarnedBadge(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            clientId: widget.clientId,
            badgeKey: pick,
            earnedAt: DateTime.now().toIso8601String().substring(0, 10),
            earnedMethod: meta?.category == "coach" ? "coach" : "automatic",
            grantedByUserId: trainerAuth,
            note: note?.trim().isEmpty == true ? null : note?.trim(),
          ));
      setState(() => _forcePick = null);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel("Merit Badges — ${info.name}"),
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
