import "../../data/models/booking.dart";
import "../../data/models/client_record.dart";
import "../widgets/status_dot.dart";
import "date_utils.dart";

/// Mirrors lib/helpers.js's `computeClientStatus` — derived from logged
/// sessions, never set by hand. Trimmed to `workoutLogs` (the structured
/// per-set logger); the legacy free-text `client.logs` path and the
/// goal-weight-measurement bonus rule aren't modeled here. Returns the same
/// [ClientStatus] enum StatusDot renders.
///
/// "New Client" exists to flag a client the coach still needs to run a
/// physical assessment on — it's not tied to the structured per-set logger
/// specifically, since a first session (an assessment especially) often
/// isn't logged that way at all. So [bookings] (that client's own bookings)
/// clears "New" the moment they have any checked-in session on record, even
/// with zero workoutLogs yet — otherwise a client whose only completed
/// session was an assessment would stay stuck as "New" forever.
class _SessionItem {
  const _SessionItem({required this.key, this.weight, this.reps});
  final String key;
  final double? weight;
  final int? reps;
}

class _Session {
  const _Session({required this.date, required this.items});
  final String date;
  final List<_SessionItem> items;
}

double _daysSince(String isoDate) => DateTime.parse(isoToday()).difference(DateTime.parse(isoDate)).inHours / 24.0;

/// Mirrors lib/helpers.js `computeClientStatus`.
ClientStatus computeClientStatus(ClientRecord record, {List<Booking> bookings = const []}) {
  final logs = record.workoutLogs
      .map((log) => _Session(
            date: log.date,
            items: log.exercises.map((ex) {
              final doneSets = ex.sets.where((s) => s.completed);
              final bestWeight = doneSets.fold<double>(0, (m, s) => (s.completedWeight ?? 0) > m ? (s.completedWeight ?? 0) : m);
              final bestReps = doneSets.fold<int>(0, (m, s) => (s.completedReps ?? 0) > m ? (s.completedReps ?? 0) : m);
              return _SessionItem(key: ex.name, weight: bestWeight > 0 ? bestWeight : null, reps: bestReps > 0 ? bestReps : null);
            }).toList(),
          ))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  final checkedIn = bookings.where((b) => b.attendanceStatus == "checked-in").map((b) => b.date).toList();
  if (logs.isEmpty && checkedIn.isEmpty) return ClientStatus.newClient;

  if (logs.isEmpty) {
    // At least one completed (checked-in) session, but nothing yet through
    // the structured per-set logger — e.g. the physical assessment itself
    // isn't logged that way. Nothing to judge improvement from, so this
    // just applies the same 7-day recency rule off the most recent
    // checked-in date.
    final lastCheckedIn = checkedIn.reduce((a, b) => a.compareTo(b) > 0 ? a : b);
    return _daysSince(lastCheckedIn) > 7 ? ClientStatus.red : ClientStatus.yellow;
  }
  final lastLog = logs.last;

  String? lastProgressDate;
  for (var i = 0; i < logs.length; i++) {
    final log = logs[i];
    var improved = false;
    for (final item in log.items) {
      for (var j = i - 1; j >= 0; j--) {
        final prevMatches = logs[j].items.where((p) => p.key == item.key);
        if (prevMatches.isNotEmpty) {
          final prev = prevMatches.first;
          if ((item.weight != null && prev.weight != null && item.weight! > prev.weight!) ||
              (item.reps != null && prev.reps != null && item.reps! > prev.reps!)) {
            improved = true;
          }
          break;
        }
      }
    }
    if (improved) lastProgressDate = log.date;
  }

  if (logs.length == 1 && lastProgressDate == null) lastProgressDate = lastLog.date;

  if (_daysSince(lastLog.date) > 7) return ClientStatus.red;
  if (lastProgressDate != null && _daysSince(lastProgressDate) <= 7) return ClientStatus.green;
  return ClientStatus.yellow;
}
