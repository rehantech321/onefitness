/// Mirrors one row in `points_ledger` (src/data/pointsLedger.js's expected
/// shape) — an append-only points event. `type` drives replayLedger's FIFO
/// lot logic; `amount` is signed (positive for earn/grant, negative for
/// redeem/deduct/void/expire).
class PointsLedgerEntry {
  const PointsLedgerEntry({
    required this.id,
    required this.clientId,
    required this.amount,
    required this.type, // "earn" | "grant" | "redeem" | "deduct" | "void" | "expire"
    required this.source,
    required this.createdAt, // ISO date, drives replay ordering
    this.expiresAt,
    this.grantedByUserId,
    this.reason,
    this.voidedByLedgerId,
  });

  final String id;
  final String clientId;
  final int amount;
  final String type;
  final String source;
  final String createdAt;
  final String? expiresAt;
  final String? grantedByUserId;
  final String? reason;
  final String? voidedByLedgerId;
}
