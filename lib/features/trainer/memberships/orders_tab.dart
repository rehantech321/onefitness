import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/order.dart";

/// Staff view of merchandise orders: who bought what, and where each one is
/// in the fulfilment process.
///
/// Loaded on demand rather than held in a provider — orders are only looked
/// at deliberately, and staleness matters more here than anywhere else in
/// the app (two coaches both marking the same order collected is exactly the
/// confusion a fresh read avoids).
class OrdersTab extends ConsumerStatefulWidget {
  const OrdersTab({super.key});

  @override
  ConsumerState<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends ConsumerState<OrdersTab> {
  late Future<List<Order>> _future = SupabaseService.loadOrders();
  String _filter = "open";
  String? _busyId;

  void _reload() => setState(() => _future = SupabaseService.loadOrders());

  Future<void> _setStatus(Order order, String status) async {
    setState(() => _busyId = order.id);
    try {
      await SupabaseService.updateOrderStatus(order.id, status);
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${order.productName} → ${orderStatusLabel(status)}")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't update: ${e.toString().replaceFirst("Exception: ", "")}")),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Order>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HintBox(text: "Couldn't load orders: ${snap.error}"),
                const SizedBox(height: 10),
                BtnGhost(onPressed: _reload, child: const Text("Try again")),
              ],
            ),
          );
        }

        final all = snap.data ?? const <Order>[];
        // Open-first by default: an order that still needs doing is the
        // reason to be on this screen at all, and a completed backlog would
        // otherwise bury them within a few weeks.
        final shown = switch (_filter) {
          "open" => all.where((o) => o.isOpen).toList(),
          "done" => all.where((o) => !o.isOpen).toList(),
          _ => all,
        };
        final openCount = all.where((o) => o.isOpen).length;

        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                const Expanded(child: SectionLabel("Orders")),
                IconButton(
                  onPressed: _reload,
                  icon: const Icon(LucideIcons.refreshCw, size: 16, color: AppColors.mute),
                  tooltip: "Refresh",
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _FilterChip(label: "Open ($openCount)", selected: _filter == "open", onTap: () => setState(() => _filter = "open")),
                const SizedBox(width: 8),
                _FilterChip(label: "Completed", selected: _filter == "done", onTap: () => setState(() => _filter = "done")),
                const SizedBox(width: 8),
                _FilterChip(label: "All", selected: _filter == "all", onTap: () => setState(() => _filter = "all")),
              ],
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              HintBox(
                text: _filter == "open"
                    ? "No open orders — everything's been handed over."
                    : "Nothing here yet.",
              )
            else
              ...shown.map((o) => _OrderCard(
                    order: o,
                    busy: _busyId == o.id,
                    onSetStatus: (s) => _setStatus(o, s),
                  )),
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card,
          border: Border.all(color: selected ? AppColors.gold : AppColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.gold : AppColors.mute,
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.busy, required this.onSetStatus});

  final Order order;
  final bool busy;
  final ValueChanged<String> onSetStatus;

  @override
  Widget build(BuildContext context) {
    final placed = order.createdAt;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.productName,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(status: order.status),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            [
              order.clientName.isEmpty ? "Unknown buyer" : order.clientName,
              if ((order.size ?? "").isNotEmpty) "Size ${order.size}",
              if (order.quantity > 1) "x${order.quantity}",
              "\$${(order.amountCents / 100).toStringAsFixed(2)}",
              if (placed != null) "${placed.month}/${placed.day}/${placed.year % 100}",
            ].join(" · "),
            style: const TextStyle(fontSize: 11.5, color: AppColors.mute),
          ),
          if (order.status != "cancelled") ...[
            const SizedBox(height: 10),
            const Text("MOVE TO", style: TextStyle(fontSize: 9.5, color: AppColors.mute, letterSpacing: 1)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in kOrderStatuses)
                  if (s != order.status)
                    OutlinedButton(
                      onPressed: busy ? null : () => onSetStatus(s),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.line),
                        foregroundColor: AppColors.txt,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(orderStatusLabel(s), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                OutlinedButton(
                  onPressed: busy ? null : () => onSetStatus("cancelled"),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.line),
                    foregroundColor: const Color(0xFFC97F7F),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text("Cancel", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      "paid" => (AppColors.gold.withValues(alpha: 0.15), AppColors.gold),
      "preparing" => (const Color(0x1AC9784A), const Color(0xFFD68A4F)),
      "ready" => (const Color(0x1A4CAF50), AppColors.success),
      "completed" => (AppColors.bg, AppColors.mute),
      _ => (AppColors.bg, const Color(0xFFC97F7F)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        orderStatusLabel(status).toUpperCase(),
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.5),
      ),
    );
  }
}
