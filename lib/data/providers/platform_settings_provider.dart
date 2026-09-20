import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../core/utils/offered_catalog.dart";

/// One place the gym runs sessions at (Customize Platform → Location). The
/// first is the main one; the rest are extra sites a session can be created
/// at. A gym with a single location never sees any of this.
class GymLocation {
  const GymLocation({required this.name, this.address = "", this.hint = ""});

  final String name;
  final String address;

  /// "Park at the back", "Enter through the side door" — shown with the
  /// address wherever a client sees where their session is.
  final String hint;

  GymLocation copyWith({String? name, String? address, String? hint}) =>
      GymLocation(name: name ?? this.name, address: address ?? this.address, hint: hint ?? this.hint);
}

/// One fee profile (card or ACH) — mirrors platformSettings.js's
/// `cardFee`/`achFee` shape exactly (payments.cardFee / payments.achFee in
/// the real `platform_settings` row), including `structure` deciding which
/// of percent/flatCents actually applies (see calculateFeeCents.js).
class FeeProfile {
  const FeeProfile({
    this.enabled = false,
    this.label = "",
    this.structure = "percentage_flat", // percentage | flat | percentage_flat
    this.percent = 0,
    this.flatCents = 0,
  });

  final bool enabled;
  final String label;
  final String structure;
  final num percent;
  final int flatCents;
}

/// One owner-defined extra client-intake field — mirrors platformSettings.js
/// `clients.customProfileFields` entries (`{id, label, type}`).
class CustomProfileField {
  const CustomProfileField({required this.id, required this.label, this.type = "text"});

  final String id;
  final String label;
  final String type; // text | number | date
}

/// Mirrors data/platformSettings.js's owner-editable settings object.
/// A handful of read-only client-facing screens still reference the
/// hardcoded defaults in core/utils/platform_settings.dart rather than this
/// live provider (documented there) — this is the coach-facing settings UI
/// itself, which is real and fully interactive.
class PlatformSettings {
  const PlatformSettings({
    this.lateCancellationHours = 24,
    this.blockRescheduleInWindow = true,
    this.lateCancellationFeeCents = 2500,
    this.noShowFeeCents = 2500,
    this.maxBookingHorizonDays = 30,
    this.minBookingLeadHours = 2,
    this.bookingCoachScope = "assigned",
    this.semiPrivateCap = 4,
    this.twoFactorRequirement = "off",
    this.coachClientScope = "all",
    this.coachCanViewRevenue = false,
    this.coachCanSeeOtherSchedules = false,
    this.coachCanEditClientWorkouts = true,
    this.messageIdentity = "self",
    this.requiredProfileFields = const ["phone", "birthday", "city"],
    this.customProfileFields = const [],
    this.requireWaiverAtSignup = true,
    this.clientsCanMessageAnyCoach = false,
    this.achOffered = false,
    this.cardFee = const FeeProfile(label: "Card Processing Fee"),
    this.achFee = const FeeProfile(label: "Bank Transfer Fee"),
    this.checkoutDisclosureText = "",
    this.defaultBillingAnchorDay,
    this.refundFeeOnRefund = false,
    this.autoCarryOverLastWeight = true,
    this.defaultWeightUnit = "lb",
    this.clientsCanSwapExercises = false,
    this.businessTimeZone = "America/Los_Angeles",
    this.businessName = "ONE Fitness",
    this.offeredSessionTypes = const ["semi-private", "one-on-one", "large-group"],
    this.offeredDisciplines = const ["personal-training", "boxing", "hike", "outdoor-hiit", "stretch", "stick-mobility", "yoga"],
    this.sessionTypeCaps = const {},
    this.locations = const [],
    this.locationName = "",
    this.locationAddress = "",
    this.locationHint = "",
    this.meritBadgeProgressWeeks = 3,
    this.meritBadgeHabitPercent = 80,
    this.meritBadgeHabitWeeks = 3,
    this.badgeFullHouseCents = 2500,
    this.badgePrFactoryCents = 2500,
    this.badgeCheckInCents = 2500,
    this.badgeComebackCents = 3500,
    this.badgeHabitCoachCents = 2500,
    this.badgeChallengeCoachCents = 2500,
    this.badgeCoachOfMonthCents = 5000,
  });

  final int lateCancellationHours;
  final bool blockRescheduleInWindow;

  /// Charged (a real charge row) on a late cancellation — self-cancel
  /// inside the window, or a coach marking a booking "late-cancel" after
  /// the fact. Gives the session back either way (see
  /// membership_utils.dart's kGiveBackAttendanceStatuses).
  final int lateCancellationFeeCents;

  /// Charged when a coach marks a booking "no-show" — unlike a late
  /// cancellation, a no-show does NOT give the session back (Attendance &
  /// Cancellation Charging Policy, July 2026: a no-show costs the client
  /// both the fee and the session itself). Independent from
  /// [lateCancellationFeeCents] — the two are never assumed equal.
  final int noShowFeeCents;

  final int maxBookingHorizonDays;
  final int minBookingLeadHours;
  final String bookingCoachScope; // assigned | any
  final int semiPrivateCap;
  final String twoFactorRequirement; // off | staff | everyone
  final String coachClientScope; // own | all
  final bool coachCanViewRevenue;
  final bool coachCanSeeOtherSchedules;

  /// Off gives coaches read-only Plans — only the owner can build or edit
  /// workout/nutrition programs (see plans_tab.dart / program_builder_screen.dart).
  final bool coachCanEditClientWorkouts;
  final String messageIdentity; // self | business
  final List<String> requiredProfileFields; // subset of phone|birthday|city
  final List<CustomProfileField> customProfileFields;
  final bool requireWaiverAtSignup;
  final bool clientsCanMessageAnyCoach;
  final bool achOffered;
  final FeeProfile cardFee;
  final FeeProfile achFee;
  final String checkoutDisclosureText;

  /// Billing Cycle Anchor Date spec §2 — day-of-month (1-28) new
  /// subscriptions bill on going forward. Null means "off" — a new
  /// membership just bills on whatever day checkout happens, the
  /// pre-this-feature default. Only used at creation time (create-
  /// checkout-session); never retroactively shifts an existing client's
  /// own billing_anchor_day (see ClientInfo.billingAnchorDay).
  final int? defaultBillingAnchorDay;
  final bool refundFeeOnRefund;
  final bool autoCarryOverLastWeight;
  final String defaultWeightUnit; // lb | kg
  final bool clientsCanSwapExercises;
  final String businessTimeZone;
  final String businessName;

  // ── Services tab ──
  /// Which session types and disciplines the gym offers. Everything not
  /// listed disappears from the pickers staff and clients see when creating
  /// or booking a session — the catalogue itself is fixed, this narrows it.
  final List<String> offeredSessionTypes;
  final List<String> offeredDisciplines;

  /// How many clients each session type takes, by type key — the owner's own
  /// class-size limit, including for types they added themselves. A type with
  /// no entry here uses the built-in default (see capFor).
  final Map<String, int> sessionTypeCaps;

  /// Every location the gym runs sessions at. Empty means the single
  /// location in [locationName]/[locationAddress]/[locationHint] above.
  final List<GymLocation> locations;

  /// The locations to choose from, always including the main one — so this
  /// is never empty as long as a location name is set.
  List<GymLocation> get allLocations => [
        if (locationName.trim().isNotEmpty)
          GymLocation(name: locationName, address: locationAddress, hint: locationHint),
        ...locations.where((l) => l.name.trim().isNotEmpty && l.name != locationName),
      ];

  // ── Location tab ──
  /// The gym's physical location. Shown to clients on sessions whose coach
  /// hasn't set their own, and in the calendar feed.
  final String locationName;
  final String locationAddress;

  /// Parking / arrival notes, e.g. "Side entrance, buzz 4".
  final String locationHint;
  final int meritBadgeProgressWeeks;
  final int meritBadgeHabitPercent;
  final int meritBadgeHabitWeeks;

  /// Coach Merit Badge System — dollar rewards, owner-editable. Changing
  /// one only ever affects FUTURE badge earnings; each earned badge
  /// snapshots its own reward_cents at the moment it's awarded (see
  /// coach_merit_badge_utils.dart / SupabaseService.finalizeCoachBadgesForMonth),
  /// so past payouts never retroactively change.
  final int badgeFullHouseCents;
  final int badgePrFactoryCents;
  final int badgeCheckInCents;
  final int badgeComebackCents;
  final int badgeHabitCoachCents;
  final int badgeChallengeCoachCents;
  final int badgeCoachOfMonthCents;

  PlatformSettings copyWith({
    int? lateCancellationHours,
    bool? blockRescheduleInWindow,
    int? lateCancellationFeeCents,
    int? noShowFeeCents,
    int? maxBookingHorizonDays,
    int? minBookingLeadHours,
    String? bookingCoachScope,
    int? semiPrivateCap,
    String? twoFactorRequirement,
    String? coachClientScope,
    bool? coachCanViewRevenue,
    bool? coachCanSeeOtherSchedules,
    bool? coachCanEditClientWorkouts,
    String? messageIdentity,
    List<String>? requiredProfileFields,
    List<CustomProfileField>? customProfileFields,
    bool? requireWaiverAtSignup,
    bool? clientsCanMessageAnyCoach,
    bool? achOffered,
    FeeProfile? cardFee,
    FeeProfile? achFee,
    String? checkoutDisclosureText,
    int? defaultBillingAnchorDay,
    bool clearDefaultBillingAnchorDay = false,
    bool? refundFeeOnRefund,
    bool? autoCarryOverLastWeight,
    String? defaultWeightUnit,
    bool? clientsCanSwapExercises,
    String? businessTimeZone,
    String? businessName,
    List<String>? offeredSessionTypes,
    List<String>? offeredDisciplines,
    Map<String, int>? sessionTypeCaps,
    List<GymLocation>? locations,
    String? locationName,
    String? locationAddress,
    String? locationHint,
    int? meritBadgeProgressWeeks,
    int? meritBadgeHabitPercent,
    int? meritBadgeHabitWeeks,
    int? badgeFullHouseCents,
    int? badgePrFactoryCents,
    int? badgeCheckInCents,
    int? badgeComebackCents,
    int? badgeHabitCoachCents,
    int? badgeChallengeCoachCents,
    int? badgeCoachOfMonthCents,
  }) =>
      PlatformSettings(
        lateCancellationHours: lateCancellationHours ?? this.lateCancellationHours,
        blockRescheduleInWindow: blockRescheduleInWindow ?? this.blockRescheduleInWindow,
        lateCancellationFeeCents: lateCancellationFeeCents ?? this.lateCancellationFeeCents,
        noShowFeeCents: noShowFeeCents ?? this.noShowFeeCents,
        maxBookingHorizonDays: maxBookingHorizonDays ?? this.maxBookingHorizonDays,
        minBookingLeadHours: minBookingLeadHours ?? this.minBookingLeadHours,
        bookingCoachScope: bookingCoachScope ?? this.bookingCoachScope,
        semiPrivateCap: semiPrivateCap ?? this.semiPrivateCap,
        twoFactorRequirement: twoFactorRequirement ?? this.twoFactorRequirement,
        coachClientScope: coachClientScope ?? this.coachClientScope,
        coachCanViewRevenue: coachCanViewRevenue ?? this.coachCanViewRevenue,
        coachCanSeeOtherSchedules: coachCanSeeOtherSchedules ?? this.coachCanSeeOtherSchedules,
        coachCanEditClientWorkouts: coachCanEditClientWorkouts ?? this.coachCanEditClientWorkouts,
        messageIdentity: messageIdentity ?? this.messageIdentity,
        requiredProfileFields: requiredProfileFields ?? this.requiredProfileFields,
        customProfileFields: customProfileFields ?? this.customProfileFields,
        requireWaiverAtSignup: requireWaiverAtSignup ?? this.requireWaiverAtSignup,
        clientsCanMessageAnyCoach: clientsCanMessageAnyCoach ?? this.clientsCanMessageAnyCoach,
        achOffered: achOffered ?? this.achOffered,
        cardFee: cardFee ?? this.cardFee,
        achFee: achFee ?? this.achFee,
        checkoutDisclosureText: checkoutDisclosureText ?? this.checkoutDisclosureText,
        defaultBillingAnchorDay: clearDefaultBillingAnchorDay ? null : (defaultBillingAnchorDay ?? this.defaultBillingAnchorDay),
        refundFeeOnRefund: refundFeeOnRefund ?? this.refundFeeOnRefund,
        autoCarryOverLastWeight: autoCarryOverLastWeight ?? this.autoCarryOverLastWeight,
        defaultWeightUnit: defaultWeightUnit ?? this.defaultWeightUnit,
        clientsCanSwapExercises: clientsCanSwapExercises ?? this.clientsCanSwapExercises,
        businessTimeZone: businessTimeZone ?? this.businessTimeZone,
        businessName: businessName ?? this.businessName,
        offeredSessionTypes: offeredSessionTypes ?? this.offeredSessionTypes,
        offeredDisciplines: offeredDisciplines ?? this.offeredDisciplines,
        sessionTypeCaps: sessionTypeCaps ?? this.sessionTypeCaps,
        locations: locations ?? this.locations,
        locationName: locationName ?? this.locationName,
        locationAddress: locationAddress ?? this.locationAddress,
        locationHint: locationHint ?? this.locationHint,
        meritBadgeProgressWeeks: meritBadgeProgressWeeks ?? this.meritBadgeProgressWeeks,
        meritBadgeHabitPercent: meritBadgeHabitPercent ?? this.meritBadgeHabitPercent,
        meritBadgeHabitWeeks: meritBadgeHabitWeeks ?? this.meritBadgeHabitWeeks,
        badgeFullHouseCents: badgeFullHouseCents ?? this.badgeFullHouseCents,
        badgePrFactoryCents: badgePrFactoryCents ?? this.badgePrFactoryCents,
        badgeCheckInCents: badgeCheckInCents ?? this.badgeCheckInCents,
        badgeComebackCents: badgeComebackCents ?? this.badgeComebackCents,
        badgeHabitCoachCents: badgeHabitCoachCents ?? this.badgeHabitCoachCents,
        badgeChallengeCoachCents: badgeChallengeCoachCents ?? this.badgeChallengeCoachCents,
        badgeCoachOfMonthCents: badgeCoachOfMonthCents ?? this.badgeCoachOfMonthCents,
      );
}

class PlatformSettingsNotifier extends Notifier<PlatformSettings> {
  @override
  PlatformSettings build() => const PlatformSettings();

  void update(PlatformSettings Function(PlatformSettings) f) {
    state = f(state);
    LiveCatalog.sessionTypes = state.offeredSessionTypes.toSet();
    LiveCatalog.disciplines = state.offeredDisciplines.toSet();
    LiveCatalog.caps = state.sessionTypeCaps;
  }
}

final platformSettingsProvider = NotifierProvider<PlatformSettingsNotifier, PlatformSettings>(PlatformSettingsNotifier.new);

/// Customize Platform → Services is the catalogue: a session type or
/// discipline the owner deleted there is gone from every picker, booking
/// step and coach profile in the app. These are the one check they all use.
extension OfferedCatalog on PlatformSettings {
  /// "programmer" is a staff role (assessments), not a service clients pick,
  /// so it's never removed by the catalogue.
  bool offersDiscipline(String key) => key == "programmer" || offeredDisciplines.contains(key);

  /// Intake/assessment sessions are always available to staff.
  bool offersSessionType(String key) => key.startsWith("assessment") || offeredSessionTypes.contains(key);
}
