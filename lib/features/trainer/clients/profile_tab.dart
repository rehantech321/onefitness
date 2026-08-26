import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/client_status_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/flag_utils.dart";
import "../../../core/utils/membership_utils.dart";
import "../../../core/utils/program_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/charge.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/intake_schema.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors Profile.jsx (viewed from the coach side, via TrainerView). Trimmed
/// vs. the web: Edit Profile is a simplified name/email/phone/city form here
/// rather than the full IntakeForm. Everything else — price on the
/// membership line, real freeze/unfreeze (Stripe pause_collection via
/// freeze-membership/unfreeze-membership), the remaining-sessions editor
/// (available to any coach, not just the owner), and Add Charge — persists
/// to the real backend the same as the web.
class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({
    super.key,
    required this.clientId,
    required this.onGoToIntake,
  });

  final String clientId;
  final VoidCallback onGoToIntake;

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  bool _editing = false;
  bool _charging = false;
  bool _freezing = false;
  bool _freezeBusy = false;
  late final _freezeStart = TextEditingController(text: isoToday());
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
    final records = ref.watch(trainerClientRecordsProvider);
    final record = records[widget.clientId];
    final status = record != null
        ? computeClientStatus(record)
        : ClientStatus.newClient;
    final meta = kStatusMeta[status]!;
    final plan = ref
        .watch(membershipPlansProvider.notifier)
        .byId(info.membershipPlanId);
    final bookings = ref
        .watch(allBookingsProvider)
        .where((b) => b.clientId == widget.clientId)
        .toList();
    final notes = record != null ? getClientProgramNotes(record) : const [];
    final earnedBadges = ref.watch(earnedBadgesProvider);
    final hasActiveBadges = earnedBadges.any(
      (b) => b.clientId == widget.clientId && b.isActive,
    );

    void update(ClientInfoUpdater updater) => ref
        .read(trainerRosterProvider.notifier)
        .update(widget.clientId, updater);

    if (_editing) {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _editing = false),
        child: _EditSection(
          info: info,
          onCancel: () => setState(() => _editing = false),
          onSave: (name, email, phone, city) async {
            await SupabaseService.updateClientRow(
              info.id,
              name: name,
              email: email,
              phone: phone,
              city: city,
            );
            update(
              (c) => c.copyWith(
                name: name,
                email: email,
                phone: phone,
                city: city,
              ),
            );
            if (mounted) setState(() => _editing = false);
          },
        ),
      );
    }

    if (_charging) {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _charging = false),
        child: _AddChargeForm(
          info: info,
          onCancel: () => setState(() => _charging = false),
          onSubmit: (category, description, amount) async {
            final saved = await SupabaseService.insertCharge(
              Charge(
                id: "",
                clientId: info.id,
                clientName: info.name,
                type: "manual",
                date: isoToday(),
                at: stamp(),
                category: category,
                description: description,
                amount: amount,
              ),
            );
            ref.read(chargesProvider.notifier).add(saved);
            if (mounted) setState(() => _charging = false);
          },
        ),
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
                  Text(
                    info.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                    ),
                  ),
                  const Text(
                    "ONE Fitness client",
                    style: TextStyle(fontSize: 12, color: AppColors.mute),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          const SectionLabel("Active Merit Badges"),
          hasActiveBadges
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: MeritBadgeRow(
                    clientId: widget.clientId,
                    earnedBadges: earnedBadges,
                  ),
                )
              : const Padding(
                  padding: EdgeInsets.only(bottom: 14),
                  child: Text(
                    "No Merit Badges earned yet.",
                    style: TextStyle(fontSize: 12, color: AppColors.mute),
                  ),
                ),
          _IntakeStatusSummary(
            intake: record?.intake ?? const {},
            onTap: widget.onGoToIntake,
          ),
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
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE05555),
                      ),
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
                    const Text(
                      "PROGRESS STATUS",
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.mute,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      meta.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      meta.desc,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.mute,
                      ),
                    ),
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
                    const Icon(
                      LucideIcons.creditCard,
                      size: 17,
                      color: AppColors.gold,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "MEMBERSHIP",
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.mute,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            plan != null
                                ? _membershipLabel(plan)
                                : "No membership selected",
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (info.membershipPaused)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                "Frozen ${info.membershipPausedAt ?? ''}${info.membershipFreezeEndsAt != null ? ' – ${info.membershipFreezeEndsAt}' : ''}",
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFD68A4F),
                                  fontWeight: FontWeight.w700,
                                ),
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
                      child: Text(
                        _freezeErr!,
                        style: const TextStyle(
                          color: Color(0xFFC97F7F),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (info.membershipPaused)
                    BtnGold(
                      full: true,
                      onPressed: _freezeBusy
                          ? null
                          : () => _unfreeze(info, update),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.refreshCw, size: 14),
                          const SizedBox(width: 6),
                          Text(_freezeBusy ? "Working…" : "Unfreeze now"),
                        ],
                      ),
                    )
                  else if (_freezing)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        border: Border.all(color: AppColors.line),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Both dates are required — this shifts ${info.name}'s billing date too, so they don't lose any paid-for time.",
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.mute,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: FieldLabeled(
                                  label: "Start (YYYY-MM-DD)",
                                  child: AppField(controller: _freezeStart),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FieldLabeled(
                                  label: "End (YYYY-MM-DD)",
                                  child: AppField(controller: _freezeEnd),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              BtnGold(
                                onPressed: _freezeBusy
                                    ? null
                                    : () => _confirmFreeze(info, update),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(LucideIcons.snowflake, size: 14),
                                    const SizedBox(width: 6),
                                    Text(
                                      _freezeBusy
                                          ? "Freezing…"
                                          : "Confirm freeze",
                                    ),
                                  ],
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
                        children: [
                          Icon(LucideIcons.snowflake, size: 14),
                          SizedBox(width: 6),
                          Text("Freeze membership"),
                        ],
                      ),
                    ),
                ],
                if (plan != null && plan.kind != PlanKind.program) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Container(
                      padding: const EdgeInsets.only(top: 12),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: AppColors.line)),
                      ),
                      child: _SessionOverrideRow(
                        info: info,
                        plan: plan,
                        bookings: bookings,
                        onSave: (total, month, clear) async {
                          await SupabaseService.updateClientRow(
                            info.id,
                            sessionCountOverride: total,
                            sessionCountOverrideMonth: month,
                            clearSessionCountOverride: clear,
                          );
                          update(
                            (c) => clear
                                ? c.copyWith(clearSessionCountOverride: true)
                                : c.copyWith(
                                    sessionCountOverride: total,
                                    sessionCountOverrideMonth: month,
                                  ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _ContactRow(
            icon: LucideIcons.mail,
            label: "Email",
            value: info.email,
          ),
          _ContactRow(
            icon: LucideIcons.cake,
            label: "Birthday",
            value: info.birthday != null
                ? "${_niceDate(info.birthday!)} (age ${_ageFrom(info.birthday!)})"
                : null,
          ),
          _ContactRow(
            icon: LucideIcons.phone,
            label: "Phone",
            value: info.phone,
          ),
          _ContactRow(
            icon: LucideIcons.mapPin,
            label: "City",
            value: info.city,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: BtnGhost(
                  onPressed: () => setState(() => _editing = true),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.edit3, size: 14),
                      SizedBox(width: 6),
                      Text("Edit profile"),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BtnGhost(
                  onPressed: () => setState(() => _charging = true),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.creditCard, size: 14),
                      SizedBox(width: 6),
                      Text("Add charge"),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: AppColors.line),
          const SizedBox(height: 14),
          Center(
            child: TextButton(
              onPressed: () => _deleteClient(info),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFC97F7F),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.trash2, size: 14),
                  SizedBox(width: 6),
                  Text("Delete client"),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteClient(ClientInfo info) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text("Delete client?"),
        content: Text(
          "Delete ${info.name}? This permanently removes their profile, programs, logs, and history. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await SupabaseService.deleteClientRow(info.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't delete that client — check your connection and try again.",
            ),
          ),
        );
      }
      return;
    }
    ref.read(trainerRosterProvider.notifier).remove(info.id);
    ref.read(selectedClientIdProvider.notifier).select(null);
  }

  String _membershipLabel(MembershipPlan plan) {
    if (plan.priceCents <= 0) return "${plan.name} — Free";
    final price = "\$${(plan.priceCents / 100).toStringAsFixed(2)}";
    final suffix = plan.kind == PlanKind.membership ? "/mo" : "";
    return "${plan.name} — $price$suffix";
  }

  Future<void> _unfreeze(
    ClientInfo info,
    void Function(ClientInfoUpdater) update,
  ) async {
    setState(() {
      _freezeBusy = true;
      _freezeErr = null;
    });
    try {
      await SupabaseService.unfreezeMembership(info.id);
      update(
        (c) => c.copyWith(
          membershipPaused: false,
          clearMembershipPausedAt: true,
          clearMembershipFreezeEndsAt: true,
        ),
      );
    } catch (e) {
      if (mounted)
        setState(
          () => _freezeErr = e.toString().replaceFirst("Exception: ", ""),
        );
    } finally {
      if (mounted) setState(() => _freezeBusy = false);
    }
  }

  Future<void> _confirmFreeze(
    ClientInfo info,
    void Function(ClientInfoUpdater) update,
  ) async {
    if (_freezeEnd.text.trim().isEmpty) {
      setState(() => _freezeErr = "An end date is required.");
      return;
    }
    setState(() {
      _freezeBusy = true;
      _freezeErr = null;
    });
    final start = _freezeStart.text.trim().isEmpty
        ? isoToday()
        : _freezeStart.text.trim();
    final end = _freezeEnd.text.trim();
    try {
      await SupabaseService.freezeMembership(info.id, start, end);
      update(
        (c) => c.copyWith(
          membershipPaused: true,
          membershipPausedAt: start,
          membershipFreezeEndsAt: end,
        ),
      );
      if (mounted) setState(() => _freezing = false);
    } catch (e) {
      if (mounted)
        setState(
          () => _freezeErr = e.toString().replaceFirst("Exception: ", ""),
        );
    } finally {
      if (mounted) setState(() => _freezeBusy = false);
    }
  }
}

typedef ClientInfoUpdater = ClientInfo Function(ClientInfo);

const _kIntakeStatusItems = [
  ("personalTraining", "Personalized Training Intake"),
  ("nutritional", "Nutrition Program Intake"),
  ("physical", "Free Physical Assessment Session"),
];

/// Mirrors OnboardingAlerts.jsx `IntakeStatusSummary` — always all 3 forms,
/// in this fixed order, whether complete or not (unlike the client
/// dashboard's onboarding banner, which drops each step off the list once
/// done). Tapping any row opens the full Intake list (IntakeTab).
class _IntakeStatusSummary extends StatelessWidget {
  const _IntakeStatusSummary({required this.intake, required this.onTap});

  final Map<String, IntakeRecord> intake;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: _kIntakeStatusItems.map((item) {
          final (key, label) = item;
          final rec = intake[key];
          final done = rec?.completed ?? false;
          return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: done
                      ? AppColors.gold.withValues(alpha: 0.06)
                      : AppColors.card,
                  border: Border.all(
                    color: done ? AppColors.goldDim : AppColors.line,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    done
                        ? const Icon(
                            LucideIcons.check,
                            size: 16,
                            color: AppColors.gold,
                          )
                        : Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFE05555),
                            ),
                          ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              done
                                  ? "Completed by ${rec?.by ?? "Client"}${rec?.at != null ? " · ${rec!.at}" : ""}"
                                  : "Not completed yet",
                              style: TextStyle(
                                fontSize: 11,
                                color: done ? AppColors.gold : AppColors.mute,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      LucideIcons.chevronRight,
                      size: 15,
                      color: AppColors.mute,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
  });
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
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.mute,
                  letterSpacing: 1,
                ),
              ),
              Text(
                value ?? "—",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mirrors Profile.jsx's "Remaining sessions" editor — the coach types how
/// many sessions the client should have REMAINING right now, not a total;
/// internally that's still stored as a total (sessionCountOverride = used +
/// desiredRemaining), which is all effectiveMaxSessions actually
/// understands. A membership plan's override also stamps the current
/// month (sessionCountOverrideMonth) so it's a one-off top-up for this
/// period only; a package's override has no month and stays permanent.
class _SessionOverrideRow extends StatefulWidget {
  const _SessionOverrideRow({
    required this.info,
    required this.plan,
    required this.bookings,
    required this.onSave,
  });
  final ClientInfo info;
  final MembershipPlan plan;
  final List<Booking> bookings;

  /// (total, month, clear) — clear:true means "remove the override entirely".
  final Future<void> Function(int? total, String? month, bool clear) onSave;

  @override
  State<_SessionOverrideRow> createState() => _SessionOverrideRowState();
}

class _SessionOverrideRowState extends State<_SessionOverrideRow> {
  late final TextEditingController _draft;
  bool _busy = false;

  int get _used =>
      sessionsUsedThisPeriod(widget.info, widget.plan, widget.bookings);
  int get _defaultRemaining =>
      ((widget.plan.maxSessions ?? 0) - _used).clamp(0, 1 << 30);
  int? get _currentRemaining => widget.info.sessionCountOverride != null
      ? (effectiveMaxSessions(widget.info, widget.plan) - _used).clamp(
          0,
          1 << 30,
        )
      : null;

  @override
  void initState() {
    super.initState();
    _draft = TextEditingController(
      text: _currentRemaining != null ? "$_currentRemaining" : "",
    );
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final trimmed = _draft.text.trim();
    setState(() => _busy = true);
    try {
      if (trimmed.isEmpty) {
        await widget.onSave(null, null, true);
      } else {
        final desiredRemaining = int.tryParse(trimmed)?.clamp(0, 1 << 30) ?? 0;
        final month = widget.plan.kind == PlanKind.membership
            ? isoToday().substring(0, 7)
            : null;
        await widget.onSave(_used + desiredRemaining, month, false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentRemaining = _currentRemaining;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "REMAINING SESSIONS",
          style: TextStyle(
            fontSize: 10,
            color: AppColors.mute,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            SizedBox(
              width: 90,
              child: AppField(
                controller: _draft,
                placeholder: "$_defaultRemaining",
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            BtnGhost(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? "Saving…" : "Save"),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            (currentRemaining != null
                    ? "Currently set to $currentRemaining remaining — the plan default right now would be $_defaultRemaining."
                    : "Using the plan's default of $_defaultRemaining remaining. Leave blank to clear an override.") +
                (widget.plan.kind == PlanKind.membership
                    ? " This only applies to the current month — it reverts to the plan default next month."
                    : ""),
            style: const TextStyle(fontSize: 11, color: AppColors.mute),
          ),
        ),
      ],
    );
  }
}

const _kChargeCategories = [
  ("membership", "Membership"),
  ("package", "Session Package"),
  ("assessment", "Assessment"),
  ("recovery", "Recovery"),
  ("merchandise", "Merchandise"),
  ("supplements", "Supplements"),
  ("fee", "Fee"),
  ("other", "Other"),
];

/// Mirrors AddChargeForm.jsx — logs a one-off manual charge against this
/// client (e.g. a no-show fee, merchandise sale) for the owner/coach to
/// collect; purely a ledger entry, no real Stripe payment is taken here.
class _AddChargeForm extends StatefulWidget {
  const _AddChargeForm({
    required this.info,
    required this.onCancel,
    required this.onSubmit,
  });
  final ClientInfo info;
  final VoidCallback onCancel;
  final Future<void> Function(
    String category,
    String description,
    double amount,
  )
  onSubmit;

  @override
  State<_AddChargeForm> createState() => _AddChargeFormState();
}

class _AddChargeFormState extends State<_AddChargeForm> {
  String _category = "fee";
  final _description = TextEditingController();
  final _amount = TextEditingController();
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_description.text.trim().isEmpty) {
      setState(() => _err = "Add a description.");
      return;
    }
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _err = "Enter a valid amount.");
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await widget.onSubmit(_category, _description.text.trim(), amount);
    } catch (e) {
      if (mounted)
        setState(() => _err = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          SectionLabel("Add Charge — ${widget.info.name}"),
          const SizedBox(height: 14),
          const Text(
            "CATEGORY",
            style: TextStyle(
              fontSize: 10,
              color: AppColors.mute,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _kChargeCategories.map((c) {
              final (key, label) = c;
              final selected = _category == key;
              return InkWell(
                onTap: () => setState(() => _category = key),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? AppColors.gold : AppColors.line,
                    ),
                    color: selected
                        ? AppColors.gold.withValues(alpha: 0.15)
                        : AppColors.card,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.gold : AppColors.mute,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          FieldLabeled(
            label: "Description *",
            child: AppField(
              controller: _description,
              placeholder: "e.g. Monthly membership, No-show fee…",
            ),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Amount (\$) *",
            child: AppField(
              controller: _amount,
              placeholder: "0.00",
              keyboardType: TextInputType.number,
            ),
          ),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _err!,
                style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          BtnGold(
            full: true,
            onPressed: _busy ? null : _submit,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.creditCard, size: 14),
                const SizedBox(width: 6),
                Text(_busy ? "Adding…" : "Add charge"),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mirrors lib/format.js `niceDate`.
String _niceDate(String iso) {
  final d = DateTime.parse(iso);
  const months = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ];
  const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  return "${weekdays[d.weekday % 7]}, ${months[d.month - 1]} ${d.day}";
}

/// Mirrors lib/helpers.js `ageFrom`.
int _ageFrom(String iso) {
  final d = DateTime.parse(iso);
  final t = DateTime.now();
  var age = t.year - d.year;
  if (t.month < d.month || (t.month == d.month && t.day < d.day)) age--;
  return age;
}

class _EditSection extends StatefulWidget {
  const _EditSection({
    required this.info,
    required this.onCancel,
    required this.onSave,
  });
  final ClientInfo info;
  final VoidCallback onCancel;
  final Future<void> Function(
    String name,
    String email,
    String phone,
    String city,
  )
  onSave;

  @override
  State<_EditSection> createState() => _EditSectionState();
}

class _EditSectionState extends State<_EditSection> {
  late final _name = TextEditingController(text: widget.info.name);
  late final _email = TextEditingController(text: widget.info.email ?? "");
  late final _phone = TextEditingController(text: widget.info.phone ?? "");
  late final _city = TextEditingController(text: widget.info.city ?? "");
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await widget.onSave(
        _name.text.trim(),
        _email.text.trim(),
        _phone.text.trim(),
        _city.text.trim(),
      );
    } catch (e) {
      if (mounted)
        setState(() => _err = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          FieldLabeled(
            label: "Name",
            child: AppField(controller: _name),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Email",
            child: AppField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
            ),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Phone",
            child: AppField(
              controller: _phone,
              keyboardType: TextInputType.phone,
            ),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "City",
            child: AppField(controller: _city),
          ),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _err!,
                style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12),
              ),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: BtnGold(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? "Saving…" : "Save"),
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
