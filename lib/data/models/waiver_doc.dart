/// Mirrors a waiver/contract document (ManageWaivers.jsx) — either a
/// general signup waiver or a plan-specific contract.
class WaiverDoc {
  const WaiverDoc({
    required this.id,
    required this.title,
    required this.body,
    this.scope = "general", // "general" | "plan"
    this.planId,
    this.required = true,
    this.archived = false,
  });

  final String id;
  final String title;
  final String body;
  final String scope;
  final String? planId;
  final bool required;
  final bool archived;
}
