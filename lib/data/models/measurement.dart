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
}
