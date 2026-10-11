import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/items_sold.dart";
import "package:onefitness/data/models/charge.dart";
import "package:onefitness/data/models/membership_plan.dart";
import "package:onefitness/data/models/order.dart";

/// "What did we sell, how many, and how does that compare with last month."
///
/// The arithmetic has two traps worth guarding: a product purchase writes
/// both an order and a charge, so it can easily be counted twice; and an
/// order can be for more than one of something, so counting rows instead of
/// quantities undercounts.
void main() {
  MembershipPlan plan(String id, String name, PlanKind kind) =>
      MembershipPlan(id: id, name: name, kind: kind);

  final catalogue = [
    plan("p-gold", "Gold Membership", PlanKind.membership),
    plan("p-10pack", "10 Session Package", PlanKind.package),
    plan("p-prog", "12 Week Program", PlanKind.program),
    plan("p-nutri", "Nutrition Plan", PlanKind.nutritionProgram),
  ];

  Charge sale({
    required String date,
    String? planId = "p-gold",
    String? planName = "Gold Membership",
    double? amount = 100,
    String type = "purchase",
    String? waivedAt,
    String? description,
  }) =>
      Charge(
        id: "c-$date-$planId-$amount",
        clientId: "cl1",
        clientName: "Tina",
        type: type,
        date: date,
        amount: amount,
        planId: planId,
        planName: planName,
        description: description,
        waivedAt: waivedAt,
      );

  Order order({
    required DateTime at,
    String productName = "Gym Shirt",
    int quantity = 1,
    int amountCents = 2500,
    String status = "paid",
  }) =>
      Order(
        id: "o-${at.millisecondsSinceEpoch}-$productName-$quantity",
        clientId: "cl1",
        clientName: "Tina",
        productId: "prod-1",
        productName: productName,
        status: status,
        quantity: quantity,
        amountCents: amountCents,
        createdAt: at,
      );

  List<SoldGroup> soldIn(
    String month, {
    List<Charge> charges = const [],
    List<Order> orders = const [],
  }) =>
      itemsSold(
        charges: charges,
        orders: orders,
        catalogue: catalogue,
        inRange: (d) => d.startsWith(month),
      );

  SoldGroup? groupOf(List<SoldGroup> groups, SoldKind kind) {
    for (final g in groups) {
      if (g.kind == kind) return g;
    }
    return null;
  }

  group("classifying what was sold", () {
    test("a membership lands under Memberships", () {
      expect(kindForPlan("p-gold", catalogue), SoldKind.membership);
    });

    test("a package lands under Packages", () {
      expect(kindForPlan("p-10pack", catalogue), SoldKind.package);
    });

    test("both program types are counted together", () {
      expect(kindForPlan("p-prog", catalogue), SoldKind.program);
      expect(kindForPlan("p-nutri", catalogue), SoldKind.program);
    });

    test("a plan no longer in the catalogue is not guessed at", () {
      // Filing a sale in the wrong column is worse than admitting we can't
      // tell. Real data has charges pointing at plans that were deleted.
      expect(kindForPlan("oneonone-package", catalogue), SoldKind.other);
    });

    test("a charge with no plan at all is not a plan sale", () {
      expect(kindForPlan(null, catalogue), SoldKind.other);
    });
  });

  group("what counts as a sale", () {
    test("a purchase does", () {
      expect(isPlanSale(sale(date: "2026-10-02")), isTrue);
    });

    test("a late-cancel fee does not — it is money, not an item sold", () {
      expect(
        isPlanSale(sale(date: "2026-10-02", type: "late", planId: null)),
        isFalse,
      );
    });

    test("a waived charge does not — it was never collected", () {
      expect(
        isPlanSale(sale(date: "2026-10-02", waivedAt: "2026-10-03")),
        isFalse,
      );
    });

    test("a flag-only row with no amount does not", () {
      expect(isPlanSale(sale(date: "2026-10-02", amount: null)), isFalse);
    });

    test("a cancelled order does not", () {
      expect(isProductSale(order(at: DateTime(2026, 10, 2), status: "cancelled")), isFalse);
      expect(isProductSale(order(at: DateTime(2026, 10, 2), status: "paid")), isTrue);
      expect(isProductSale(order(at: DateTime(2026, 10, 2), status: "completed")), isTrue);
    });
  });

  group("counting units", () {
    test("each plan purchase is one sale", () {
      final groups = soldIn("2026-10", charges: [
        sale(date: "2026-10-01"),
        sale(date: "2026-10-05", amount: 120),
      ]);
      expect(groupOf(groups, SoldKind.membership)!.units, 2);
    });

    test("an order of three shirts is three sold, not one", () {
      // Counting rows instead of quantities is the easy mistake here.
      final groups = soldIn("2026-10", orders: [
        order(at: DateTime(2026, 10, 3), quantity: 3, amountCents: 7500),
      ]);
      final products = groupOf(groups, SoldKind.product)!;
      expect(products.units, 3);
      expect(products.revenue, 75);
    });

    test("the same item bought twice is one line with two units", () {
      final groups = soldIn("2026-10", charges: [
        sale(date: "2026-10-01"),
        sale(date: "2026-10-09"),
      ]);
      final memberships = groupOf(groups, SoldKind.membership)!;
      expect(memberships.items.length, 1);
      expect(memberships.items.single.units, 2);
      expect(memberships.items.single.revenue, 200);
    });

    test("a product purchase is not also counted as a plan", () {
      // A product writes an order AND a charge. The charge carries no
      // plan_id, so it must not appear in any plan group.
      final groups = soldIn(
        "2026-10",
        charges: [sale(date: "2026-10-03", planId: null, planName: null, description: "Gym Shirt x1")],
        orders: [order(at: DateTime(2026, 10, 3))],
      );
      expect(groupOf(groups, SoldKind.product)!.units, 1);
      expect(groupOf(groups, SoldKind.membership), isNull);
      expect(groupOf(groups, SoldKind.other), isNull);
    });

    test("items outside the period are left out", () {
      final groups = soldIn("2026-10", charges: [
        sale(date: "2026-09-30"),
        sale(date: "2026-10-01"),
        sale(date: "2026-11-01"),
      ]);
      expect(groupOf(groups, SoldKind.membership)!.units, 1);
    });

    test("a deleted plan still reports under the name it sold as", () {
      final groups = soldIn("2026-10", charges: [
        sale(date: "2026-10-02", planId: "gone", planName: "One-on-One Package"),
      ]);
      final other = groupOf(groups, SoldKind.other)!;
      expect(other.items.single.name, "One-on-One Package");
      expect(other.units, 1);
    });

    test("empty groups are not shown at all", () {
      final groups = soldIn("2026-10", charges: [sale(date: "2026-10-02")]);
      expect(groups.map((g) => g.kind), [SoldKind.membership]);
    });
  });

  group("ordering", () {
    test("best seller first", () {
      final groups = soldIn("2026-10", orders: [
        order(at: DateTime(2026, 10, 1), productName: "Shaker", quantity: 1),
        order(at: DateTime(2026, 10, 2), productName: "Shirt", quantity: 5),
        order(at: DateTime(2026, 10, 3), productName: "Cap", quantity: 3),
      ]);
      expect(
        groupOf(groups, SoldKind.product)!.items.map((i) => i.name),
        ["Shirt", "Cap", "Shaker"],
      );
    });

    test("groups come out in a fixed order", () {
      final groups = soldIn(
        "2026-10",
        charges: [
          sale(date: "2026-10-01", planId: "p-10pack", planName: "10 Session Package"),
          sale(date: "2026-10-02"),
        ],
        orders: [order(at: DateTime(2026, 10, 3))],
      );
      expect(groups.map((g) => g.kind),
          [SoldKind.membership, SoldKind.package, SoldKind.product]);
    });
  });

  group("previous months", () {
    final charges = [
      sale(date: "2026-10-02"),
      sale(date: "2026-09-10"),
      sale(date: "2026-09-20"),
      sale(date: "2026-08-05"),
    ];

    test("returns the requested number of months, newest first", () {
      final months = monthlyHistory(
        charges: charges,
        orders: const [],
        catalogue: catalogue,
        endingMonth: DateTime(2026, 10),
        count: 3,
      );
      expect(months.map((m) => m.month), ["2026-10", "2026-09", "2026-08"]);
    });

    test("each month counts only its own sales", () {
      final months = monthlyHistory(
        charges: charges,
        orders: const [],
        catalogue: catalogue,
        endingMonth: DateTime(2026, 10),
        count: 3,
      );
      expect(months[0].unitsOf(SoldKind.membership), 1);
      expect(months[1].unitsOf(SoldKind.membership), 2);
      expect(months[2].unitsOf(SoldKind.membership), 1);
    });

    test("a month with nothing sold is still listed", () {
      // A blank row answers "how did we do in July"; dropping it would look
      // like missing data.
      final months = monthlyHistory(
        charges: [sale(date: "2026-10-02")],
        orders: const [],
        catalogue: catalogue,
        endingMonth: DateTime(2026, 10),
        count: 2,
      );
      expect(months.length, 2);
      expect(months[1].units, 0);
    });

    test("stepping back over a year boundary works", () {
      final months = monthlyHistory(
        charges: const [],
        orders: const [],
        catalogue: catalogue,
        endingMonth: DateTime(2026, 2),
        count: 4,
      );
      expect(months.map((m) => m.month), ["2026-02", "2026-01", "2025-12", "2025-11"]);
    });
  });

  group("presentation helpers", () {
    test("a month reads as a person would say it", () {
      expect(monthLabel("2026-10"), "Oct 2026");
      expect(monthLabel("2025-01"), "Jan 2025");
    });

    test("a malformed month is passed through rather than crashing", () {
      expect(monthLabel("nonsense"), "nonsense");
      expect(monthLabel("2026-13"), "2026-13");
    });

    test("change against last month", () {
      expect(percentChange(12, 10), closeTo(20, 0.001));
      expect(percentChange(8, 10), closeTo(-20, 0.001));
    });

    test("no comparison is offered against a month with nothing in it", () {
      // "+100%" against zero would be an invention, not a trend.
      expect(percentChange(5, 0), isNull);
    });
  });
}
