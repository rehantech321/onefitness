import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/client_status_utils.dart";
import "../../../core/utils/flag_utils.dart";
import "../../../core/utils/program_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors Profile.jsx (viewed from the coach side, via TrainerView). Trimmed
/// to what's built so far: avatar header, progress-status card, membership
/// card with a simplified freeze/unfreeze flow and owner-only session-count
/// override, contact rows, program-notes banner, and Edit Profile. FlagAlert,
/// OnboardingAlerts, CompletedIntakeLinks, and Add Charge are deferred —
/// they depend on the intake/flag and billing systems, not yet ported.
class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  bool _editing = false;
  bool _freezing = false;
  final _freezeStart = TextEditingController();
  final _freezeEnd = TextEditingController();
  String? _freezeErr;

  @override
  void dispose() {
    _freezeStart.dispose();
    _freezeEnd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context, [WidgetRef? _]) => _build(context, ref);

  Widget _build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(trainerRosterProvider);
    final matches = roster.where((c) => c.id == widget.clientId);
    if (matches.isEmpty) return const SizedBox.shrink();
    final info = matches.first;
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final records = ref.watch(trainerClientRecordsProvider);
    final record = records[widget.clientId];
    final status = record != null ? computeClientStatus(record) : ClientStatus.newClient;
    final meta = kStatusMeta[status]!;
    final plan = ref.watch(membershipPlansProvider.notifier).byId(info.membershipPlanId);
    final notes = record != null ? getClientProgramNotes(record) : const [];

    void update(ClientInfoUpdater updater) => ref.read(trainerRosterProvider.notifier).update(widget.clientId, updater);

    if (_editing) {
      return _EditSection(
        info: info,
        onCancel: () => setState(() => _editing = false),
        onSave: (name, email, phone, city) {
          update((c) => c.copyWith(name: name, email: email, phone: phone, city: city));
          setState(() => _editing = false);
        },
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(src: info.photo, name: info.name, size: 64, active: true),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
                  const Text("ONE Fitness client", style: TextStyle(fontSize: 12, color: AppColors.mute)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (record != null) FlagAlert(flag: getHighestFlag(record, info)),
          if (notes.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                border: Border.all(color: const Color(0xFF8B3B3B)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Text("📝", style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Client left ${notes.length == 1 ? 'a note' : '${notes.length} notes'} on their workout program — review before session",
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFE05555)),
                    ),
                  ),
                ],
              ),
            ),
          AppCard(
            child: Row(
              children: [
                StatusDot(status: status, size: 14),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("PROGRESS STATUS", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
                    Text(meta.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(meta.desc, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                  ],
                ),
              ],
            ),
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.creditCard, size: 17, color: AppColors.gold),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("MEMBERSHIP", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
                          Text(plan?.name ?? "No membership selected", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          if (info.membershipPaused)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                "Frozen ${info.membershipPausedAt ?? ''}${info.membershipFreezeEndsAt != null ? ' – ${info.membershipFreezeEndsAt}' : ''}",
                                style: const TextStyle(fontSize: 11, color: Color(0xFFD68A4F), fontWeight: FontWeight.w700),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (plan != null) ...[
                  const SizedBox(height: 12),
                  if (_freezeErr != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_freezeErr!, style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12)),
                    ),
                  if (info.membershipPaused)
                    BtnGold(
                      full: true,
                      onPressed: () {
                        update((c) => c.copyWith(membershipPaused: false, clearMembershipPausedAt: true, clearMembershipFreezeEndsAt: true));
                      },
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [Icon(LucideIcons.refreshCw, size: 14), SizedBox(width: 6), Text("Unfreeze now")],
                      ),
                    )
                  else if (_freezing)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(10)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Both dates are required — this shifts ${info.name}'s billing date too, so they don't lose any paid-for time.",
                            style: const TextStyle(fontSize: 12, color: AppColors.mute),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: FieldLabeled(label: "Start (YYYY-MM-DD)", child: AppField(controller: _freezeStart))),
                              const SizedBox(width: 8),
                              Expanded(child: FieldLabeled(label: "End (YYYY-MM-DD)", child: AppField(controller: _freezeEnd))),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              BtnGold(
                                onPressed: () {
                                  if (_freezeEnd.text.trim().isEmpty) {
                                    setState(() => _freezeErr = "An end date is required.");
                                    return;
                                  }
                                  update((c) => c.copyWith(
                                        membershipPaused: true,
                                        membershipPausedAt: _freezeStart.text.trim().isEmpty ? null : _freezeStart.text.trim(),
                                        membershipFreezeEndsAt: _freezeEnd.text.trim(),
                                      ));
                                  setState(() {
                                    _freezing = false;
                                    _freezeErr = null;
                                  });
                                },
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [Icon(LucideIcons.snowflake, size: 14), SizedBox(width: 6), Text("Confirm freeze")],
                                ),
                              ),
                              const SizedBox(width: 8),
                              BtnGhost(
                                onPressed: () => setState(() {
                                  _freezing = false;
                                  _freezeErr = null;
                                }),
                                child: const Text("Cancel"),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    BtnGhost(
                      full: true,
                      onPressed: () => setState(() => _freezing = true),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [Icon(LucideIcons.snowflake, size: 14), SizedBox(width: 6), Text("Freeze membership")],
                      ),
                    ),
                ],
                if (isOwner && plan != null && plan.kind != PlanKind.program) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Container(
                      padding: const EdgeInsets.only(top: 12),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                      child: _SessionOverrideRow(info: info, plan: plan, onSave: (v) => update((c) => v == null ? c.copyWith(clearSessionCountOverride: true) : c.copyWith(sessionCountOverride: v))),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _ContactRow(icon: LucideIcons.mail, label: "Email", value: info.email),
          _ContactRow(
            icon: LucideIcons.cake,
            label: "Birthday",
            value: info.birthday,
          ),
          _ContactRow(icon: LucideIcons.phone, label: "Phone", value: info.phone),
          _ContactRow(icon: LucideIcons.mapPin, label: "City", value: info.city),
          const SizedBox(height: 8),
          BtnGhost(
            onPressed: () => setState(() => _editing = true),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [Icon(LucideIcons.edit3, size: 14), SizedBox(width: 6), Text("Edit profile")],
            ),
          ),
        ],
      ),
    );
  }
}

typedef ClientInfoUpdater = ClientInfo Function(ClientInfo);

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.gold),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
              Text(value ?? "—", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionOverrideRow extends StatefulWidget {
  const _SessionOverrideRow({required this.info, required this.plan, required this.onSave});
  final ClientInfo info;
  final MembershipPlan plan;
  final void Function(int?) onSave;

  @override
  State<_SessionOverrideRow> createState() => _SessionOverrideRowState();
}

class _SessionOverrideRowState extends State<_SessionOverrideRow> {
  late final _draft = TextEditingController(text: widget.info.sessionCountOverride?.toString() ?? "");

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("SESSION COUNT OVERRIDE", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
        const SizedBox(height: 6),
        Row(
          children: [
            SizedBox(
              width: 90,
              child: AppField(controller: _draft, placeholder: "${widget.plan.maxSessions ?? 0}", keyboardType: TextInputType.number),
            ),
            const SizedBox(width: 8),
            BtnGhost(
              onPressed: () {
                final trimmed = _draft.text.trim();
                widget.onSave(trimmed.isEmpty ? null : int.tryParse(trimmed)?.clamp(0, 1 << 30));
              },
              child: const Text("Save"),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            widget.info.sessionCountOverride != null
                ? "Currently overridden to ${widget.info.sessionCountOverride} — plan default is ${widget.plan.maxSessions ?? 0}."
                : "Using the plan's default of ${widget.plan.maxSessions ?? 0}. Leave blank to clear an override.",
            style: const TextStyle(fontSize: 11, color: AppColors.mute),
          ),
        ),
      ],
    );
  }
}

class _EditSection extends StatefulWidget {
  const _EditSection({required this.info, required this.onCancel, required this.onSave});
  final ClientInfo info;
  final VoidCallback onCancel;
  final void Function(String name, String email, String phone, String city) onSave;

  @override
  State<_EditSection> createState() => _EditSectionState();
}

class _EditSectionState extends State<_EditSection> {
  late final _name = TextEditingController(text: widget.info.name);
  late final _email = TextEditingController(text: widget.info.email ?? "");
  late final _phone = TextEditingController(text: widget.info.phone ?? "");
  late final _city = TextEditingController(text: widget.info.city ?? "");

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _city.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onCancel, title: "Profile"),
          const SizedBox(height: 10),
          const SectionLabel("Edit Profile"),
          FieldLabeled(label: "Name", child: AppField(controller: _name)),
          const SizedBox(height: 10),
          FieldLabeled(label: "Email", child: AppField(controller: _email, keyboardType: TextInputType.emailAddress)),
          const SizedBox(height: 10),
          FieldLabeled(label: "Phone", child: AppField(controller: _phone, keyboardType: TextInputType.phone)),
          const SizedBox(height: 10),
          FieldLabeled(label: "City", child: AppField(controller: _city)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: BtnGold(
                  onPressed: () => widget.onSave(_name.text.trim(), _email.text.trim(), _phone.text.trim(), _city.text.trim()),
                  child: const Text("Save"),
                ),
              ),
              const SizedBox(width: 8),
              BtnGhost(onPressed: widget.onCancel, child: const Text("Cancel")),
            ],
          ),
        ],
      ),
    );
  }
}
