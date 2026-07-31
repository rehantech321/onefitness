/// One entry in ClientInfo.plans — mirrors { planId, status, startDate, termMonths }.
class ClientPlanEnrollment {
  const ClientPlanEnrollment({
    required this.planId,
    required this.status,
    required this.startDate,
    this.termMonths,
  });

  final String planId;
  final String status; // active | cancelled | ...
  final String startDate; // ISO yyyy-MM-dd
  final int? termMonths;
}
