/// Mirrors src/data/platformSettings.js's DEFAULT_PLATFORM_SETTINGS —
/// fallback values only. The real, owner-editable settings live in
/// `data/providers/platform_settings_provider.dart`'s `platformSettingsProvider`
/// (loaded from the real `platform_settings` Supabase row at bootstrap).
/// These consts exist purely so `core/utils/booking_utils.dart`'s plain
/// (non-Riverpod) functions have a sensible default parameter value when a
/// caller genuinely can't reach the live provider — every real UI call site
/// must pass the live value instead of relying on the default here.
library;

const String kBusinessName = "ONE Fitness";
const bool kClientsCanMessageAnyCoach = false;
const String kMessageIdentity = "self"; // "self" | "business"

// scheduling defaults (DEFAULT_PLATFORM_SETTINGS.scheduling)
const int kLateCancellationHours = 24;
const bool kBlockRescheduleInWindow = true;
const int kLateCancellationFeeCents = 2500;
const int kNoShowFeeCents = 2500;
const int kMaxBookingHorizonDays = 30;
const int kMinBookingLeadHours = 2;
const int kSemiPrivateCap = 4;
