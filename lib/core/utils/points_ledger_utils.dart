import "../../data/models/points_ledger_entry.dart";
import "date_utils.dart";

/// Ported from src/data/pointsLedger.js — pure FIFO ledger-replay logic,
/// the single source of truth for balance, "expiring soon," and
/// redemption planning. Safe to port faithfully: no backend calls.

class PointsLot {
  PointsLot({required this.id, required this.source, required this.remaining, this.expiresAt});
  final String id;
  final String source;
  int remaining;
  final String? expiresAt;
}

class ReplayResult {
  const ReplayResult({required this.lots, required this.balance});
  final List<PointsLot> lots;
  final int balance;
}

DateTime _parse(String iso) => DateTime.parse(iso);

/// Mirrors `replayLedger` — replays every row in creation order, tracking
/// each earn/grant's remaining ("lot") amount as later redeem/deduct rows
/// consume the oldest still-live lots first.
ReplayResult replayLedger(List<PointsLedgerEntry> rows, {DateTime? now}) {
  final nowDt = now ?? _parse(isoToday());
  final sorted = [...rows]..sort((a, b) => a.createdAt == b.createdAt ? a.id.compareTo(b.id) : a.createdAt.compareTo(b.createdAt));

  final lotsById = <String, PointsLot>{};
  final lotsOrder = <String>[];

  void consumeFifo(int amountToConsume) {
    var left = amountToConsume;
    for (final lotId in lotsOrder) {
      if (left <= 0) break;
      final lot = lotsById[lotId]!;
      if (lot.remaining <= 0) continue;
      final take = lot.remaining < left ? lot.remaining : left;
      lot.remaining -= take;
      left -= take;
    }
  }

  for (final row in sorted) {
    if (row.type == "earn" || row.type == "grant") {
      final lot = PointsLot(id: row.id, source: row.source, remaining: row.amount, expiresAt: row.expiresAt);
      lotsById[row.id] = lot;
      lotsOrder.add(row.id);
    } else if (row.type == "void" || row.type == "expire") {
      final lot = row.voidedByLedgerId != null ? lotsById[row.voidedByLedgerId] : null;
      if (lot != null) lot.remaining = (lot.remaining - row.amount.abs()).clamp(0, 1 << 30);
    } else if (row.type == "redeem" || row.type == "deduct") {
      consumeFifo(row.amount.abs());
    }
  }

  final lots = lotsOrder.map((id) => lotsById[id]!).toList();
  bool isLive(PointsLot lot) => lot.remaining > 0 && (lot.expiresAt == null || _parse(lot.expiresAt!).isAfter(nowDt));
  final balance = lots.where(isLive).fold<int>(0, (sum, lot) => sum + lot.remaining);

  return ReplayResult(lots: lots, balance: balance);
}

/// Mirrors `expiringWithin` — lots with real remaining points expiring
/// within the next [days].
List<PointsLot> expiringWithin(List<PointsLot> lots, {DateTime? now, int days = 60}) {
  final nowDt = now ?? _parse(isoToday());
  final horizon = nowDt.add(Duration(days: days));
  return lots.where((lot) {
    if (lot.remaining <= 0 || lot.expiresAt == null) return false;
    final exp = _parse(lot.expiresAt!);
    return exp.isAfter(nowDt) && !exp.isAfter(horizon);
  }).toList();
}

class RedemptionPlan {
  const RedemptionPlan({required this.points});
  final int points;
}

/// Mirrors `planRedemption` — FIFO redemption plan, or null under the
/// minimum.
RedemptionPlan? planRedemption(List<PointsLot> lots, {DateTime? now, int capPoints = 40, int minPoints = 10}) {
  final nowDt = now ?? _parse(isoToday());
  final active = lots.where((lot) => lot.remaining > 0 && (lot.expiresAt == null || _parse(lot.expiresAt!).isAfter(nowDt)));
  final balance = active.fold<int>(0, (s, l) => s + l.remaining);
  if (balance < minPoints) return null;
  final points = balance < capPoints ? balance : capPoints;
  return RedemptionPlan(points: points);
}

/// Mirrors `pointsToDiscountCents` — 1 point = 0.5% = 50 basis points.
int pointsToDiscountCents(int points, int subtotalCents, {int rateBp = 50}) => (subtotalCents * points * rateBp / 10000).round();
