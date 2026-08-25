import "package:flutter_riverpod/flutter_riverpod.dart";

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
    this.messageIdentity = "self",
    this.requiredProfileFields = const ["phone", "birthday", "city"],
    this.customProfileFields = const [],
    this.requireWaiverAtSignup = true,
    this.clientsCanMessageAnyCoach = false,
    this.achOffered = false,
    this.cardFee = const FeeProfile(label: "Card Processing Fee"),
    this.achFee = const FeeProfile(label: "Bank Transfer Fee"),
    this.checkoutDisclosureText = "",
    this.refundFeeOnRefund = false,
    this.autoCarryOverLastWeight = true,
    this.defaultWeightUnit = "lb",
    this.clientsCanSwapExercises = false,
    this.businessTimeZone = "America/Los_Angeles",
    this.businessName = "ONE Fitness",
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
  final String messageIdentity; // self | business
  final List<String> requiredProfileFields; // subset of phone|birthday|city
  final List<CustomProfileField> customProfileFields;
  final bool requireWaiverAtSignup;
  final bool clientsCanMessageAnyCoach;
  final bool achOffered;
  final FeeProfile cardFee;
  final FeeProfile achFee;
  final String checkoutDisclosureText;
  final bool refundFeeOnRefund;
  final bool autoCarryOverLastWeight;
  final String defaultWeightUnit; // lb | kg
  final bool clientsCanSwapExercises;
  final String businessTimeZone;
  final String businessName;
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
    String? messageIdentity,
    List<String>? requiredProfileFields,
    List<CustomProfileField>? customProfileFields,
    bool? requireWaiverAtSignup,
    bool? clientsCanMessageAnyCoach,
    bool? achOffered,
    FeeProfile? cardFee,
    FeeProfile? achFee,
    String? checkoutDisclosureText,
    bool? refundFeeOnRefund,
    bool? autoCarryOverLastWeight,
    String? defaultWeightUnit,
    bool? clientsCanSwapExercises,
    String? businessTimeZone,
    String? businessName,
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
        messageIdentity: messageIdentity ?? this.messageIdentity,
        requiredProfileFields: requiredProfileFields ?? this.requiredProfileFields,
        customProfileFields: customProfileFields ?? this.customProfileFields,
        requireWaiverAtSignup: requireWaiverAtSignup ?? this.requireWaiverAtSignup,
        clientsCanMessageAnyCoach: clientsCanMessageAnyCoach ?? this.clientsCanMessageAnyCoach,
        achOffered: achOffered ?? this.achOffered,
        cardFee: cardFee ?? this.cardFee,
        achFee: achFee ?? this.achFee,
        checkoutDisclosureText: checkoutDisclosureText ?? this.checkoutDisclosureText,
        refundFeeOnRefund: refundFeeOnRefund ?? this.refundFeeOnRefund,
        autoCarryOverLastWeight: autoCarryOverLastWeight ?? this.autoCarryOverLastWeight,
        defaultWeightUnit: defaultWeightUnit ?? this.defaultWeightUnit,
        clientsCanSwapExercises: clientsCanSwapExercises ?? this.clientsCanSwapExercises,
        businessTimeZone: businessTimeZone ?? this.businessTimeZone,
        businessName: businessName ?? this.businessName,
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

  void update(PlatformSettings Function(PlatformSettings) f) => state = f(state);
}

final platformSettingsProvider = NotifierProvider<PlatformSettingsNotifier, PlatformSettings>(PlatformSettingsNotifier.new);
