import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/order.dart";

/// A client's own merchandise orders and where each one has got to.
///
/// RLS scopes this to the signed-in user, so it calls the same loadOrders()
/// the staff screen does — there's no client-specific query to keep in step.
class MyOrdersSection extends ConsumerStatefulWidget {
  const MyOrdersSection({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<MyOrdersSection> createState() => _MyOrdersSectionState();
}

class _MyOrdersSectionState extends ConsumerState<MyOrdersSection> {
  late Future<List<Order>> _future = SupabaseService.loadOrders();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onBack, title: "Profile Settings"),
          const SizedBox(height: 10),
          const SectionLabel("My Orders"),
          const SizedBox(height: 10),
          FutureBuilder<List<Order>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const HintBox(text: "Couldn't load your orders just now."),
                    const SizedBox(height: 10),
                    BtnGhost(
                      onPressed: () => setState(() => _future = SupabaseService.loadOrders()),
                      child: const Text("Try again"),
                    ),
                  ],
                );
              }
              final orders = snap.data ?? const <Order>[];
              if (orders.isEmpty) {
                return const HintBox(text: "No orders yet. Anything you buy from the Shop shows up here.");
              }
              return Column(children: orders.map((o) => _OrderCard(order: o)).toList());
            },
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final cancelled = order.status == "cancelled";
    // Where this order sits on the paid → preparing → ready → collected
    // track. Cancelled has no position on it, so the tracker is hidden
    // rather than shown stalled at some arbitrary point.
    final stepIndex = kOrderStatuses.indexOf(order.status);
    final placed = order.createdAt;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(order.productName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              Text(
                "\$${(order.amountCents / 100).toStringAsFixed(2)}",
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.gold),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              if ((order.size ?? "").isNotEmpty) "Size ${order.size}",
              if (order.quantity > 1) "x${order.quantity}",
              if (placed != null) "Ordered ${placed.month}/${placed.day}/${placed.year % 100}",
            ].join(" · "),
            style: const TextStyle(fontSize: 11.5, color: AppColors.mute),
          ),
          const SizedBox(height: 12),
          if (!cancelled && stepIndex >= 0)
            Row(
              children: [
                for (var i = 0; i < kOrderStatuses.length; i++) ...[
                  if (i > 0)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i <= stepIndex ? AppColors.gold : AppColors.line,
                      ),
                    ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= stepIndex ? AppColors.gold : AppColors.card,
                      border: Border.all(color: i <= stepIndex ? AppColors.gold : AppColors.line, width: 2),
                    ),
                  ),
                ],
              ],
            ),
          if (!cancelled && stepIndex >= 0) const SizedBox(height: 8),
          Row(
            children: [
              Text(
                orderStatusLabel(order.status),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: cancelled ? const Color(0xFFC97F7F) : AppColors.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            orderStatusBlurb(order.status),
            style: const TextStyle(fontSize: 11.5, color: AppColors.mute, height: 1.4),
          ),
        ],
      ),
    );
  }
}
