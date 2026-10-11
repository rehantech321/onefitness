import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/items_sold.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/order.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
import "../../../data/models/report_range.dart";

/// Orders aren't part of the startup load — nothing outside the shop and
/// this report needs them — so they're fetched when the report opens. RLS
/// gives staff every order and a client only their own, so this is the
/// whole gym's merchandise sales.
final reportOrdersProvider = FutureProvider<List<Order>>((ref) async {
  return SupabaseService.loadOrders();
});

/// What sold, how many, and how that compares with the months before.
///
/// Deliberately separate from Itemized Sales, which lists every charge one
/// by one: that answers "where did this money come from", this answers
/// "what are we actually selling". Fees are money but not an item sold, so
/// they appear in that report and not in this one — which is why this
/// report's totals are smaller, and why the two are not meant to reconcile.
class ItemsSoldReport extends ConsumerWidget {
  const ItemsSoldReport({super.key, required this.range});
  final ReportRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charges = ref.watch(chargesProvider);
    final catalogue = ref.watch(membershipPlansProvider);
    final ordersAsync = ref.watch(reportOrdersProvider);

    return ordersAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      ),
      // Plan sales are still worth showing when merchandise can't be
      // loaded — a partial report that says so beats no report.
      error: (e, _) => _Body(
        charges: charges,
        orders: const [],
        catalogue: catalogue,
        range: range,
        warning: "Couldn't load merchandise orders, so product sales are missing below.",
      ),
      data: (orders) => _Body(
        charges: charges,
        orders: orders,
        catalogue: catalogue,
        range: range,
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.charges,
    required this.orders,
    required this.catalogue,
    required this.range,
    this.warning,
  });

  final List<dynamic> charges;
  final List<Order> orders;
  final List<dynamic> catalogue;
  final ReportRange range;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final groups = itemsSold(
      charges: charges.cast(),
      orders: orders,
      catalogue: catalogue.cast(),
      inRange: range.includes,
    );
    final totalUnits = groups.fold(0, (s, g) => s + g.units);
    final totalRevenue = groups.fold(0.0, (s, g) => s + g.revenue);

    // Six months back from today, regardless of the range above — the
    // trend table is the "previous months" view and shouldn't shrink to
    // whatever window is selected for the detail.
    final history = monthlyHistory(
      charges: charges.cast(),
      orders: orders,
      catalogue: catalogue.cast(),
      endingMonth: DateTime.now(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (warning != null) ...[
          HintBox(text: warning!),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: DownloadCsvButton(
            filename: "items-sold.csv",
            rows: [
              ["Section", "Group", "Item", "Units", "Revenue"],
              for (final g in groups)
                for (final i in g.items)
                  ["This period", g.kind.label, i.name, "${i.units}", i.revenue.toStringAsFixed(2)],
              [],
              ["Month", "Memberships", "Packages", "Programs", "Products", "Total units", "Revenue"],
              for (final m in history)
                [
                  monthLabel(m.month),
                  "${m.unitsOf(SoldKind.membership)}",
                  "${m.unitsOf(SoldKind.package)}",
                  "${m.unitsOf(SoldKind.program)}",
                  "${m.unitsOf(SoldKind.product)}",
                  "${m.units}",
                  m.revenue.toStringAsFixed(2),
                ],
            ],
          ),
        ),

        if (groups.isEmpty)
          const HintBox(text: "Nothing sold in this range.")
        else ...[
          AppCard(
            borderColor: AppColors.goldDim,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("$totalUnits item${totalUnits == 1 ? "" : "s"} sold",
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const Text("in the selected range",
                        style: TextStyle(fontSize: 11, color: AppColors.mute)),
                  ],
                ),
                Text(_money(totalRevenue),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.gold)),
              ],
            ),
          ),
          for (final g in groups) _GroupCard(group: g),
        ],

        const SizedBox(height: 6),
        const SectionLabel("Previous months"),
        const HintBox(text: "The last six months, whatever range is selected above. Counts are items sold in that month — a membership counts in the month it was bought, not again when it renews."),
        _HistoryTable(history: history),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});
  final SoldGroup group;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(group.kind.label,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gold,
                      letterSpacing: 0.8)),
              Text("${group.units} sold · ${_money(group.revenue)}",
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          if (group.kind == SoldKind.other)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                "Sold under a plan that's no longer in the catalogue, so it can't be filed under a type.",
                style: TextStyle(fontSize: 10.5, color: AppColors.mute, height: 1.35),
              ),
            ),
          const SizedBox(height: 8),
          for (final item in group.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Text("${item.units}×",
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.gold)),
                  ),
                  Expanded(
                    child: Text(item.name,
                        style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                  ),
                  Text(_money(item.revenue),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.mute)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryTable extends StatelessWidget {
  const _HistoryTable({required this.history});
  final List<MonthlySold> history;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          const Row(
            children: [
              Expanded(flex: 3, child: _H("Month")),
              Expanded(flex: 2, child: _H("Mem", right: true)),
              Expanded(flex: 2, child: _H("Pack", right: true)),
              Expanded(flex: 2, child: _H("Prod", right: true)),
              Expanded(flex: 3, child: _H("Total", right: true)),
            ],
          ),
          const Divider(color: AppColors.line, height: 14),
          for (var i = 0; i < history.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(monthLabel(history[i].month),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  Expanded(flex: 2, child: _N(history[i].unitsOf(SoldKind.membership))),
                  Expanded(flex: 2, child: _N(history[i].unitsOf(SoldKind.package))),
                  Expanded(flex: 2, child: _N(history[i].unitsOf(SoldKind.product))),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("${history[i].units}",
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.gold)),
                        // Against the month before it, and only when there
                        // is a month before it with something in it.
                        if (i + 1 < history.length)
                          Builder(builder: (context) {
                            final change =
                                percentChange(history[i].units, history[i + 1].units);
                            if (change == null) return const SizedBox.shrink();
                            final up = change >= 0;
                            return Text(
                              "${up ? "+" : ""}${change.round()}%",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: up ? AppColors.grn : AppColors.danger,
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _H extends StatelessWidget {
  const _H(this.text, {this.right = false});
  final String text;
  final bool right;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
            fontSize: 10, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 0.6),
      );
}

class _N extends StatelessWidget {
  const _N(this.value);
  final int value;

  @override
  Widget build(BuildContext context) => Text(
        value == 0 ? "—" : "$value",
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          // A zero month is real information, but it shouldn't shout.
          color: value == 0 ? AppColors.mute : AppColors.txt,
        ),
      );
}

String _money(double v) => "\$${v.toStringAsFixed(2)}";
