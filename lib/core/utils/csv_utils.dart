/// Mirrors reportHelpers.js `downloadCSV`'s escaping — a value containing a
/// comma, quote, or newline gets wrapped in quotes with any inner quotes
/// doubled; everything else is written as-is. `rows` includes the header
/// row as its first entry (each report screen builds that itself, same as
/// web's `columns` label row).
String buildCsv(List<List<Object?>> rows) {
  String esc(Object? v) {
    final s = v?.toString() ?? "";
    return RegExp('[",\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  return rows.map((row) => row.map(esc).join(",")).join("\n");
}
