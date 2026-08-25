import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/client_status_utils.dart";
import "../../../core/utils/flag_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors RosterBar.jsx, trimmed to what's built so far: search and the
/// horizontal client-card scroller. Deleting a client lives at the bottom
/// of their Profile tab (profile_tab.dart), not here. Adding a client
/// needs the full IntakeForm (not built yet), so "+ Client" is a placeholder.
class RosterBar extends ConsumerStatefulWidget {
  const RosterBar({super.key});

  @override
  ConsumerState<RosterBar> createState() => _RosterBarState();
}

class _RosterBarState extends ConsumerState<RosterBar> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _fmtEmail(String? email) {
    if (email == null || email.isEmpty) return "";
    final parts = email.split("@");
    if (parts.length < 2) return email;
    final domain = parts[1].length > 4 ? parts[1].substring(0, 4) : parts[1];
    return "${parts[0]}@$domain…com";
  }

  @override
  Widget build(BuildContext context) {
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final roster = ref.watch(trainerRosterProvider);
    final clientRecords = ref.watch(trainerClientRecordsProvider);
    final activeId = ref.watch(selectedClientIdProvider);

    // Platform → Coaches, Access & Security controls this — owner is never
    // scoped, and a coach only gets filtered to their own clients if the
    // owner has explicitly set the scope to "own" (default is "all").
    final coachClientScope = ref.watch(platformSettingsProvider).coachClientScope;
    final scoped = (!isOwner && coachClientScope == "own") ? roster.where((c) => c.primaryTrainerId == trainerAuth).toList() : roster;
    final q = _search.text.trim().toLowerCase();
    final visible = q.isEmpty
        ? scoped
        : scoped.where((c) => c.name.toLowerCase().contains(q) || (c.email ?? "").toLowerCase().contains(q)).toList();

    void showComingSoon(String what) =>
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$what coming in a later pass.")));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppField(
            controller: _search,
            placeholder: "Search clients by name or email…",
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                InkWell(
                  onTap: () => showComingSoon("Add client"),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.goldDim, style: BorderStyle.solid),
                    ),
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.plus, size: 14, color: AppColors.gold),
                        SizedBox(width: 6),
                        Text("Client", style: TextStyle(fontSize: 13, color: AppColors.gold)),
                      ],
                    ),
                  ),
                ),
                ...visible.map((c) {
                  final isActive = activeId == c.id;
                  final rec = clientRecords[c.id];
                  final status = rec != null ? computeClientStatus(rec) : ClientStatus.newClient;
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: InkWell(
                      onTap: () => ref.read(selectedClientIdProvider.notifier).select(c.id),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 180,
                        padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: isActive ? AppColors.gold.withValues(alpha: 0.12) : AppColors.card,
                          border: Border.all(color: isActive ? AppColors.gold : AppColors.line),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Avatar(src: c.photo, name: c.name, size: 32, active: isActive),
                                  Positioned(bottom: -1, right: -1, child: StatusDot(status: status, size: 9)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    c.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: isActive ? AppColors.gold : AppColors.txt,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          _fmtEmail(c.email),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 10, color: AppColors.mute),
                                        ),
                                      ),
                                      if (rec != null && getHighestFlag(rec, c) != null) ...[
                                        const SizedBox(width: 4),
                                        FlagAlert(flag: getHighestFlag(rec, c), compact: true),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                "No clients yet — tap + Client to add your first one.",
                style: TextStyle(fontSize: 12, color: AppColors.mute, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}
