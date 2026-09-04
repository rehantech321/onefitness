/// Mirrors one entry in client.measurements — free-text fields, same as the
/// web app (a trainer might log "185" or "185 lbs").
class Measurement {
  const Measurement({
    required this.id,
    required this.date,
    this.weight,
    this.bodyfat,
    this.chest,
    this.waist,
    this.hips,
    this.arms,
    this.thighs,
    this.coachComment,
    this.coachCommentAt,
  });

  final String id;
  final String date; // ISO yyyy-MM-dd
  final String? weight;
  final String? bodyfat;
  final String? chest;
  final String? waist;
  final String? hips;
  final String? arms;
  final String? thighs;

  /// A coach's note left on this specific entry (Notifications spec —
  /// "Coach comments on a measurement"), shown to the client and emailed
  /// once on save. One comment per entry, editable — not a full thread.
  final String? coachComment;
  final String? coachCommentAt;

  /// (key, label, value) pairs — mirrors schemas.js `MEASURE_FIELDS` order.
  List<(String, String, String?)> get fields => [
        ("weight", "Weight", weight),
        ("bodyfat", "Body Fat %", bodyfat),
        ("chest", "Chest", chest),
        ("waist", "Waist", waist),
        ("hips", "Hips", hips),
        ("arms", "Arms", arms),
        ("thighs", "Thighs", thighs),
      ];

  Measurement copyWith({String? coachComment, String? coachCommentAt}) => Measurement(
        id: id,
        date: date,
        weight: weight,
        bodyfat: bodyfat,
        chest: chest,
        waist: waist,
        hips: hips,
        arms: arms,
        thighs: thighs,
        coachComment: coachComment ?? this.coachComment,
        coachCommentAt: coachCommentAt ?? this.coachCommentAt,
      );
}
