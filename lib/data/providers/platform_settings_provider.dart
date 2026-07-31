import "package:flutter_riverpod/flutter_riverpod.dart";

/// Mirrors data/platformSettings.js's owner-editable settings object.
/// Trimmed to the fields CustomizePlatform actually exposes a control for;
/// a handful of read-only client-facing screens still reference the
/// hardcoded defaults in core/utils/platform_settings.dart rather than this
/// live provider (documented there) — this is the coach-facing settings UI
/// itself, which is real and fully interactive.
class PlatformSettings {
  const PlatformSettings({
    this.lateCancellationHours = 24,
    this.maxBookingHorizonDays = 30,
    this.minBookingLeadHours = 2,
    this.semiPrivateCap = 4,
    this.twoFactorRequirement = "off",
    this.coachClientScope = "all",
    this.coachCanViewRevenue = false,
    this.coachCanSeeOtherSchedules = false,
    this.coachCanEditClientWorkouts = true,
    this.messageIdentity = "self",
    this.requireWaiverAtSignup = true,
    this.clientsCanMessageAnyCoach = false,
    this.processingFeeEnabled = false,
    this.feePercent = 0,
    this.autoCarryOverLastWeight = true,
    this.defaultWeightUnit = "lb",
    this.clientsCanSwapExercises = false,
    this.businessName = "ONE Fitness",
  });

  final int lateCancellationHours;
  final int maxBookingHorizonDays;
  final int minBookingLeadHours;
  final int semiPrivateCap;
  final String twoFactorRequirement; // off | staff | everyone
  final String coachClientScope; // own | all
  final bool coachCanViewRevenue;
  final bool coachCanSeeOtherSchedules;
  final bool coachCanEditClientWorkouts;
  final String messageIdentity; // self | business
  final bool requireWaiverAtSignup;
  final bool clientsCanMessageAnyCoach;
  final bool processingFeeEnabled;
  final num feePercent;
  final bool autoCarryOverLastWeight;
  final String defaultWeightUnit; // lb | kg
  final bool clientsCanSwapExercises;
  final String businessName;

  PlatformSettings copyWith({
    int? lateCancellationHours,
    int? maxBookingHorizonDays,
    int? minBookingLeadHours,
    int? semiPrivateCap,
    String? twoFactorRequirement,
    String? coachClientScope,
    bool? coachCanViewRevenue,
    bool? coachCanSeeOtherSchedules,
    bool? coachCanEditClientWorkouts,
    String? messageIdentity,
    bool? requireWaiverAtSignup,
    bool? clientsCanMessageAnyCoach,
    bool? processingFeeEnabled,
    num? feePercent,
    bool? autoCarryOverLastWeight,
    String? defaultWeightUnit,
    bool? clientsCanSwapExercises,
    String? businessName,
  }) =>
      PlatformSettings(
        lateCancellationHours: lateCancellationHours ?? this.lateCancellationHours,
        maxBookingHorizonDays: maxBookingHorizonDays ?? this.maxBookingHorizonDays,
        minBookingLeadHours: minBookingLeadHours ?? this.minBookingLeadHours,
        semiPrivateCap: semiPrivateCap ?? this.semiPrivateCap,
        twoFactorRequirement: twoFactorRequirement ?? this.twoFactorRequirement,
        coachClientScope: coachClientScope ?? this.coachClientScope,
        coachCanViewRevenue: coachCanViewRevenue ?? this.coachCanViewRevenue,
        coachCanSeeOtherSchedules: coachCanSeeOtherSchedules ?? this.coachCanSeeOtherSchedules,
        coachCanEditClientWorkouts: coachCanEditClientWorkouts ?? this.coachCanEditClientWorkouts,
        messageIdentity: messageIdentity ?? this.messageIdentity,
        requireWaiverAtSignup: requireWaiverAtSignup ?? this.requireWaiverAtSignup,
        clientsCanMessageAnyCoach: clientsCanMessageAnyCoach ?? this.clientsCanMessageAnyCoach,
        processingFeeEnabled: processingFeeEnabled ?? this.processingFeeEnabled,
        feePercent: feePercent ?? this.feePercent,
        autoCarryOverLastWeight: autoCarryOverLastWeight ?? this.autoCarryOverLastWeight,
        defaultWeightUnit: defaultWeightUnit ?? this.defaultWeightUnit,
        clientsCanSwapExercises: clientsCanSwapExercises ?? this.clientsCanSwapExercises,
        businessName: businessName ?? this.businessName,
      );
}

class PlatformSettingsNotifier extends Notifier<PlatformSettings> {
  @override
  PlatformSettings build() => const PlatformSettings();

  void update(PlatformSettings Function(PlatformSettings) f) => state = f(state);
}

final platformSettingsProvider = NotifierProvider<PlatformSettingsNotifier, PlatformSettings>(PlatformSettingsNotifier.new);
