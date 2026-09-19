/// The session types and disciplines the gym currently offers (Customize
/// Platform → Services), for the plain helper functions that have no
/// Riverpod access — trainerOfferings and everything built on it (booking
/// slots, the schedule, capacity). PlatformSettingsNotifier keeps this in
/// step on every settings change, so a type or discipline the owner deletes
/// stops being offered anywhere in the app, even if a coach's saved weekly
/// availability still lists it.
class LiveCatalog {
  LiveCatalog._();

  /// Null until settings have loaded — everything counts as offered then.
  static Set<String>? sessionTypes;
  static Set<String>? disciplines;

  static bool offersType(String sessionType) =>
      sessionType.startsWith("assessment") || sessionTypes == null || sessionTypes!.contains(sessionType);

  static bool offersDiscipline(String discipline) =>
      discipline == "programmer" || disciplines == null || disciplines!.contains(discipline);

  static bool offers(String sessionType, String discipline) => offersType(sessionType) && offersDiscipline(discipline);
}
