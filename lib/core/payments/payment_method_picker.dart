import "dart:io" show Platform;
import "package:flutter/foundation.dart" show kIsWeb;
import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../theme/app_colors.dart";
import "../../data/models/membership_plan.dart";

/// How a purchase is being paid for. Card and ACH both run through Stripe's
/// Payment Sheet (they only differ in which processing-fee profile applies);
/// Apple Pay is a wallet the sheet layers on top of card.
enum PayTender { card, ach, applePay }

/// Which tenders a given product type accepts. Deliberately derived from the
/// plan, not from a global setting:
///   membership → card, debit, ACH.  No Apple Pay.
///   package    → card, debit, ACH, Apple Pay.
/// The server enforces the same rule in create-payment-intent — this list
/// only decides what's offered.
List<PayTender> tendersFor(MembershipPlan plan) {
  final isPackage = plan.kind == PlanKind.package;
  return [
    PayTender.card,
    PayTender.ach,
    // Apple Pay is iOS-only hardware; offering it anywhere else is a dead
    // button, so it's filtered by platform as well as by product type.
    if (isPackage && !kIsWeb && Platform.isIOS) PayTender.applePay,
  ];
}

String tenderLabel(PayTender t) => switch (t) {
  PayTender.card => "Credit or debit card",
  PayTender.ach => "Bank transfer (ACH)",
  PayTender.applePay => "Apple Pay",
};

String tenderHint(PayTender t) => switch (t) {
  PayTender.card => "Pay securely in the app.",
  PayTender.ach => "Straight from your bank account.",
  PayTender.applePay => "Confirm with Face ID or Touch ID.",
};

IconData tenderIcon(PayTender t) => switch (t) {
  PayTender.card => LucideIcons.creditCard,
  PayTender.ach => LucideIcons.building2,
  PayTender.applePay => LucideIcons.smartphone,
};

/// Sheet asking how to pay, shown before the Stripe sheet so the fee profile
/// and tender rules are settled first. Returns null if dismissed.
Future<PayTender?> showPaymentMethodPicker(BuildContext context, MembershipPlan plan) {
  final options = tendersFor(plan);
  // Nothing to choose between — don't make them tap through a one-item list.
  if (options.length == 1) return Future.value(options.first);

  return showModalBottomSheet<PayTender>(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "How would you like to pay?",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.txt),
            ),
            const SizedBox(height: 4),
            Text(
              plan.name,
              style: const TextStyle(fontSize: 12, color: AppColors.mute),
            ),
            const SizedBox(height: 14),
            for (final t in options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => Navigator.pop(ctx, t),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      border: Border.all(color: AppColors.line),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(tenderIcon(t), size: 18, color: AppColors.gold),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tenderLabel(t), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 1),
                              Text(tenderHint(t), style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                            ],
                          ),
                        ),
                        const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
