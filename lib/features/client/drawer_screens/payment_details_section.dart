import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/saved_payment_method.dart";

/// Profile Settings → Payment Details: the cards and bank accounts saved when
/// the client paid for a membership or package. They're stored by Stripe on
/// the client's Customer (never by us) and offered again automatically at the
/// next checkout. The client can remove any except the one a live membership
/// renews on.
class PaymentDetailsSection extends StatefulWidget {
  const PaymentDetailsSection({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<PaymentDetailsSection> createState() => _PaymentDetailsSectionState();
}

class _PaymentDetailsSectionState extends State<PaymentDetailsSection> {
  late Future<List<SavedPaymentMethod>> _future = SupabaseService.loadPaymentMethods();
  String? _removing;

  Future<void> _remove(SavedPaymentMethod m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text("Remove payment method?"),
        content: Text("${m.label} will be removed from your account. You can add it again at your next purchase."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Keep")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Remove", style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _removing = m.id);
    try {
      final next = await SupabaseService.loadPaymentMethods(removeId: m.id);
      if (mounted) setState(() => _future = Future.value(next));
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst("Exception: ", "");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.contains("renews on") ? msg : "Couldn't remove it — check your connection and try again.")));
      }
    } finally {
      if (mounted) setState(() => _removing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: () async {
        final next = SupabaseService.loadPaymentMethods();
        setState(() => _future = next);
        await next;
      },
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          BackBar(onBack: widget.onBack, title: "Payment Details"),
          const SizedBox(height: 14),
          FutureBuilder<List<SavedPaymentMethod>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: AppColors.gold)));
              }
              if (snap.hasError) {
                return const HintBox(text: "Couldn't load your payment details — pull down to try again.");
              }
              final methods = snap.data ?? const [];
              if (methods.isEmpty) {
                return const HintBox(
                  text: "No saved payment method yet. When you buy a membership or package, your card is saved here automatically so you don't have to enter it again next time.",
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final m in methods)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        borderColor: m.isDefault ? AppColors.gold : null,
                        child: Row(
                          children: [
                            Icon(m.isCard ? LucideIcons.creditCard : LucideIcons.landmark, size: 20, color: AppColors.gold),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      if (m.expiry != null) "Expires ${m.expiry}",
                                      if (m.isDefault) "Used for membership renewals",
                                    ].join(" · ").ifEmpty(m.isCard ? "Saved card" : "Saved bank account"),
                                    style: const TextStyle(fontSize: 12, color: AppColors.mute),
                                  ),
                                ],
                              ),
                            ),
                            if (_removing == m.id)
                              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold))
                            else
                              IconButton(
                                tooltip: "Remove",
                                onPressed: _removing != null ? null : () => _remove(m),
                                icon: const Icon(LucideIcons.trash2, size: 17, color: AppColors.mute),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  const HintBox(text: "Your card details are stored securely by Stripe, not by ONE Fitness. Saved methods are offered automatically at your next checkout."),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
