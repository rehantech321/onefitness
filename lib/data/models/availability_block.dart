/// Mirrors one entry in trainer.availability — mirrors schedulingHelpers.js
/// `trainerBlocks`/`trainerOfferings`. `byDay` keys are JS-style weekday
/// numbers: 0=Sunday .. 6=Saturday.
class AvailabilityBlock {
  const AvailabilityBlock({
    required this.sessionType,
    required this.discipline,
    required this.byDay,
  });

  final String sessionType;
  final String discipline;
  final Map<int, List<int>> byDay; // weekday -> minutes-from-midnight slot starts
}
