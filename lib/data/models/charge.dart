/// Mirrors one entry in the gym's charge ledger (Reports → Financial).
/// `amount` is dollars (not cents) for simplicity on this trimmed model.
class Charge {
  const Charge({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.type, // "purchase" | "manual" | "early_termination_fee" | "late" | "noshow" — constrained by the real charges_type_check DB constraint
    required this.date, // ISO yyyy-MM-dd
    this.at = "", // stamp() human-readable string, e.g. "Aug 17, 6:00 AM"
    this.amount,
    this.category,
    this.description,
    this.planId,
    this.planName,
    this.trainerId,
    this.trainerName,
    this.waivedAt,
  });

  final String id;
  final String clientId;
  final String clientName;
  final String type;
  final String date;
  final String at;
  final double? amount;
  final String? category;
  final String? description;
  final String? planId;
  final String? planName;
  final String? trainerId;
  final String? trainerName;
  final String? waivedAt;
}
