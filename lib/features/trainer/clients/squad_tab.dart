import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/roster_client.dart";
import "../../../data/models/squad.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
import "../../client/squad/squad_member_search_screen.dart";

/// Mirrors SquadTrainerPanel.jsx — staff-mediated management of the ONE
/// squad this client belongs to (not a squad browser). Coaches/owner can
/// create a squad on the client's behalf and search-invite others (never
/// force-add without consent); owner alone can remove members.
class SquadTab extends ConsumerStatefulWidget {
  const SquadTab({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<SquadTab> createState() => _SquadTabState();
}

class _SquadTabState extends ConsumerState<SquadTab> {
  String _sub = "members";
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(trainerRosterProvider);
    final matches = roster.where((c) => c.id == widget.clientId);
    if (matches.isEmpty) return const SizedBox.shrink();
    final info = matches.first;
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final squads = ref.watch(squadsProvider);
    final clientRoster = ref.watch(rosterProvider);
    final squadMatches = squads.where((s) => s.memberIds.contains(widget.clientId));
    final squad = squadMatches.isEmpty ? null : squadMatches.first;

    if (squad == null) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.users2, size: 36, color: AppColors.gold),
              const SizedBox(height: 14),
              Text("${info.name} isn't in a Squad yet", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 16),
              BtnGold(
                onPressed: () {
                  final newSquad = Squad(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    leadId: info.id,
                    memberIds: [info.id],
                    memberMeta: {info.id: const SquadMemberMeta(paymentEnabled: true)},
                  ).withActivity("squad_created", actorName: info.name, description: "${info.name} created the Squad");
                  ref.read(squadsProvider.notifier).createSquad(newSquad);
                },
                child: Text("Create Squad for ${info.name.split(' ').first}"),
              ),
            ],
          ),
        ),
      );
    }

    if (_searching) {
      return SquadMemberSearchScreen(
        roster: clientRoster,
        squad: squad,
        onCancel: () => setState(() => _searching = false),
        onSelect: (c) {
          ref.read(squadsProvider.notifier).update(squad.id, (s) {
            final invites = [...s.pendingInvites, SquadInvite(clientId: c.id, sentAt: _nowLabel())];
            var updated = s.copyWith(pendingInvites: invites);
            if (!s.canAddMember() && isOwner) {
              updated = updated.withActivity("admin_override", actorName: "Owner", description: "Owner overrode the ${s.maxSize}-member cap to invite ${c.name}");
            }
            return updated.withActivity("invite_sent", actorName: info.name, description: "${c.name} was invited to the Squad");
          });
          setState(() => _searching = false);
        },
      );
    }

    final members = squad.memberIds
        .map((id) => id == info.id ? RosterClient(id: id, name: info.name, email: info.email) : clientRoster.firstWhere((r) => r.id == id, orElse: () => RosterClient(id: id, name: "Member")))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.users2, size: 20, color: AppColors.gold),
              const SizedBox(width: 10),
              Expanded(child: Text(squad.displayName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [("members", "Members"), ("membership", "Membership"), ("activity", "Activity")]
                  .map((t) => Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _sub = t.$1),
                          borderRadius: BorderRadius.circular(7),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _sub == t.$1 ? AppColors.gold.withValues(alpha: 0.15) : Colors.transparent,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(t.$2, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _sub == t.$1 ? AppColors.gold : AppColors.mute)),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          if (_sub == "members") ...[
            ...members.map((c) {
              final m = squad.memberMeta[c.id] ?? const SquadMemberMeta();
              final lead = c.id == squad.leadId;
              return AppCard(
                child: Row(
                  children: [
                    Avatar(name: c.name, size: 40, active: m.status != "inactive"),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            children: [
                              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              if (lead)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.12), border: Border.all(color: AppColors.goldDim), borderRadius: BorderRadius.circular(5)),
                                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(LucideIcons.crown, size: 9, color: AppColors.gold),
                                    SizedBox(width: 3),
                                    Text("LEAD", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.gold)),
                                  ]),
                                ),
                            ],
                          ),
                          if (m.relationship.isNotEmpty) Text(m.relationship, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                        ],
                      ),
                    ),
                    if (isOwner && !lead)
                      IconButton(
                        onPressed: () => ref.read(squadsProvider.notifier).update(squad.id, (s) {
                          final newIds = s.memberIds.where((id) => id != c.id).toList();
                          final newMeta = {...s.memberMeta}..remove(c.id);
                          return s.copyWith(memberIds: newIds, memberMeta: newMeta).withActivity("member_removed", actorName: "Owner", description: "${c.name} was removed from the Squad");
                        }),
                        icon: const Icon(LucideIcons.userMinus, size: 14, color: Color(0xFF6B3B3B)),
                      ),
                  ],
                ),
              );
            }),
            if (squad.pendingCount > 0) ...[
              const SectionLabel("Pending Invites"),
              ...squad.pendingInvites.where((i) => i.status == "pending").map((inv) {
                final name = clientRoster.firstWhere((m) => m.id == inv.clientId, orElse: () => const RosterClient(id: "", name: "Client")).name;
                return AppCard(
                  child: Row(
                    children: [
                      Avatar(name: name, size: 34),
                      const SizedBox(width: 12),
                      Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      OutlinedButton(
                        onPressed: () => ref.read(squadsProvider.notifier).update(squad.id, (s) => s.copyWith(pendingInvites: s.pendingInvites.where((x) => x.clientId != inv.clientId).toList())),
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.mute, side: const BorderSide(color: AppColors.line)),
                        child: const Text("Cancel", style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                );
              }),
            ],
            AppCard(
              borderColor: AppColors.goldDim,
              onTap: () => setState(() => _searching = true),
              child: const Row(children: [
                Icon(LucideIcons.userPlus, size: 17, color: AppColors.gold),
                SizedBox(width: 10),
                Expanded(child: Text("Add existing client", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mute),
              ]),
            ),
            if (!squad.canAddMember())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  "Squad is at the ${squad.maxSize}-member limit (including pending invites).${isOwner ? ' As owner you can override this by inviting anyway.' : ''}",
                  style: const TextStyle(fontSize: 11, color: AppColors.mute),
                ),
              ),
            if (isOwner) ...[
              const SizedBox(height: 8),
              BtnGhost(
                onPressed: () => _promptSetMaxSize(context, squad),
                child: const Text("Set size limit"),
              ),
            ],
          ],
          if (_sub == "membership")
            squad.membership == null
                ? const HintBox(text: "No shared membership or package assigned to this Squad yet.")
                : AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(squad.membership!.planName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text("${squad.membership!.sessionsRemaining} / ${squad.membership!.sessionsTotal} sessions remaining", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                      ],
                    ),
                  ),
          if (_sub == "activity")
            squad.activity.isEmpty
                ? const HintBox(text: "No activity recorded yet.")
                : Column(
                    children: squad.activity
                        .map((e) => Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                              child: Row(
                                children: [
                                  Expanded(child: Text(e.description ?? e.type, style: const TextStyle(fontSize: 13))),
                                  Text(e.at, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
        ],
      ),
    );
  }

  void _promptSetMaxSize(BuildContext context, Squad squad) {
    final controller = TextEditingController(text: "${squad.maxSize}");
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text("Set new max Squad size"),
        content: AppField(controller: controller, keyboardType: TextInputType.number),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v != null && v > 0) {
                ref.read(squadsProvider.notifier).update(squad.id, (s) => Squad(
                      id: s.id,
                      name: s.name,
                      leadId: s.leadId,
                      memberIds: s.memberIds,
                      memberMeta: s.memberMeta,
                      maxSize: v,
                      membership: s.membership,
                      pendingInvites: s.pendingInvites,
                      activity: s.activity,
                    ).withActivity("admin_override", actorName: "Owner", description: "Owner set the Squad size limit to $v"));
              }
              Navigator.of(ctx).pop();
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}

String _nowLabel() {
  final d = DateTime.now();
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  return "${months[d.month - 1]} ${d.day}";
}
