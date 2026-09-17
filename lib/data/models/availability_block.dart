/// Mirrors one entry in trainer.availability — mirrors schedulingHelpers.js
/// `trainerBlocks`/`trainerOfferings`. `byDay` keys are JS-style weekday
/// numbers: 0=Sunday .. 6=Saturday.
class AvailabilityBlock {
  const AvailabilityBlock({
    required this.sessionType,
    required this.discipline,
    required this.byDay,
    this.dates = const {},
    this.durationMin = 60,
  });

  final String sessionType;
  final String discipline;
  final Map<int, List<int>> byDay; // weekday -> minutes-from-midnight slot starts

  /// One-off sessions on specific calendar dates (ISO yyyy-MM-dd -> slot
  /// starts), as opposed to [byDay]'s weekly pattern. This is what the
  /// owner's "Create session" makes: a bookable session on a given day
  /// that doesn't repeat. Read alongside byDay everywhere offerings are
  /// computed — see trainerOfferingsOn.
  final Map<String, List<int>> dates;

  /// How long each session in this block runs. 60 unless the owner set an
  /// end time when creating it.
  final int durationMin;

  AvailabilityBlock copyWith({Map<int, List<int>>? byDay, Map<String, List<int>>? dates, int? durationMin}) =>
      AvailabilityBlock(
        sessionType: sessionType,
        discipline: discipline,
        byDay: byDay ?? this.byDay,
        dates: dates ?? this.dates,
        durationMin: durationMin ?? this.durationMin,
      );
}
