import "../../data/models/client_info.dart";

/// Who currently holds a given plan.
///
/// A client can hold a plan two ways, and both count:
///
///   membershipPlanId  the primary slot — the plan Change Access, freezing
///                     and cancellation act on
///   plans[]           everything they hold, which is how someone can have
///                     a membership and a package at the same time
///
/// Checking only the first would miss anyone holding this plan alongside
/// another, which is exactly the case a gym selling packages on top of
/// memberships runs into. Only `active` enrolments count: a cancelled one
/// is history, not access.
List<ClientInfo> membersOnPlan(List<ClientInfo> roster, String planId) {
  final out = roster
      .where((c) =>
          c.membershipPlanId == planId ||
          c.plans.any((pl) => pl.planId == planId && pl.status == "active"))
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

/// Whether this plan is the one occupying the client's primary slot, as
/// opposed to something they hold alongside it. Worth showing, because only
/// the primary one is what freezing and cancelling act on.
bool isPrimaryPlan(ClientInfo client, String planId) =>
    client.membershipPlanId == planId;

/// When this client started on this plan, or null if it isn't recorded —
/// which is the case for a plan assigned by a coach rather than bought.
String? planStartDate(ClientInfo client, String planId) {
  for (final pl in client.plans) {
    if (pl.planId == planId && pl.status == "active") {
      return pl.startDate.trim().isEmpty ? null : pl.startDate;
    }
  }
  return null;
}

/// The date this client's plan is set to end, when they've cancelled it but
/// it's still running out the time they paid for. Null while it's simply
/// active — there's nothing to warn about then.
String? planEndsOn(ClientInfo client, String planId) {
  for (final pl in client.plans) {
    if (pl.planId != planId || pl.status != "active") continue;
    final cancels = pl.cancelsAt?.trim();
    if (cancels != null && cancels.isNotEmpty) return cancels;
    final ends = pl.endsAt?.trim();
    if (ends != null && ends.isNotEmpty) return ends;
  }
  return null;
}
