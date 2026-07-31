import "package:flutter/material.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/roster_client.dart";
import "../../../data/models/squad.dart";

/// Mirrors SquadDashboard.jsx `SquadMemberSearch` — search the roster,
/// selecting someone sends them an invite (they aren't added directly).
class SquadMemberSearchScreen extends StatefulWidget {
  const SquadMemberSearchScreen({
    super.key,
    required this.roster,
    required this.squad,
    required this.onSelect,
    required this.onCancel,
  });

  final List<RosterClient> roster;
  final Squad squad;
  final ValueChanged<RosterClient> onSelect;
  final VoidCallback onCancel;

  @override
  State<SquadMemberSearchScreen> createState() => _SquadMemberSearchScreenState();
}

class _SquadMemberSearchScreenState extends State<SquadMemberSearchScreen> {
  final _controller = TextEditingController();
  String _query = "";

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inSquad = widget.squad.memberIds.toSet();
    final invited = widget.squad.pendingInvites.where((i) => i.status == "pending").map((i) => i.clientId).toSet();
    final q = _query.trim().toLowerCase();
    final filtered = q.length < 2
        ? const <RosterClient>[]
        : widget.roster
            .where((c) => !inSquad.contains(c.id) && !invited.contains(c.id))
            .where((c) => c.name.toLowerCase().contains(q) || (c.email ?? "").toLowerCase().contains(q))
            .take(12)
            .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onCancel),
          const SizedBox(height: 10),
          const SectionLabel("Search Existing Clients"),
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: HintBox(
              text: "Selecting someone sends them an invitation — they'll need to accept it before joining the Squad.",
            ),
          ),
          AppField(controller: _controller, placeholder: "Name or email…", onChanged: (v) => setState(() => _query = v)),
          const SizedBox(height: 10),
          if (q.length < 2)
            const HintBox(text: "Type at least 2 characters to search.")
          else if (filtered.isEmpty)
            const HintBox(text: "No matching clients found who aren't already in the Squad or already invited.")
          else
            ...filtered.map((c) => AppCard(
                  onTap: () => widget.onSelect(c),
                  child: Row(
                    children: [
                      Avatar(name: c.name, size: 38),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            Text(c.email ?? "", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                          ],
                        ),
                      ),
                      const Icon(LucideIcons.userPlus, size: 16, color: AppColors.gold),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}
