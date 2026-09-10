import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/payments/payment_method_picker.dart";
import "../../../core/payments/payment_sheet_service.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";

/// Coach/owner "individual purchase for a client" flow. The coach picks a
/// plan (and optional coupon), then takes payment in person on this device
/// through Stripe's native Payment Sheet — the client taps their own card in,
/// and nothing leaves the app. Card details never reach us: the sheet talks
/// to Stripe directly, which is what keeps this out of PCI scope.
///
/// Tender options follow the product type: memberships take card/debit/ACH,
/// packages additionally take Apple Pay.
class PurchaseForClientSection extends ConsumerStatefulWidget {
  const PurchaseForClientSection({super.key, required this.info, required this.onBack, required this.onPlanAssigned});

  final ClientInfo info;
  final VoidCallback onBack;
  final ValueChanged<String> onPlanAssigned;

  @override
  ConsumerState<PurchaseForClientSection> createState() => _PurchaseForClientSectionState();
}

class _PurchaseForClientSectionState extends ConsumerState<PurchaseForClientSection> {
  String? _planId;
  String? _couponId;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    // Programs included: a coach selling a client a personalized or nutrition
    // program is exactly the case this screen exists for, and unlike a
    // membership swap it adds to what they already hold rather than replacing
    // it (see enroll-free-plan / stripe-webhook, which keep the two apart).
    final plans = ref.watch(membershipPlansProvider).where((p) => !p.archived).toList()
      ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
    final coupons = ref.watch(couponsProvider).where((c) => !c.archived).toList();
    final plan = plans.where((p) => p.id == _planId).firstOrNull;
    final coupon = coupons.where((c) => c.id == _couponId).firstOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onBack, title: "Profile"),
          const SizedBox(height: 10),
          SectionLabel("Purchase for ${widget.info.name}"),
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 14),
            child: Text(
              "Pick a plan and, if you'd like, a coupon code. For a paid plan you'll take payment right here — hand the client your phone to enter their card. A free plan is assigned right away, with nothing to pay.",
              style: TextStyle(fontSize: 12, color: AppColors.mute),
            ),
          ),
          const Text("PLAN", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 8),
          if (plans.isEmpty) const HintBox(text: "No plans set up yet — create one under Access/Memberships first."),
          ...plans.map((p) {
            final selected = p.id == _planId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                borderColor: selected ? AppColors.gold : null,
                onTap: () => setState(() {
                  _planId = p.id;
                              _error = null;
                }),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                    Text(
                      p.priceCents > 0 ? "\$${(p.priceCents / 100).toStringAsFixed(2)}${p.kind == PlanKind.membership ? '/mo' : ''}" : "Free",
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.gold),
                    ),
                    const SizedBox(width: 8),
                    Icon(selected ? LucideIcons.checkCircle2 : LucideIcons.circle, size: 18, color: selected ? AppColors.gold : AppColors.line),
                  ],
                ),
              ),
            );
          }),
          if (plan != null && plan.priceCents > 0) ...[
            const SizedBox(height: 10),
            const Text("COUPON (OPTIONAL)", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
            const SizedBox(height: 8),
            AppCard(
              child: DropdownButton<String?>(
                value: _couponId,
                isExpanded: true,
                underline: const SizedBox(),
                dropdownColor: AppColors.card,
                hint: const Text("No coupon", style: TextStyle(color: AppColors.mute, fontSize: 13)),
                style: const TextStyle(color: AppColors.txt, fontSize: 13),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text("No coupon")),
                  ...coupons.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text("${c.code} — ${c.valueLabel}"))),
                ],
                onChanged: (v) => setState(() {
                  _couponId = v;
                            }),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12)),
            ),
          BtnGold(
            full: true,
            onPressed: plan == null || _busy ? null : () => _submit(plan, coupon?.code),
            child: Text(
              _busy
                  ? "Working…"
                  : (plan != null && plan.priceCents > 0 ? "Take payment" : "Assign plan"),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(MembershipPlan plan, String? couponCode) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (plan.priceCents <= 0) {
        // Server-side: `plans` is a grant (it unlocks intake forms), and this
        // also keeps a program from overwriting the client's membership.
        await SupabaseService.enrollFreePlan(plan.id, clientId: widget.info.id);
        if (!isProgramKind(plan.kind)) widget.onPlanAssigned(plan.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${plan.name} assigned to ${widget.info.name}.")));
          widget.onBack();
        }
        return;
      }
      // Taken in person on this device rather than by sending the client a
      // link: the client taps their own card into Stripe's sheet while
      // they're standing there, and nothing leaves the app.
      if (!mounted) return;
      final tender = await showPaymentMethodPicker(context, plan);
      if (tender == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      final result = await PaymentSheetService.purchase(
        planId: plan.id,
        couponCode: couponCode,
        targetClientId: widget.info.id,
        paymentMethod: tender == PayTender.ach ? "ach" : "card",
        businessName: ref.read(platformSettingsProvider).businessName,
      );
      if (result.cancelled) return;
      if (!result.ok && !result.noPaymentNeeded) {
        if (mounted) setState(() => _error = result.error);
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Payment received — ${plan.name} is being activated for ${widget.info.name}.")),
        );
        widget.onBack();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
