import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/providers/client_providers.dart";

const _allowedTypeOptions = ["one-on-one", "semi-private", "large-group"];

/// Mirrors ManageMemberships.jsx, trimmed to the core plan fields (no
/// PackageSetupModal advanced settings — sharing, guest fees, expiration,
/// Stripe ids — since those don't affect any read screen in this build).
class ManageMembershipsScreen extends ConsumerStatefulWidget {
  const ManageMembershipsScreen({super.key});

  @override
  ConsumerState<ManageMembershipsScreen> createState() => _ManageMembershipsScreenState();
}

class _ManageMembershipsScreenState extends ConsumerState<ManageMembershipsScreen> {
  MembershipPlan? _editing;
  bool _creating = false;

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(membershipPlansProvider);

    if (_editing != null || _creating) {
      return _PlanEditForm(
        initial: _editing,
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
          ...plans.map((p) => Opacity(
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
                              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              if (p.archived) const Padding(padding: EdgeInsets.only(left: 6), child: Tag(text: "Archived")),
                            ]),
                            Text("${_kindLabel(p.kind)} · \$${(p.priceCents / 100).toStringAsFixed(2)}${p.kind == PlanKind.membership ? '/mo' : ''} · ${p.maxSessions ?? 0} sessions", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                          ],
                        ),
                      ),
                      const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

String _kindLabel(PlanKind k) => switch (k) { PlanKind.membership => "Membership", PlanKind.package => "Package", PlanKind.program => "Program" };

class _PlanEditForm extends StatefulWidget {
  const _PlanEditForm({required this.initial, required this.onCancel, required this.onSave});
  final MembershipPlan? initial;
  final VoidCallback onCancel;
  final ValueChanged<MembershipPlan> onSave;

  @override
  State<_PlanEditForm> createState() => _PlanEditFormState();
}

class _PlanEditFormState extends State<_PlanEditForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? "");
  late PlanKind _kind = widget.initial?.kind ?? PlanKind.membership;
  late final _price = TextEditingController(text: widget.initial != null ? (widget.initial!.priceCents / 100).toStringAsFixed(2) : "");
  late final _maxSessions = TextEditingController(text: "${widget.initial?.maxSessions ?? 0}");
  late final _termMonths = TextEditingController(text: "${widget.initial?.termMonths ?? 1}");
  late final Set<String> _allowedTypes = {...(widget.initial?.allowedTypes ?? [])};
  late bool _archived = widget.initial?.archived ?? false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _maxSessions.dispose();
    _termMonths.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onCancel, title: widget.initial != null ? "Edit Plan" : "New Plan"),
          const SizedBox(height: 12),
          FieldLabeled(label: "Name", child: AppField(controller: _name)),
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
          if (_kind == PlanKind.program) ...[
            const SizedBox(height: 10),
            FieldLabeled(label: "Term (months)", child: AppField(controller: _termMonths, keyboardType: TextInputType.number)),
          ],
          if (_kind != PlanKind.program) ...[
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
                      termMonths: _kind == PlanKind.program ? (int.tryParse(_termMonths.text.trim()) ?? 1) : null,
                      allowedTypes: _allowedTypes.toList(),
                      priceCents: ((double.tryParse(_price.text.trim()) ?? 0) * 100).round(),
                      archived: _archived,
                    )),
            child: const Text("Save plan"),
          ),
        ],
      ),
    );
  }
}
