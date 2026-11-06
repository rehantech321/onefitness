import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/payments/payment_sheet_service.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/billing_address_form.dart";
import "../../../data/models/billing_address.dart";
import "../../../data/providers/client_providers.dart" show clientInfoProvider;
import "../../../core/widgets/widgets.dart";
import "../../../data/models/saved_payment_method.dart";
import "../../../data/providers/platform_settings_provider.dart";

/// Profile Settings → Payment Details: the cards and bank accounts saved when
/// the client paid for a membership or package. They're stored by Stripe on
/// the client's Customer (never by us) and offered again automatically at the
/// next checkout. The client can remove any except the one a live membership
/// renews on.
class PaymentDetailsSection extends ConsumerStatefulWidget {
  const PaymentDetailsSection({super.key, required this.onBack, this.clientId, this.clientName});
  final VoidCallback onBack;

  /// Set when a coach or owner is managing a client's payment methods; null
  /// for a client looking at their own.
  final String? clientId;
  final String? clientName;

  @override
  ConsumerState<PaymentDetailsSection> createState() => _PaymentDetailsSectionState();
}

class _PaymentDetailsSectionState extends ConsumerState<PaymentDetailsSection> {
  late Future<List<SavedPaymentMethod>> _future = SupabaseService.loadPaymentMethods(clientId: widget.clientId);
  String? _removing;
  bool _adding = false;

  /// Whose address and cards these are: the client being managed by staff,
  /// or the signed-in client themselves.
  String get _targetId => widget.clientId ?? ref.read(clientInfoProvider).id;

  late Future<BillingAddress?> _billingFuture = SupabaseService.loadBillingAddress(_targetId);

  Future<void> _editBilling() async {
    final updated = await ensureBillingAddress(context, clientId: _targetId, clientName: widget.clientName, forceEdit: true);
    if (updated != null && mounted) {
      setState(() => _billingFuture = Future.value(updated));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Billing address saved.")));
    }
  }

  Future<void> _addCard() async {
    setState(() => _adding = true);
    final billing = await ensureBillingAddress(context, clientId: _targetId, clientName: widget.clientName);
    if (billing == null) {
      if (mounted) setState(() => _adding = false);
      return;
    }
    final result = await PaymentSheetService.addPaymentMethod(
      businessName: ref.read(platformSettingsProvider).businessName,
      clientId: widget.clientId,
      billing: billing,
    );
    if (!mounted) return;
    setState(() => _adding = false);
    if (result.cancelled) return;
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error ?? "Couldn't save that card.")));
      return;
    }
    setState(() => _future = SupabaseService.loadPaymentMethods(clientId: widget.clientId));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Card saved.")));
  }

  Future<void> _remove(SavedPaymentMethod m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text("Remove payment method?"),
        content: Text(widget.clientId == null
            ? "${m.label} will be removed from your account. You can add it again at your next purchase."
            : "${m.label} will be removed from ${widget.clientName ?? "this client"}'s account."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Keep")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Remove", style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _removing = m.id);
    try {
      final next = await SupabaseService.loadPaymentMethods(removeId: m.id, clientId: widget.clientId);
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
        final next = SupabaseService.loadPaymentMethods(clientId: widget.clientId);
        setState(() => _future = next);
        await next;
      },
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          BackBar(onBack: widget.onBack, title: widget.clientName == null ? "Payment Details" : "${widget.clientName}'s Payment Details"),
          const SizedBox(height: 14),
          // Add a card up front, without waiting for a purchase — it's then
          // used for renewals and any cancellation fee.
          BtnGold(
            full: true,
            onPressed: _adding ? null : _addCard,
            child: Text(_adding ? "Opening…" : "Add card"),
          ),
          const SizedBox(height: 12),
          // Billing address — saved to the profile, reused for every purchase
          // and editable here.
          FutureBuilder<BillingAddress?>(
            future: _billingFuture,
            builder: (context, snap) {
              final a = snap.data;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  child: Row(
                    children: [
                      Icon(LucideIcons.mapPin, size: 20, color: AppColors.gold),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Billing address", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(
                              a == null
                                  ? (snap.connectionState == ConnectionState.done ? "Not added yet" : "Loading…")
                                  : [a.line1, if (a.line2.isNotEmpty) a.line2, "${a.city}, ${a.state} ${a.postalCode}"].join(", "),
                              style: TextStyle(fontSize: 12, color: AppColors.mute),
                            ),
                          ],
                        ),
                      ),
                      TextButton(onPressed: _editBilling, child: Text(a == null ? "Add" : "Edit")),
                    ],
                  ),
                ),
              );
            },
          ),
          FutureBuilder<List<SavedPaymentMethod>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: AppColors.gold)));
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
                                    style: TextStyle(fontSize: 12, color: AppColors.mute),
                                  ),
                                ],
                              ),
                            ),
                            if (_removing == m.id)
                              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold))
                            else
                              IconButton(
                                tooltip: "Remove",
                                onPressed: _removing != null ? null : () => _remove(m),
                                icon: Icon(LucideIcons.trash2, size: 17, color: AppColors.mute),
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
