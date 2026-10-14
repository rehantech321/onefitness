/// One line in the owner's activity feed — a row of `activity_log`.
///
/// Written by database triggers rather than by the app, so it covers every
/// path a change can arrive by: the app, an Edge Function, the Stripe
/// webhook, or staff editing a row directly.
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.at,
    required this.action,
    required this.entity,
    required this.summary,
    this.actorName,
    this.subject,
    this.entityId,
  });

  final String id;
  final String at;

  /// sold | charged | created | edited | deleted | booked | moved |
  /// cancelled | attendance
  final String action;

  /// booking | charge | order | plan | product | client | settings
  final String entity;

  final String summary;

  /// Who did it. "System" for anything that happened without a signed-in
  /// person behind it — a Stripe webhook, a scheduled sweep.
  final String? actorName;

  /// The client it concerns, where there is one.
  final String? subject;

  final String? entityId;

  DateTime? get atTime => DateTime.tryParse(at)?.toLocal();

  /// True for things that moved money. Used to let the owner narrow the
  /// feed to sales without having to read every attendance tick.
  bool get isSale => action == "sold" || action == "charged";

  bool get isSession =>
      action == "booked" || action == "moved" || action == "cancelled" || action == "attendance";

  bool get isEdit => action == "created" || action == "edited" || action == "deleted";

  static ActivityEntry? fromJson(Map<String, dynamic> j) {
    final id = j["id"]?.toString();
    final summary = j["summary"]?.toString();
    if (id == null || summary == null) return null;
    return ActivityEntry(
      id: id,
      at: j["at"]?.toString() ?? "",
      action: j["action"]?.toString() ?? "",
      entity: j["entity"]?.toString() ?? "",
      summary: summary,
      actorName: j["actor_name"]?.toString(),
      subject: j["subject"]?.toString(),
      entityId: j["entity_id"]?.toString(),
    );
  }
}

/// The filters the feed offers, and what each one keeps.
enum ActivityFilter { all, sales, sessions, edits }

extension ActivityFilterX on ActivityFilter {
  String get label => switch (this) {
        ActivityFilter.all => "Everything",
        ActivityFilter.sales => "Sales",
        ActivityFilter.sessions => "Sessions",
        ActivityFilter.edits => "Edits",
      };

  bool matches(ActivityEntry e) => switch (this) {
        ActivityFilter.all => true,
        ActivityFilter.sales => e.isSale,
        ActivityFilter.sessions => e.isSession,
        ActivityFilter.edits => e.isEdit,
      };
}
