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

  /// What the client will actually be charged, in dollars. Starts at the
  /// plan's own price and is editable — a coach agreeing a different rate
  /// with a client shouldn't have to create a whole plan for it. For a
  /// membership this becomes the recurring amount too, so the client pays
  /// the agreed rate every month rather than only the first.
  final _price = TextEditingController();

  /// When this access stops. Memberships default to a month out; anything
  /// else starts with no expiry unless the plan sets one, and staff can
  /// change any of it.
  DateTime? _expiresAt;

  /// So re-picking the same plan doesn't wipe an edit the coach just made.
  String? _defaultsFor;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  /// Fills the price and expiry from a newly-picked plan.
  void _applyPlanDefaults(MembershipPlan plan) {
    if (_defaultsFor == plan.id) return;
    _defaultsFor = plan.id;
    _price.text = (plan.priceCents / 100).toStringAsFixed(2);
    _expiresAt = _defaultExpiryFor(plan);
  }

  /// A monthly membership runs a month; a plan with its own expiry window
  /// uses that; everything else has none until someone sets one.
  DateTime? _defaultExpiryFor(MembershipPlan plan) {
    final now = DateTime.now();
    if (plan.kind == PlanKind.membership) {
      return DateTime(now.year, now.month + 1, now.day);
    }
    if (plan.expirationEnabled && (plan.expirationDays ?? 0) > 0) {
      return now.add(Duration(days: plan.expirationDays!));
    }
    return null;
  }

  String? get _expiryIso =>
      _expiresAt == null ? null : _expiresAt!.toIso8601String().substring(0, 10);

  int? get _priceOverrideCents {
    final typed = double.tryParse(_price.text.trim());
    if (typed == null) return null;
    return (typed * 100).round();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? DateTime(now.year, now.month + 1, now.day),
      // Access can't expire before it starts; five years is further ahead
      // than any membership this gym sells.
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

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
                  _applyPlanDefaults(p);
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
          if (plan != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FieldLabeled(
                    label: plan.kind == PlanKind.membership ? "Price (\$ / month)" : "Price (\$)",
                    child: AppField(
                      kind: FieldKind.decimal,
                      controller: _price,
                      onChanged: (_) => setState(() => _error = null),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FieldLabeled(
                    label: "Access expires",
                    child: InkWell(
                      onTap: _pickExpiry,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          border: Border.all(color: AppColors.line),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _expiresAt == null ? "No expiry" : _expiryIso!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _expiresAt == null ? AppColors.mute : AppColors.txt,
                                ),
                              ),
                            ),
                            const Icon(LucideIcons.calendar, size: 14, color: AppColors.mute),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _expiresAt == null
                        ? "Access doesn't run out. Set a date to give it a limit."
                        : "Sessions can't be booked against this plan after this date.",
                    style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.3),
                  ),
                ),
                if (_expiresAt != null)
                  TextButton(
                    onPressed: () => setState(() => _expiresAt = null),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.mute,
                      minimumSize: const Size(44, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text("Clear", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ],
          if (plan != null && (_priceOverrideCents ?? plan.priceCents) > 0) ...[
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
                  : (plan != null && (_priceOverrideCents ?? plan.priceCents) > 0
                      ? "Take payment"
                      : "Assign plan"),
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
      // The typed price decides this, not the plan's own: a coach can sell a
      // normally-paid plan for nothing (a comp, a make-good) and a free plan
      // for a price, and either should do the right thing.
      final chargeCents = _priceOverrideCents ?? plan.priceCents;
      if (chargeCents <= 0) {
        // Server-side: `plans` is a grant (it unlocks intake forms), and this
        // also keeps a program from overwriting the client's membership.
        await SupabaseService.enrollFreePlan(
          plan.id,
          clientId: widget.info.id,
          accessExpiresAt: _expiryIso,
        );
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
        // Only sent when it differs from the plan, so an ordinary sale is
        // still priced entirely server-side. Either way the server re-checks
        // that whoever asked for it is staff.
        priceOverrideCents: chargeCents == plan.priceCents ? null : chargeCents,
        accessExpiresAt: _expiryIso,
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
