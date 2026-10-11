import "../../data/models/charge.dart";
import "../../data/models/membership_plan.dart";
import "../../data/models/order.dart";

/// What sold, how much of it, and for how much — the arithmetic behind the
/// Items Sold report, kept out of the widget so it can be tested.
///
/// Two sources, deliberately not merged:
///
///   plans     charges with a plan_id — memberships, packages and programs
///   products  the `orders` table, which carries a quantity
///
/// A product purchase writes BOTH an order and a charge (the order is what
/// staff hand over, the charge is the money). Counting products from orders
/// and plans from charges-with-a-plan partitions the two cleanly: every
/// product charge has a null plan_id, so nothing is counted twice and
/// nothing is missed.
///
/// These are SALES, not revenue-in-period. A membership renewing next month
/// writes no new charge, so it is one sale in the month it was bought and
/// not another one after — which is what "items sold" means, and why this
/// report's totals are smaller than the revenue reports'.

/// The groups the report shows, in the order it shows them.
enum SoldKind { membership, package, program, product, other }

extension SoldKindX on SoldKind {
  String get label => switch (this) {
        SoldKind.membership => "Memberships",
        SoldKind.package => "Packages",
        SoldKind.program => "Programs",
        SoldKind.product => "Products",
        SoldKind.other => "Other",
      };

  /// Plural noun for a single line's count, e.g. "3 sold".
  String get unit => this == SoldKind.product ? "sold" : "sold";
}

/// One catalogue item and how it did in the period.
class SoldItem {
  const SoldItem({
    required this.name,
    required this.kind,
    required this.units,
    required this.revenue,
  });

  final String name;
  final SoldKind kind;
  final int units;
  final double revenue;

  SoldItem plus({int units = 0, double revenue = 0}) => SoldItem(
        name: name,
        kind: kind,
        units: this.units + units,
        revenue: this.revenue + revenue,
      );
}

/// A whole group — Memberships, Packages, Products — with its items.
class SoldGroup {
  const SoldGroup({required this.kind, required this.items});
  final SoldKind kind;
  final List<SoldItem> items;

  int get units => items.fold(0, (sum, i) => sum + i.units);
  double get revenue => items.fold(0.0, (sum, i) => sum + i.revenue);
}

/// Which group a plan belongs in.
///
/// The catalogue is the source of truth. A plan that has since been deleted
/// or renamed can't be classified, and is NOT guessed at from its name — a
/// sales report that silently files things in the wrong column is worse
/// than one that admits it doesn't know. Those land in [SoldKind.other],
/// where the item name still shows so the owner can see what it was.
SoldKind kindForPlan(String? planId, List<MembershipPlan> catalogue) {
  if (planId == null) return SoldKind.other;
  for (final p in catalogue) {
    if (p.id != planId) continue;
    return switch (p.kind) {
      PlanKind.membership => SoldKind.membership,
      PlanKind.package => SoldKind.package,
      // Personalized and nutrition programs are both programming rather
      // than gym access, and an owner asking "what did we sell" wants them
      // together.
      PlanKind.program || PlanKind.nutritionProgram => SoldKind.program,
    };
  }
  return SoldKind.other;
}

/// True for a charge that represents buying something from the catalogue.
///
/// Fees (late cancel, no-show, termination) are money but not an item sold,
/// and a waived charge was never collected — neither belongs in a count of
/// what the gym sold.
bool isPlanSale(Charge c) =>
    c.type == "purchase" && c.planId != null && c.amount != null && c.waivedAt == null;

/// A cancelled order is not a sale. Everything else — paid, preparing,
/// ready, completed — is something the client bought.
bool isProductSale(Order o) => o.status != "cancelled";

/// Everything sold in one period, grouped and ordered.
///
/// [inRange] decides the period, so the caller keeps control of what "this
/// month" means and the same function serves both the current period and
/// each historical month.
List<SoldGroup> itemsSold({
  required List<Charge> charges,
  required List<Order> orders,
  required List<MembershipPlan> catalogue,
  required bool Function(String isoDate) inRange,
}) {
  final byKey = <String, SoldItem>{};

  void add(String name, SoldKind kind, int units, double revenue) {
    final key = "${kind.name}|${name.trim().toLowerCase()}";
    final existing = byKey[key];
    byKey[key] = existing == null
        ? SoldItem(name: name.trim(), kind: kind, units: units, revenue: revenue)
        : existing.plus(units: units, revenue: revenue);
  }

  for (final c in charges) {
    if (!isPlanSale(c) || !inRange(c.date)) continue;
    // The name recorded on the charge, not the catalogue's current one: a
    // plan renamed or deleted since should still report under what it was
    // actually sold as.
    final name = (c.planName?.trim().isNotEmpty ?? false)
        ? c.planName!
        : (c.description?.trim().isNotEmpty ?? false)
            ? c.description!
            : "Unnamed plan";
    add(name, kindForPlan(c.planId, catalogue), 1, c.amount ?? 0);
  }

  for (final o in orders) {
    final at = o.createdAt;
    if (at == null || !isProductSale(o)) continue;
    if (!inRange(at.toLocal().toIso8601String().substring(0, 10))) continue;
    // quantity, not one per order — three shirts in one order is three sold.
    add(o.productName, SoldKind.product, o.quantity, o.amountCents / 100);
  }

  final groups = <SoldGroup>[];
  for (final kind in SoldKind.values) {
    final items = byKey.values.where((i) => i.kind == kind).toList()
      // Best seller first; ties broken by revenue, then name, so the order
      // is stable rather than depending on map iteration.
      ..sort((a, b) {
        final byUnits = b.units.compareTo(a.units);
        if (byUnits != 0) return byUnits;
        final byRevenue = b.revenue.compareTo(a.revenue);
        return byRevenue != 0 ? byRevenue : a.name.compareTo(b.name);
      });
    if (items.isNotEmpty) groups.add(SoldGroup(kind: kind, items: items));
  }
  return groups;
}

/// One month's totals, for the trend table.
class MonthlySold {
  const MonthlySold({required this.month, required this.groups});

  /// "YYYY-MM".
  final String month;
  final List<SoldGroup> groups;

  int unitsOf(SoldKind kind) =>
      groups.where((g) => g.kind == kind).fold(0, (s, g) => s + g.units);

  double revenueOf(SoldKind kind) =>
      groups.where((g) => g.kind == kind).fold(0.0, (s, g) => s + g.revenue);

  int get units => groups.fold(0, (s, g) => s + g.units);
  double get revenue => groups.fold(0.0, (s, g) => s + g.revenue);
}

/// The last [count] months ending with [endingMonth], newest first.
///
/// Months with nothing sold are still included: a blank row is the useful
/// answer to "how did we do in August", and dropping it would make a quiet
/// month look like missing data.
List<MonthlySold> monthlyHistory({
  required List<Charge> charges,
  required List<Order> orders,
  required List<MembershipPlan> catalogue,
  required DateTime endingMonth,
  int count = 6,
}) {
  final out = <MonthlySold>[];
  for (var back = 0; back < count; back++) {
    final m = DateTime(endingMonth.year, endingMonth.month - back);
    final key = "${m.year.toString().padLeft(4, "0")}-${m.month.toString().padLeft(2, "0")}";
    out.add(MonthlySold(
      month: key,
      groups: itemsSold(
        charges: charges,
        orders: orders,
        catalogue: catalogue,
        inRange: (d) => d.startsWith(key),
      ),
    ));
  }
  return out;
}

/// "Oct 2026" from "2026-10".
String monthLabel(String yyyyMm) {
  const names = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ];
  final parts = yyyyMm.split("-");
  if (parts.length != 2) return yyyyMm;
  final m = int.tryParse(parts[1]);
  if (m == null || m < 1 || m > 12) return yyyyMm;
  return "${names[m - 1]} ${parts[0]}";
}

/// Change against the month before, as a percentage. Null when there's
/// nothing to compare against — a first month has no trend, and showing
/// "+100%" against zero would be an invention.
double? percentChange(num now, num before) {
  if (before == 0) return null;
  return (now - before) / before * 100;
}
