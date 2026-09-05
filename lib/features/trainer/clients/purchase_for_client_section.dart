import "package:flutter/foundation.dart" show kIsWeb;
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "package:url_launcher/url_launcher.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

/// Coach/owner "individual purchase for a client" flow. There's no saved
/// card to charge off-session, and this app doesn't collect card details
/// directly (PCI scope), so the coach picks a plan (and optional coupon)
/// and the app generates a real Stripe Checkout link — same session type
/// membership_hub_screen.dart's self-checkout creates, just attributed to
/// the chosen client via create-checkout-session's targetClientId — for
/// the coach to hand to the client, who completes payment themselves.
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
  String? _generatedUrl;

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(membershipPlansProvider).where((p) => !p.archived && p.kind != PlanKind.program).toList();
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
              "Pick a plan and, if you'd like, a coupon code. For a paid plan, this generates a secure Stripe checkout link — send it to the client (or hand them your phone) to complete payment. A free plan is assigned right away, no checkout needed.",
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
                  _generatedUrl = null;
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
                  _generatedUrl = null;
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
          if (_generatedUrl == null)
            BtnGold(
              full: true,
              onPressed: plan == null || _busy ? null : () => _submit(plan, coupon?.code),
              child: Text(_busy ? "Working…" : (plan != null && plan.priceCents > 0 ? "Generate checkout link" : "Assign plan")),
            )
          else
            AppCard(
              borderColor: AppColors.goldDim,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("CHECKOUT LINK", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
                  const SizedBox(height: 6),
                  SelectableText(_generatedUrl!, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: BtnGhost(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: _generatedUrl!));
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link copied.")));
                            }
                          },
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [Icon(LucideIcons.copy, size: 14), SizedBox(width: 6), Text("Copy link")],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: BtnGhost(
                          onPressed: () => launchUrl(Uri.parse(_generatedUrl!), mode: LaunchMode.externalApplication),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [Icon(LucideIcons.externalLink, size: 14), SizedBox(width: 6), Text("Open")],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      "The plan is only granted once the client actually completes payment on this link — nothing changes until then.",
                      style: TextStyle(fontSize: 11, color: AppColors.mute),
                    ),
                  ),
                ],
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
      _generatedUrl = null;
    });
    try {
      if (plan.priceCents <= 0) {
        await SupabaseService.updateClientRow(widget.info.id, membershipPlanId: plan.id);
        widget.onPlanAssigned(plan.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${plan.name} assigned to ${widget.info.name}.")));
          widget.onBack();
        }
        return;
      }
      final returnUrl = kIsWeb ? Uri.base.origin + Uri.base.path : "onefitness://checkout-return";
      final url = await SupabaseService.createCheckoutSession(
        planId: plan.id,
        returnUrl: returnUrl,
        couponCode: couponCode,
        targetClientId: widget.info.id,
      );
      if (mounted) setState(() => _generatedUrl = url);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
