/// A date range for Reports/My Pay — mirrors reportHelpers.js's `range`
/// shape `{ preset, start, end }`, both ISO dates inclusive.
class ReportRange {
  const ReportRange({required this.preset, required this.start, required this.end});
  final String preset; // "today" | "week" | "month" | "quarter" | "year" | "custom"
  final String start;
  final String end;

  bool includes(String isoDate) => isoDate.compareTo(start) >= 0 && isoDate.compareTo(end) <= 0;
}
