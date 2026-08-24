import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/models/product.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

const _allowedTypeOptions = ["one-on-one", "semi-private", "large-group"];

/// Mirrors ManageMemberships.jsx + PackageSetupModal.jsx, folded into one
/// inline form (matching this screen's existing style, rather than
/// PackageSetupModal's separate payment-type-picker overlay step). Covers
/// the highest-value subset of the modal's ~15 Advanced Settings fields —
/// rollover, guests + guest fee, cancellation notice, early-termination
/// fee, service balance, squad sharing, public flag, one-per-account
/// limit, expiration, and the fee-item product link. Deliberately trimmed:
/// contract attachment (would need a second bespoke waiver-linking flow —
/// same "don't build a second bespoke editor" reasoning as Customize
/// Platform's signup-waiver field) and two lower-value toggles
/// (allowBookingBeyondBillingInterval, includeGuestsInVisitCount).
class ManageMembershipsScreen extends ConsumerStatefulWidget {
  const ManageMembershipsScreen({super.key});

  @override
  ConsumerState<ManageMembershipsScreen> createState() => _ManageMembershipsScreenState();
}

class _ManageMembershipsScreenState extends ConsumerState<ManageMembershipsScreen> {
  MembershipPlan? _editing;
  bool _creating = false;

  int _membersOn(String planId) {
    final roster = ref.watch(trainerRosterProvider);
    return roster.where((c) => c.membershipPlanId == planId || c.plans.any((pl) => pl.planId == planId && pl.status == "active")).length;
  }

  void _move(String id, int dir) {
    final plans = ref.read(membershipPlansProvider);
    final i = plans.indexWhere((p) => p.id == id);
    final j = i + dir;
    if (i < 0 || j < 0 || j >= plans.length) return;
    final next = [...plans];
    final tmp = next[i];
    next[i] = next[j];
    next[j] = tmp;
    ref.read(membershipPlansProvider.notifier).setAll(next);
    SupabaseService.upsertMembershipPlan(next[i]).catchError((_) {});
    SupabaseService.upsertMembershipPlan(next[j]).catchError((_) {});
  }

  Future<void> _removeOrArchive(MembershipPlan p) async {
    final inUse = _membersOn(p.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('${inUse > 0 ? "Archive" : "Delete"} "${p.name}"?'),
        content: Text(inUse > 0
            ? "$inUse member(s) are on this plan. Archiving hides it from new sign-ups; current members keep it and keep working exactly as before."
            : "No members are on this plan, so it can be permanently removed."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Yes, ${inUse > 0 ? "archive" : "delete"} it")),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (inUse > 0) {
        final archived = _withArchived(p, true);
        await SupabaseService.upsertMembershipPlan(archived);
        ref.read(membershipPlansProvider.notifier).upsert(archived);
      } else {
        await SupabaseService.deleteMembershipPlan(p.id);
        ref.read(membershipPlansProvider.notifier).remove(p.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't ${inUse > 0 ? "archive" : "delete"} — check your connection and try again.")));
      }
      return;
    }
    if (mounted) setState(() => _editing = null);
  }

  Future<void> _restore(MembershipPlan p) async {
    final restored = _withArchived(p, false);
    try {
      await SupabaseService.upsertMembershipPlan(restored);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't restore — check your connection and try again.")));
      }
      return;
    }
    ref.read(membershipPlansProvider.notifier).upsert(restored);
    if (mounted) setState(() => _editing = null);
  }

  MembershipPlan _withArchived(MembershipPlan p, bool archived) => MembershipPlan(
        id: p.id,
        name: p.name,
        kind: p.kind,
        maxSessions: p.maxSessions,
        termMonths: p.termMonths,
        allowedTypes: p.allowedTypes,
        priceCents: p.priceCents,
        archived: archived,
        paymentType: p.paymentType,
        feeItemProductId: p.feeItemProductId,
        category: p.category,
        allowGuests: p.allowGuests,
        guestFeeCents: p.guestFeeCents,
        rolloverEnabled: p.rolloverEnabled,
        rolloverMaxVisits: p.rolloverMaxVisits,
        cancellationNoticeDays: p.cancellationNoticeDays,
        earlyTerminationFeeCents: p.earlyTerminationFeeCents,
        serviceBalanceEnabled: p.serviceBalanceEnabled,
        sharingEnabled: p.sharingEnabled,
        sharingMaxAccounts: p.sharingMaxAccounts,
        public: p.public,
        limitOnePerAccount: p.limitOnePerAccount,
        expirationEnabled: p.expirationEnabled,
        expirationDays: p.expirationDays,
      );

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(membershipPlansProvider);
    final products = ref.watch(productsProvider);

    if (_editing != null || _creating) {
      final editingPlan = _editing;
      return _PlanEditForm(
        initial: editingPlan,
        products: products,
        onCancel: () => setState(() {
          _editing = null;
          _creating = false;
        }),
        onSave: (p) async {
          try {
            await SupabaseService.upsertMembershipPlan(p);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save — check your connection and try again.")));
            }
            return;
          }
          ref.read(membershipPlansProvider.notifier).upsert(p);
          setState(() {
            _editing = null;
            _creating = false;
          });
        },
        onDelete: editingPlan == null ? null : () => _removeOrArchive(editingPlan),
        onRestore: editingPlan == null || !editingPlan.archived ? null : () => _restore(editingPlan),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SectionLabel("Membership Plans (${plans.length})"),
              TextButton.icon(
                onPressed: () => setState(() => _creating = true),
                icon: const Icon(LucideIcons.plus, size: 14, color: AppColors.gold),
                label: const Text("Plan", style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
          const HintBox(text: "Plans with active members can be archived (hidden from new sign-ups) but never deleted — existing members keep working."),
          ...plans.asMap().entries.map((entry) {
            final i = entry.key;
            final p = entry.value;
            final inUse = _membersOn(p.id);
            return Opacity(
              opacity: p.archived ? 0.55 : 1,
              child: AppCard(
                onTap: () => setState(() => _editing = p),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Flexible(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), overflow: TextOverflow.ellipsis)),
                            if (p.archived) const Padding(padding: EdgeInsets.only(left: 6), child: Tag(text: "Archived")),
                          ]),
                          Text(
                            "${_kindLabel(p.kind)} · \$${(p.priceCents / 100).toStringAsFixed(2)}${p.kind == PlanKind.membership ? '/mo' : ''} · ${p.maxSessions ?? 0} sessions · $inUse member${inUse != 1 ? "s" : ""}${p.category != null && p.category!.isNotEmpty ? ' · ${p.category}' : ''}",
                            style: const TextStyle(fontSize: 11, color: AppColors.mute),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(onTap: i == 0 ? null : () => _move(p.id, -1), child: Icon(LucideIcons.chevronUp, size: 16, color: i == 0 ? AppColors.line : AppColors.mute)),
                        InkWell(onTap: i == plans.length - 1 ? null : () => _move(p.id, 1), child: Icon(LucideIcons.chevronDown, size: 16, color: i == plans.length - 1 ? AppColors.line : AppColors.mute)),
                      ],
                    ),
                    const SizedBox(width: 4),
                    const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

String _kindLabel(PlanKind k) => switch (k) { PlanKind.membership => "Membership", PlanKind.package => "Package", PlanKind.program => "Program" };

class _PlanEditForm extends ConsumerStatefulWidget {
  const _PlanEditForm({required this.initial, required this.products, required this.onCancel, required this.onSave, required this.onDelete, required this.onRestore});
  final MembershipPlan? initial;
  final List<Product> products;
  final VoidCallback onCancel;
  final ValueChanged<MembershipPlan> onSave;
  final VoidCallback? onDelete;
  final VoidCallback? onRestore;

  @override
  ConsumerState<_PlanEditForm> createState() => _PlanEditFormState();
}

class _PlanEditFormState extends ConsumerState<_PlanEditForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? "");
  late PlanKind _kind = widget.initial?.kind ?? PlanKind.membership;
  late final _price = TextEditingController(text: widget.initial != null ? (widget.initial!.priceCents / 100).toStringAsFixed(2) : "");
  late final _maxSessions = TextEditingController(text: "${widget.initial?.maxSessions ?? 0}");
  late final _termMonths = TextEditingController(text: "${widget.initial?.termMonths ?? 1}");
  late final Set<String> _allowedTypes = {...(widget.initial?.allowedTypes ?? [])};
  late bool _archived = widget.initial?.archived ?? false;
  String? _category;
  bool _addingCategory = false;
  final _newCategory = TextEditingController();
  bool _advancedOpen = false;

  // Advanced settings
  late bool _allowGuests = widget.initial?.allowGuests ?? false;
  late final _guestFee = TextEditingController(text: ((widget.initial?.guestFeeCents ?? 0) / 100).toStringAsFixed(2));
  late bool _rolloverEnabled = widget.initial?.rolloverEnabled ?? false;
  late final _rolloverMax = TextEditingController(text: "${widget.initial?.rolloverMaxVisits ?? 0}");
  late final _noticeDays = TextEditingController(text: "${widget.initial?.cancellationNoticeDays ?? 0}");
  late final _terminationFee = TextEditingController(text: ((widget.initial?.earlyTerminationFeeCents ?? 0) / 100).toStringAsFixed(2));
  late bool _serviceBalance = widget.initial?.serviceBalanceEnabled ?? false;
  late bool _sharingEnabled = widget.initial?.sharingEnabled ?? false;
  late final _sharingMax = TextEditingController(text: "${widget.initial?.sharingMaxAccounts ?? 1}");
  late bool _public = widget.initial?.public ?? true;
  late bool _limitOnePerAccount = widget.initial?.limitOnePerAccount ?? false;
  late bool _expirationEnabled = widget.initial?.expirationEnabled ?? false;
  late final _expirationDays = TextEditingController(text: "${widget.initial?.expirationDays ?? 30}");
  String? _feeItemProductId;

  @override
  void initState() {
    super.initState();
    _category = widget.initial?.category;
    _feeItemProductId = widget.initial?.feeItemProductId;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _maxSessions.dispose();
    _termMonths.dispose();
    _newCategory.dispose();
    _guestFee.dispose();
    _rolloverMax.dispose();
    _noticeDays.dispose();
    _terminationFee.dispose();
    _sharingMax.dispose();
    _expirationDays.dispose();
    super.dispose();
  }

  Future<void> _addCategory() async {
    final name = _newCategory.text.trim();
    if (name.isEmpty) return;
    try {
      await SupabaseService.insertPackageCategory(name);
      ref.read(packageCategoriesProvider.notifier).add(name);
      setState(() {
        _category = name;
        _addingCategory = false;
        _newCategory.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't add that category — check your connection and try again.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(packageCategoriesProvider);
    final isSub = _kind == PlanKind.membership;
    final isProgram = _kind == PlanKind.program;
    final activeProducts = widget.products.where((p) => !p.archived).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onCancel, title: widget.initial != null ? "Edit Plan" : "New Plan"),
          const SizedBox(height: 12),
          FieldLabeled(label: "Name", child: AppField(controller: _name, onChanged: (_) => setState(() {}))),
          const SizedBox(height: 10),
          const Text("KIND", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: PlanKind.values.map((k) {
              final selected = _kind == k;
              return InkWell(
                onTap: () => setState(() => _kind = k),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card, border: Border.all(color: selected ? AppColors.gold : AppColors.line), borderRadius: BorderRadius.circular(8)),
                  child: Text(_kindLabel(k), style: TextStyle(fontSize: 12, color: selected ? AppColors.gold : AppColors.txt)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: FieldLabeled(label: "Price (\$)", child: AppField(controller: _price, keyboardType: TextInputType.number))),
              const SizedBox(width: 8),
              Expanded(child: FieldLabeled(label: "Max sessions", child: AppField(controller: _maxSessions, keyboardType: TextInputType.number))),
            ],
          ),
          if (isProgram) ...[
            const SizedBox(height: 10),
            FieldLabeled(label: "Term (months)", child: AppField(controller: _termMonths, keyboardType: TextInputType.number)),
          ],
          if (!isProgram) ...[
            const SizedBox(height: 10),
            const Text("ALLOWED SESSION TYPES", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: _allowedTypeOptions.map((t) {
                final selected = _allowedTypes.contains(t);
                return InkWell(
                  onTap: () => setState(() => selected ? _allowedTypes.remove(t) : _allowedTypes.add(t)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card, border: Border.all(color: selected ? AppColors.gold : AppColors.line), borderRadius: BorderRadius.circular(8)),
                    child: Text(sessionTypeLabel(t), style: TextStyle(fontSize: 12, color: selected ? AppColors.gold : AppColors.txt)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            const Text("CATEGORY", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in categories)
                  InkWell(
                    onTap: () => setState(() => _category = c),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: _category == c ? AppColors.gold : AppColors.line), color: _category == c ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg),
                      child: Text(c, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _category == c ? AppColors.gold : AppColors.txt)),
                    ),
                  ),
                OutlinedButton(
                  onPressed: () => setState(() => _addingCategory = true),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.mute, side: const BorderSide(color: AppColors.line), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  child: const Text("+ Add category", style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            if (_addingCategory) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: AppField(controller: _newCategory, placeholder: "e.g. Fees, Apparel")),
                  const SizedBox(width: 8),
                  TextButton(onPressed: _addCategory, child: const Text("Add")),
                ],
              ),
            ],

            // ── Advanced Settings ──
            const SizedBox(height: 14),
            InkWell(
              onTap: () => setState(() => _advancedOpen = !_advancedOpen),
              child: Row(
                children: [
                  const Expanded(child: SectionLabel("Advanced Settings")),
                  Icon(_advancedOpen ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 14, color: AppColors.mute),
                ],
              ),
            ),
            if (_advancedOpen) ...[
              const SizedBox(height: 8),
              _ToggleRow(label: "Allow guests", value: _allowGuests, onChange: (v) => setState(() => _allowGuests = v)),
              if (_allowGuests && !isSub) ...[
                const SizedBox(height: 8),
                FieldLabeled(label: "Guest fee (\$ per visit)", child: AppField(controller: _guestFee, keyboardType: TextInputType.number)),
              ],
              if (isSub) ...[
                const SizedBox(height: 8),
                _ToggleRow(label: "Max unused rollover visits", value: _rolloverEnabled, onChange: (v) => setState(() => _rolloverEnabled = v)),
                if (_rolloverEnabled) ...[
                  const SizedBox(height: 8),
                  FieldLabeled(label: "Max visits that roll over", child: AppField(controller: _rolloverMax, keyboardType: TextInputType.number)),
                ],
                const SizedBox(height: 8),
                FieldLabeled(label: "Cancellation notice required (days)", child: AppField(controller: _noticeDays, keyboardType: TextInputType.number)),
                const SizedBox(height: 8),
                FieldLabeled(label: "Early termination fee (\$)", child: AppField(controller: _terminationFee, keyboardType: TextInputType.number)),
              ] else ...[
                const SizedBox(height: 8),
                FieldLabeled(
                  label: "Fee Item (select a product)",
                  child: AppCard(
                    child: DropdownButton<String?>(
                      value: _feeItemProductId,
                      isExpanded: true,
                      underline: const SizedBox(),
                      dropdownColor: AppColors.card,
                      hint: const Text("— Select a product —", style: TextStyle(color: AppColors.mute, fontSize: 13)),
                      style: const TextStyle(color: AppColors.txt, fontSize: 13),
                      items: [
                        const DropdownMenuItem(value: null, child: Text("— Select a product —")),
                        ...activeProducts.map((p) => DropdownMenuItem(value: p.id, child: Text("${p.name} — \$${(p.priceCents / 100).toStringAsFixed(2)}"))),
                      ],
                      onChanged: (v) => setState(() => _feeItemProductId = v),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _ToggleRow(label: "Enable service balance", value: _serviceBalance, onChange: (v) => setState(() => _serviceBalance = v)),
                const SizedBox(height: 8),
                _ToggleRow(label: "Limit purchasing to one per account", value: _limitOnePerAccount, onChange: (v) => setState(() => _limitOnePerAccount = v)),
                const SizedBox(height: 8),
                _ToggleRow(label: "Manage expiration", value: _expirationEnabled, onChange: (v) => setState(() => _expirationEnabled = v)),
                if (_expirationEnabled) ...[
                  const SizedBox(height: 8),
                  FieldLabeled(label: "Expires in how many days?", child: AppField(controller: _expirationDays, keyboardType: TextInputType.number)),
                ],
              ],
              const SizedBox(height: 8),
              _ToggleRow(label: "Enable sharing with squad", value: _sharingEnabled, onChange: (v) => setState(() => _sharingEnabled = v)),
              if (_sharingEnabled) ...[
                const SizedBox(height: 8),
                FieldLabeled(label: "Max accounts this plan can be shared with", child: AppField(controller: _sharingMax, keyboardType: TextInputType.number)),
              ],
              const SizedBox(height: 8),
              _ToggleRow(label: "Public", value: _public, onChange: (v) => setState(() => _public = v)),
            ],
          ],
          const SizedBox(height: 10),
          InkWell(
            onTap: () => setState(() => _archived = !_archived),
            child: Row(
              children: [
                Icon(_archived ? LucideIcons.checkSquare : LucideIcons.square, size: 18, color: _archived ? AppColors.gold : AppColors.mute),
                const SizedBox(width: 8),
                const Text("Archived (hidden from new signups)", style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          BtnGold(
            full: true,
            onPressed: _name.text.trim().isEmpty
                ? null
                : () => widget.onSave(MembershipPlan(
                      id: widget.initial?.id ?? "plan-${DateTime.now().microsecondsSinceEpoch}",
                      name: _name.text.trim(),
                      kind: _kind,
                      maxSessions: int.tryParse(_maxSessions.text.trim()) ?? 0,
                      termMonths: isProgram ? (int.tryParse(_termMonths.text.trim()) ?? 1) : null,
                      allowedTypes: _allowedTypes.toList(),
                      priceCents: ((double.tryParse(_price.text.trim()) ?? 0) * 100).round(),
                      archived: _archived,
                      paymentType: widget.initial?.paymentType ?? (isProgram ? null : (isSub ? "subscription" : "one-time")),
                      feeItemProductId: isSub ? null : _feeItemProductId,
                      category: isProgram ? null : _category,
                      allowGuests: isProgram ? false : _allowGuests,
                      guestFeeCents: (isProgram || isSub) ? 0 : ((double.tryParse(_guestFee.text.trim()) ?? 0) * 100).round(),
                      rolloverEnabled: isSub && _rolloverEnabled,
                      rolloverMaxVisits: isSub ? (int.tryParse(_rolloverMax.text.trim()) ?? 0) : 0,
                      cancellationNoticeDays: isSub ? (int.tryParse(_noticeDays.text.trim()) ?? 0) : 0,
                      earlyTerminationFeeCents: isSub ? ((double.tryParse(_terminationFee.text.trim()) ?? 0) * 100).round() : 0,
                      serviceBalanceEnabled: (!isProgram && !isSub) && _serviceBalance,
                      sharingEnabled: isProgram ? false : _sharingEnabled,
                      sharingMaxAccounts: int.tryParse(_sharingMax.text.trim()) ?? 1,
                      public: isProgram ? true : _public,
                      limitOnePerAccount: (!isProgram && !isSub) && _limitOnePerAccount,
                      expirationEnabled: (!isProgram && !isSub) && _expirationEnabled,
                      expirationDays: (!isProgram && !isSub && _expirationEnabled) ? (int.tryParse(_expirationDays.text.trim()) ?? 30) : null,
                    )),
            child: const Text("Save plan"),
          ),
          if (widget.onRestore != null) ...[
            const SizedBox(height: 10),
            BtnGhost(onPressed: widget.onRestore, full: true, child: const Text("Restore plan (visible to new sign-ups again)")),
          ] else if (widget.onDelete != null) ...[
            const SizedBox(height: 10),
            TextButton(onPressed: widget.onDelete, style: TextButton.styleFrom(foregroundColor: const Color(0xFFC97F7F)), child: const Text("Delete or archive plan")),
          ],
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.label, required this.value, required this.onChange});
  final String label;
  final bool value;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => onChange(!value),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          Icon(value ? LucideIcons.toggleRight : LucideIcons.toggleLeft, size: 30, color: value ? AppColors.gold : AppColors.mute),
        ],
      ),
    );
  }
}
