import "../../data/models/client_record.dart";
import "../widgets/status_dot.dart";
import "date_utils.dart";

/// Mirrors lib/helpers.js's `computeClientStatus` — derived from logged
/// sessions, never set by hand. Trimmed to `workoutLogs` (the structured
/// per-set logger); the legacy free-text `client.logs` path and the
/// goal-weight-measurement bonus rule aren't modeled here. Returns the same
/// [ClientStatus] enum StatusDot renders.
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
ClientStatus computeClientStatus(ClientRecord record) {
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

  if (logs.isEmpty) return ClientStatus.newClient;
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
