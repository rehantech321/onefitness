import "../../data/models/booking.dart";
import "../../data/models/client_info.dart";
import "../../data/models/client_record.dart";
import "date_utils.dart";

/// One row in the coach dashboard's "Needs Attention" list.
class AttentionItem {
  const AttentionItem({required this.clientId, required this.key, required this.label, this.bookingId, this.date, this.slot});
  final String clientId;
  final String key;
  final String label;
  final String? bookingId;
  final String? date;
  final int? slot;
}

/// Mirrors attentionHelpers.js `computeNeedsAttention` — every roster
/// client this coach programs for who's missing an active workout and/or
/// nutrition program.
List<AttentionItem> computeNeedsAttention(List<ClientInfo> myRoster, Map<String, ClientRecord> clientRecords) {
  final out = <AttentionItem>[];
  for (final c in myRoster) {
    final rec = clientRecords[c.id];
    final hasProgram = rec?.savedPrograms.any((p) => p.status == "active") ?? false;
    final hasNutrition = rec?.nutrition != null;
    if (!hasProgram) out.add(AttentionItem(clientId: c.id, key: "no-program", label: "No workout program"));
    if (!hasNutrition) out.add(AttentionItem(clientId: c.id, key: "no-nutrition", label: "No nutrition program"));
  }
  return out;
}

/// Mirrors attentionHelpers.js `computeUnloggedAttendance` — past-or-today
/// sessions the coach never marked an outcome for.
List<AttentionItem> computeUnloggedAttendance(List<ClientInfo> myRoster, List<Booking> bookings) {
  final rosterIds = myRoster.map((c) => c.id).toSet();
  final today = isoToday();
  final matches = bookings.where((b) => rosterIds.contains(b.clientId) && b.attendanceStatus == null && b.date.compareTo(today) <= 0).toList()
    ..sort((a, b) => a.date == b.date ? a.slot.compareTo(b.slot) : a.date.compareTo(b.date));
  return matches
      .map((b) => AttentionItem(clientId: b.clientId, key: "no-attendance", label: "No attendance logged", bookingId: b.id, date: b.date, slot: b.slot))
      .toList();
}

/// One-time alert for a coach: a client just signed up using their Coach
/// Code. Fires once per referred client — clears (SupabaseService.
/// markCoachCodeAlertSeen) the first time the coach opens that client's
/// profile from this row (mirrors Coaches Overview's `reviewedByOwner`
/// pattern — see coaches_overview_screen.dart).
List<AttentionItem> computeCoachCodeAlerts(List<ClientInfo> myRoster) => myRoster
    .where((c) => c.referredByTrainerId != null && !c.coachCodeAlertSeen)
    .map((c) => AttentionItem(clientId: c.id, key: "coach-code-used", label: "Coach Code"))
    .toList();
