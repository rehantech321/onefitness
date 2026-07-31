/// Stand-in for src/data/platformSettings.js's getters — hardcoded to the
/// same defaults the web app ships with, until a real Settings screen
/// (owner-configurable) is built.
library;

const String kBusinessName = "ONE Fitness";
const bool kClientsCanMessageAnyCoach = false;
const String kMessageIdentity = "self"; // "self" | "business"

// scheduling defaults (DEFAULT_PLATFORM_SETTINGS.scheduling)
const int kLateCancellationHours = 24;
const bool kBlockRescheduleInWindow = true;
const int kLateCancellationFeeCents = 0;
const int kMaxBookingHorizonDays = 30;
const int kMinBookingLeadHours = 2;
const int kSemiPrivateCap = 4;
