import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/coupon.dart";
import "../../../data/providers/trainer_providers.dart";

/// Owner-managed coupon-code catalog, reached from Customize Platform's
/// "Coupons" tab. Applied on every purchase surface: Membership Hub
/// self-checkout, and the coach/owner Purchase for Client flow (see
/// profile_tab.dart's "Purchase for client" entry point).
class ManageCouponsScreen extends ConsumerStatefulWidget {
  const ManageCouponsScreen({super.key});

  @override
  ConsumerState<ManageCouponsScreen> createState() => _ManageCouponsScreenState();
}

class _ManageCouponsScreenState extends ConsumerState<ManageCouponsScreen> {
  Coupon? _editing;
  bool _creating = false;

  Future<void> _delete(Coupon c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Delete "${c.code}"?'),
        content: const Text("This removes the code from every purchase surface immediately. Past purchases that already used it are unaffected."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Yes, delete it")),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await SupabaseService.deleteCoupon(c.id);
      ref.read(couponsProvider.notifier).remove(c.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't delete — check your connection and try again.")),
        );
      }
      return;
    }
    if (mounted) setState(() => _editing = null);
  }

  @override
  Widget build(BuildContext context) {
    final coupons = ref.watch(couponsProvider);

    if (_editing != null || _creating) {
      final editing = _editing;
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() {
          _editing = null;
          _creating = false;
        }),
        child: _CouponEditForm(
          initial: editing,
          existingCodes: coupons.where((c) => c.id != editing?.id).map((c) => c.code.toUpperCase()).toSet(),
          onCancel: () => setState(() {
            _editing = null;
            _creating = false;
          }),
          onSave: (c) async {
            try {
              await SupabaseService.upsertCoupon(c);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Couldn't save — check your connection and try again.")),
                );
              }
              return;
            }
            ref.read(couponsProvider.notifier).upsert(c);
            setState(() {
              _editing = null;
              _creating = false;
            });
          },
          onDelete: editing == null ? null : () => _delete(editing),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Coupons"),
          const SizedBox(height: 8),
          const HintBox(
            text: "Reusable discount codes a client can enter at checkout, or a coach/owner can apply when purchasing a plan on a client's behalf.",
          ),
          const SizedBox(height: 10),
          if (coupons.isEmpty) const HintBox(text: "No coupon codes yet — add one below."),
          ...coupons.map((c) {
            return AppCard(
              onTap: () => setState(() => _editing = c),
              child: Opacity(
                opacity: c.archived ? 0.55 : 1,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  c.code,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.5),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (c.archived) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(5)),
                                  child: const Text("Inactive", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.mute)),
                                ),
                              ],
                            ],
                          ),
                          Text(c.valueLabel, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                        ],
                      ),
                    ),
                    const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
          BtnGold(
            full: true,
            onPressed: () => setState(() => _creating = true),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.plus, size: 15),
                SizedBox(width: 6),
                Text("Add New Coupon"),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CouponEditForm extends StatefulWidget {
  const _CouponEditForm({
    required this.initial,
    required this.existingCodes,
    required this.onCancel,
    required this.onSave,
    required this.onDelete,
  });
  final Coupon? initial;
  final Set<String> existingCodes;
  final VoidCallback onCancel;
  final ValueChanged<Coupon> onSave;
  final VoidCallback? onDelete;

  @override
  State<_CouponEditForm> createState() => _CouponEditFormState();
}

class _CouponEditFormState extends State<_CouponEditForm> {
  late final _code = TextEditingController(text: widget.initial?.code ?? "");
  late String _type = widget.initial?.type ?? "percent";
  late final _percent = TextEditingController(text: "${widget.initial?.percentOff ?? 10}");
  late final _flat = TextEditingController(text: widget.initial != null ? (widget.initial!.flatOffCents / 100).toStringAsFixed(2) : "");
  late bool _archived = widget.initial?.archived ?? false;

  @override
  void dispose() {
    _code.dispose();
    _percent.dispose();
    _flat.dispose();
    super.dispose();
  }

  String? get _codeError {
    final code = _code.text.trim();
    if (code.isEmpty) return null;
    if (widget.existingCodes.contains(code.toUpperCase())) return "That code already exists.";
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final codeError = _codeError;
    final canSave = _code.text.trim().isNotEmpty && codeError == null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onCancel, title: widget.initial != null ? "Edit Coupon" : "New Coupon"),
          const SizedBox(height: 12),
          FieldLabeled(
            label: "Code",
            child: AppField(
              controller: _code,
              placeholder: "e.g. SUMMER10",
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (codeError != null) ...[
            const SizedBox(height: 6),
            Text(codeError, style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          const Text("Discount type", style: TextStyle(color: AppColors.mute, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final t in const [("percent", "Percent off"), ("flat", "Flat amount off")])
                InkWell(
                  onTap: () => setState(() => _type = t.$1),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _type == t.$1 ? AppColors.gold : AppColors.line),
                      color: _type == t.$1 ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg,
                    ),
                    child: Text(t.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _type == t.$1 ? AppColors.gold : AppColors.txt)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_type == "percent")
            FieldLabeled(
              label: "Percent off",
              child: AppField(controller: _percent, keyboardType: TextInputType.number),
            )
          else
            FieldLabeled(
              label: "Flat amount off (\$)",
              child: AppField(controller: _flat, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            ),
          const SizedBox(height: 10),
          AppCard(
            child: InkWell(
              onTap: () => setState(() => _archived = !_archived),
              child: Row(
                children: [
                  const Expanded(child: Text("Active", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                  Icon(!_archived ? LucideIcons.toggleRight : LucideIcons.toggleLeft, size: 30, color: !_archived ? AppColors.gold : AppColors.mute),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: BtnGold(
                  onPressed: !canSave
                      ? null
                      : () => widget.onSave(
                          Coupon(
                            id: widget.initial?.id ?? "coupon-${DateTime.now().microsecondsSinceEpoch}",
                            code: _code.text.trim().toUpperCase(),
                            type: _type,
                            percentOff: (int.tryParse(_percent.text.trim()) ?? 0).clamp(0, 100),
                            flatOffCents: (((double.tryParse(_flat.text.trim()) ?? 0) * 100).round()).clamp(0, 1 << 31),
                            archived: _archived,
                          ),
                        ),
                  child: const Text("Save"),
                ),
              ),
              const SizedBox(width: 8),
              BtnGhost(onPressed: widget.onCancel, child: const Text("Cancel")),
            ],
          ),
          if (widget.onDelete != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: widget.onDelete,
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFC97F7F)),
              child: const Text("Delete coupon"),
            ),
          ],
        ],
      ),
    );
  }
}
