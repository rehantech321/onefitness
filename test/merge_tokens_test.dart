import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/merge_token_utils.dart";
import "package:onefitness/data/models/client_info.dart";
import "package:onefitness/data/models/client_plan.dart";
import "package:onefitness/data/models/membership_plan.dart";

/// Merge tokens are what let one contract serve every client. The failure
/// that matters is a silent one: a token that doesn't resolve must stay
/// visible in the text rather than vanishing, because a membership
/// agreement that quietly loses the price is worse than one that obviously
/// hasn't been finished.
void main() {
  const client = ClientInfo(
    id: "c1",
    name: "Tina Smith",
    birthday: "1990-04-02",
    billingAnchorDay: 14,
    plans: [
      ClientPlanEnrollment(planId: "p1", status: "active", startDate: "2026-09-01"),
    ],
  );

  const plan = MembershipPlan(
    id: "p1",
    name: "8 Sessions / Month",
    kind: PlanKind.membership,
    priceCents: 48000,
    maxSessions: 8,
  );

  Map<String, String> values({MembershipPlan? forPlan = plan, String? business = "ONE Fitness"}) =>
      buildMergeTokenValues(info: client, businessName: business, plan: forPlan);

  group("the client's own details", () {
    test("name is split and offered whole", () {
      final v = values();
      expect(v["client_full_name"], "Tina Smith");
      expect(v["client_first_name"], "Tina");
      expect(v["client_last_name"], "Smith");
    });

    test("a one-word name leaves the last name blank rather than repeating it", () {
      final v = buildMergeTokenValues(info: const ClientInfo(id: "c1", name: "Cher"));
      expect(v["client_first_name"], "Cher");
      expect(v["client_last_name"], "");
    });
  });

  group("the gym and the plan", () {
    test("business name comes through", () {
      expect(values()["business_name"], "ONE Fitness");
    });

    test("the monthly charge is the plan's price", () {
      expect(values()["billing_amount"], r"$480.00");
    });

    test("the per-session rate is derived from the allowance", () {
      // $480 across 8 sessions.
      expect(values()["session_rate"], r"$60.00");
    });

    test("sessions per month comes from the plan", () {
      expect(values()["sessions_per_month"], "8");
    });

    test("the billing date reads as an ordinal", () {
      expect(values()["billing_anchor_date"], "14th");
    });

    test("ordinals are right for the awkward numbers", () {
      String anchorFor(int day) => buildMergeTokenValues(
            info: ClientInfo(id: "c1", name: "T", billingAnchorDay: day),
          )["billing_anchor_date"]!;
      expect(anchorFor(1), "1st");
      expect(anchorFor(2), "2nd");
      expect(anchorFor(3), "3rd");
      expect(anchorFor(4), "4th");
      // The teens are the trap: 11th, not 11st.
      expect(anchorFor(11), "11th");
      expect(anchorFor(12), "12th");
      expect(anchorFor(13), "13th");
      expect(anchorFor(21), "21st");
      expect(anchorFor(22), "22nd");
    });

    test("the start date is the client's own enrolment date", () {
      expect(values()["membership_start_date"], "2026-09-01");
    });
  });

  group("when something isn't known", () {
    test("a general waiver with no plan leaves plan tokens blank", () {
      final v = values(forPlan: null);
      expect(v["billing_amount"], "");
      expect(v["session_rate"], "");
      expect(v["plan_name"], "");
    });

    test("a plan with no session allowance gives no per-session rate", () {
      // An unlimited membership divided by zero sessions would otherwise
      // read "$0.00", as though sessions were free.
      const unlimited = MembershipPlan(
        id: "p2",
        name: "Unlimited",
        kind: PlanKind.membership,
        priceCents: 30000,
      );
      final v = buildMergeTokenValues(info: client, plan: unlimited);
      expect(v["session_rate"], "");
      expect(v["billing_amount"], r"$300.00");
    });

    test("no billing anchor set leaves the date blank", () {
      final v = buildMergeTokenValues(info: const ClientInfo(id: "c1", name: "T"));
      expect(v["billing_anchor_date"], "");
    });

    test("a start date is not invented before the plan is bought", () {
      final v = buildMergeTokenValues(
        info: const ClientInfo(id: "c1", name: "T"),
        plan: plan,
      );
      expect(v["membership_start_date"], "");
    });
  });

  group("substitution into a document", () {
    test("a known token is replaced", () {
      expect(
        resolveMergeTokens("Welcome {{client_full_name}}.", values()),
        "Welcome Tina Smith.",
      );
    });

    test("spacing inside the braces is tolerated", () {
      expect(resolveMergeTokens("{{ client_first_name }}", values()), "Tina");
    });

    test("an unknown token stays visible instead of disappearing", () {
      // The whole point: a typo must be obvious to whoever wrote the
      // contract, not silently blank out a clause.
      expect(
        resolveMergeTokens("Charge {{billingamount}} monthly.", values()),
        "Charge {{billingamount}} monthly.",
      );
    });

    test("square brackets are not a token syntax", () {
      // A contract written with [billingamount] renders literally.
      expect(
        resolveMergeTokens("Charge [billingamount] monthly.", values()),
        "Charge [billingamount] monthly.",
      );
    });

    test("a whole clause resolves end to end", () {
      const clause =
          "{{business_name}} will charge {{billing_amount}} on the {{billing_anchor_date}} "
          "for {{sessions_per_month}} sessions at {{session_rate}} each.";
      expect(
        resolveMergeTokens(clause, values()),
        r"ONE Fitness will charge $480.00 on the 14th for 8 sessions at $60.00 each.",
      );
    });
  });

  group("the structural markers", () {
    test("inline initial markers are counted in document order", () {
      const body = "A {{initial_1}} B {{initial_2}} C {{initial_3}}";
      expect(RegExp(r"\{\{\s*initial_\d+\s*\}\}").allMatches(body).length, 3);
    });

    test("readable text points numbered markers at the boxes below", () {
      final text = readableWaiverText("Clause one. {{initial_1}}", values());
      expect(text, contains("initial box 1 below"));
    });

    test("a bare signature marker is removed from the reading text", () {
      // It's captured in its own step, not inline.
      final text = readableWaiverText("Sign here: {{signature}}", values());
      expect(text, isNot(contains("{{signature}}")));
    });
  });
}
