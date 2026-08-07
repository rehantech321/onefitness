import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/roster_client.dart";
import "../../../data/models/squad.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/supabase_bootstrap_provider.dart";
import "squad_member_search_screen.dart";

void _showMutateError(BuildContext context) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save — check your connection and try again.")));
  }
}

/// Mirrors SquadDashboard.jsx (client-facing "My Squad" drawer tab) —
/// trimmed to the parts meaningful without a second real account to accept
/// invites: creating a Squad, sending/cancelling invites, editing member
/// relationships/payment settings, and the activity feed.
class SquadDashboardScreen extends ConsumerStatefulWidget {
  const SquadDashboardScreen({super.key});

  @override
  ConsumerState<SquadDashboardScreen> createState() => _SquadDashboardScreenState();
}

class _SquadDashboardScreenState extends ConsumerState<SquadDashboardScreen> {
  String _sub = "members";
  bool _searching = false;
  bool _creating = false;
  final _newSquadNameController = TextEditingController();
  bool _nameEditing = false;
  final _nameDraftController = TextEditingController();

  @override
  void dispose() {
    _newSquadNameController.dispose();
    _nameDraftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(clientInfoProvider);
    final squads = ref.watch(squadsProvider);
    final roster = ref.watch(rosterProvider);
    final squadMatches = squads.where((s) => s.memberIds.contains(info.id));
    final squad = squadMatches.isEmpty ? null : squadMatches.first;

    if (squad == null) {
      if (_creating) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BackBar(onBack: () => setState(() => _creating = false)),
              const SizedBox(height: 10),
              const SectionLabel("Create a Squad"),
              FieldLabeled(
                label: "Squad name (optional)",
                child: AppField(controller: _newSquadNameController, placeholder: "e.g. The Smith Family"),
              ),
              const SizedBox(height: 10),
              const HintBox(text: "You'll be the Lead Account. You can invite existing clients after creating the Squad."),
              const SizedBox(height: 14),
              BtnGold(
                onPressed: () async {
                  final name = _newSquadNameController.text.trim();
                  final newSquad = Squad(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: name.isEmpty ? null : name,
                    leadId: info.id,
                    memberIds: [info.id],
                    memberMeta: {info.id: const SquadMemberMeta(paymentEnabled: true)},
                  ).withActivity("squad_created", actorName: info.name, description: "${info.name} created the Squad");
                  try {
                    await SupabaseService.insertSquad(newSquad);
                  } catch (e) {
                    _showMutateError(context);
                    return;
                  }
                  ref.read(squadsProvider.notifier).createSquad(newSquad);
                  setState(() => _creating = false);
                },
                full: true,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [Icon(LucideIcons.users2, size: 15, color: Colors.white), SizedBox(width: 6), Text("Create Squad")],
                ),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.users2, size: 40, color: AppColors.gold),
              const SizedBox(height: 16),
              const Text("You're not in a Squad yet", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 8),
              const Text(
                "Squads let you share a membership or session package with family or training partners, "
                "while keeping your own profile and history separate.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.mute, height: 1.6),
              ),
              const SizedBox(height: 24),
              BtnGold(
                onPressed: () => setState(() => _creating = true),
                full: true,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [Icon(LucideIcons.plus, size: 15, color: Colors.white), SizedBox(width: 6), Text("Create a Squad")],
                ),
              ),
              const SizedBox(height: 10),
              const Text("Or ask your coach to add you to one.", style: TextStyle(fontSize: 12, color: AppColors.mute)),
            ],
          ),
        ),
      );
    }

    final isLead = squad.leadId == info.id;

    if (_searching && isLead) {
      return SquadMemberSearchScreen(
        roster: roster,
        squad: squad,
        onCancel: () => setState(() => _searching = false),
        onSelect: (c) async {
          if (!squad.canAddMember()) return;
          final ok = await mutateSquad(ref, squad, (s) {
            final invites = [...s.pendingInvites, SquadInvite(clientId: c.id, sentAt: _nowLabel())];
            return s.copyWith(pendingInvites: invites).withActivity(
                  "invite_sent",
                  actorName: info.name,
                  description: "${info.name} invited ${c.name} to the Squad",
                );
          });
          if (!ok) {
            _showMutateError(context);
            return;
          }
          setState(() => _searching = false);
        },
      );
    }

    final members = squad.memberIds.map((id) => id == info.id ? RosterClient(id: id, name: info.name, email: info.email) : roster.firstWhere((r) => r.id == id, orElse: () => RosterClient(id: id, name: "Member"))).toList();
    final meta = squad.memberMeta;

    final tabs = [
      ("members", "Members"),
      ("membership", "Membership"),
      if (isLead) ("payments", "Payments"),
      ("activity", "Activity"),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.users2, size: 20, color: AppColors.gold),
              const SizedBox(width: 10),
              if (_nameEditing) ...[
                Expanded(child: AppField(controller: _nameDraftController, placeholder: "Squad name…")),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: () async {
                    final ok = await mutateSquad(ref, squad, (s) => s.copyWith(name: _nameDraftController.text.trim()));
                    if (!ok) {
                      _showMutateError(context);
                      return;
                    }
                    setState(() => _nameEditing = false);
                  },
                  child: const Text("Save", style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700)),
                ),
              ] else ...[
                Expanded(child: Text(squad.displayName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
                if (isLead)
                  IconButton(
                    onPressed: () {
                      _nameDraftController.text = squad.name ?? "";
                      setState(() => _nameEditing = true);
                    },
                    icon: const Icon(LucideIcons.edit3, size: 14, color: AppColors.mute),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: tabs
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
                            child: Text(
                              t.$2,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _sub == t.$1 ? AppColors.gold : AppColors.mute),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          if (_sub == "members") _MembersTab(squad: squad, members: members, roster: roster, meta: meta, isLead: isLead, onSearch: () => setState(() => _searching = true)),
          if (_sub == "membership") _MembershipTab(squad: squad),
          if (_sub == "payments" && isLead) _PaymentsTab(squad: squad, members: members, meta: meta),
          if (_sub == "activity") _ActivityTab(activity: squad.activity),
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

class _MembersTab extends ConsumerWidget {
  const _MembersTab({required this.squad, required this.members, required this.roster, required this.meta, required this.isLead, required this.onSearch});
  final Squad squad;
  final List<RosterClient> members;
  final List<RosterClient> roster;
  final Map<String, SquadMemberMeta> meta;
  final bool isLead;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(clientInfoProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...members.map((c) {
          final m = meta[c.id] ?? const SquadMemberMeta();
          final lead = c.id == squad.leadId;
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Avatar(name: c.name, size: 44, active: m.status != "inactive"),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            children: [
                              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              if (lead)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.gold.withValues(alpha: 0.12),
                                    border: Border.all(color: AppColors.goldDim),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(LucideIcons.crown, size: 9, color: AppColors.gold),
                                    SizedBox(width: 3),
                                    Text("LEAD", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.gold)),
                                  ]),
                                ),
                              if (!lead && m.status == "inactive") const Tag(text: "Inactive"),
                            ],
                          ),
                          if (m.relationship.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(m.relationship, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                            ),
                        ],
                      ),
                    ),
                    if (isLead && !lead)
                      IconButton(
                        onPressed: () async {
                          final ok = await mutateSquad(ref, squad, (s) {
                            final newIds = s.memberIds.where((id) => id != c.id).toList();
                            final newMeta = {...s.memberMeta}..remove(c.id);
                            return s.copyWith(memberIds: newIds, memberMeta: newMeta).withActivity(
                                  "member_removed",
                                  actorName: info.name,
                                  description: "${c.name} was removed from the Squad",
                                );
                          });
                          if (!ok && context.mounted) _showMutateError(context);
                        },
                        icon: const Icon(LucideIcons.userMinus, size: 14, color: Color(0xFF6B3B3B)),
                      ),
                  ],
                ),
                if (isLead)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: AppField(
                      placeholder: "${c.name}'s relationship (e.g. Spouse, Child)",
                      controller: TextEditingController(text: m.relationship),
                      onChanged: (v) => mutateSquad(
                        ref,
                        squad,
                        (s) => s.copyWith(memberMeta: {...s.memberMeta, c.id: m.copyWith(relationship: v)}),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
        if (isLead && squad.pendingCount > 0) ...[
          const SizedBox(height: 8),
          const SectionLabel("Pending Invites"),
          ...squad.pendingInvites.where((i) => i.status == "pending").map((inv) {
            return AppCard(
              child: Row(
                children: [
                  Avatar(name: roster.firstWhere((m) => m.id == inv.clientId, orElse: () => const RosterClient(id: "", name: "?")).name, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          roster.firstWhere((m) => m.id == inv.clientId, orElse: () => const RosterClient(id: "", name: "Client")).name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        Text("Awaiting response — invited ${inv.sentAt}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final ok = await mutateSquad(
                        ref,
                        squad,
                        (s) => s.copyWith(pendingInvites: s.pendingInvites.where((x) => x.clientId != inv.clientId).toList()),
                      );
                      if (!ok && context.mounted) _showMutateError(context);
                    },
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.mute, side: const BorderSide(color: AppColors.line)),
                    child: const Text("Cancel", style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            );
          }),
        ],
        if (isLead) ...[
          const SizedBox(height: 4),
          AppCard(
            borderColor: AppColors.goldDim,
            onTap: onSearch,
            child: const Row(
              children: [
                Icon(LucideIcons.userPlus, size: 17, color: AppColors.gold),
                SizedBox(width: 10),
                Expanded(child: Text("Add existing client", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mute),
              ],
            ),
          ),
          if (!squad.canAddMember())
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: Text(
                "Squad is at the ${squad.maxSize}-member limit (including pending invites). An admin can override this.",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: AppColors.mute),
              ),
            ),
          const SizedBox(height: 12),
          TextButton(
            // Deleting the squad row outright is coach/owner-only
            // (squads_delete_staff_only) — even the Lead can't do it, so
            // this logs a "dissolved" activity entry instead, matching the
            // real backend's own intended behavior for this action.
            onPressed: () async {
              final ok = await mutateSquad(ref, squad, (s) => s.withActivity("squad_dissolved", actorName: info.name, description: "${info.name} dissolved the Squad"));
              if (!ok && context.mounted) _showMutateError(context);
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF6B3B3B), padding: EdgeInsets.zero),
            child: const Text("Dissolve Squad", style: TextStyle(fontSize: 12)),
          ),
        ],
      ],
    );
  }
}

class _MembershipTab extends StatelessWidget {
  const _MembershipTab({required this.squad});
  final Squad squad;

  @override
  Widget build(BuildContext context) {
    final ms = squad.membership;
    if (ms == null) {
      return const HintBox(text: "No shared membership or package yet. The Lead Account can assign one from the Membership Hub.");
    }
    final pct = ms.sessionsTotal > 0 ? (ms.sessionsRemaining / ms.sessionsTotal) : 0.0;
    final color = pct > 0.4 ? AppColors.grn : (pct > 0.15 ? const Color(0xFFD68A4F) : AppColors.errorText);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(ms.planName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              Tag(text: ms.kind == "membership" ? "Membership" : "Package", gold: true),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Sessions remaining", style: TextStyle(fontSize: 12, color: AppColors.mute)),
              Text("${ms.sessionsRemaining} / ${ms.sessionsTotal}", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: pct, minHeight: 6, backgroundColor: AppColors.line, valueColor: AlwaysStoppedAnimation(color)),
          ),
          if (ms.renewalDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text("Renews ${ms.renewalDate}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
            ),
        ],
      ),
    );
  }
}

class _PaymentsTab extends ConsumerWidget {
  const _PaymentsTab({required this.squad, required this.members, required this.meta});
  final Squad squad;
  final List<RosterClient> members;
  final Map<String, SquadMemberMeta> meta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(clientInfoProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          borderColor: AppColors.goldDim,
          child: const Text(
            "Choose which members' account balances can be applied toward membership renewals. Individual balances stay "
            "separate — only contributions you enable here apply to Squad charges.",
            style: TextStyle(fontSize: 12, color: AppColors.mute, height: 1.5),
          ),
        ),
        ...members.map((c) {
          final m = meta[c.id] ?? const SquadMemberMeta();
          final enabled = m.paymentEnabled;
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Avatar(name: c.name, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          const Text("Available balance: \$0.00", style: TextStyle(fontSize: 11, color: AppColors.mute)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        final ok = await mutateSquad(ref, squad, (s) {
                          final updated = s.copyWith(memberMeta: {...s.memberMeta, c.id: m.copyWith(paymentEnabled: !enabled)});
                          return updated.withActivity(
                            "payment_permission_changed",
                            actorName: info.name,
                            description: "Payment contribution for ${c.name} ${!enabled ? 'enabled' : 'disabled'}",
                          );
                        });
                        if (!ok && context.mounted) _showMutateError(context);
                      },
                      icon: Icon(enabled ? LucideIcons.toggleRight : LucideIcons.toggleLeft, size: 28, color: enabled ? AppColors.gold : AppColors.mute),
                    ),
                  ],
                ),
                if (enabled)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: MiniField(
                      label: "Min. balance before credit applies (\$)",
                      value: m.minBalance == 0 ? "" : "${m.minBalance}",
                      ph: "0",
                      onChange: (v) => mutateSquad(
                        ref,
                        squad,
                        (s) => s.copyWith(memberMeta: {...s.memberMeta, c.id: m.copyWith(minBalance: num.tryParse(v) ?? 0)}),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.activity});
  final List<SquadActivityEntry> activity;

  @override
  Widget build(BuildContext context) {
    if (activity.isEmpty) return const HintBox(text: "No activity recorded yet.");
    return Column(
      children: activity
          .map((e) => Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: const Icon(LucideIcons.shield, size: 15, color: AppColors.gold),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.description ?? e.type.replaceAll("_", " "), style: const TextStyle(fontSize: 13, color: AppColors.txt)),
                          if (e.actorName != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text("by ${e.actorName}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                            ),
                        ],
                      ),
                    ),
                    Text(e.at, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}
