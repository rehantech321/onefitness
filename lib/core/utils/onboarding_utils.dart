import "package:lucide_flutter/lucide_flutter.dart";
import "package:flutter/widgets.dart" show IconData;
import "../../data/models/booking.dart";
import "../../data/models/client_record.dart";
import "../../data/models/membership_plan.dart";

/// Mirrors constants/domain.js `ONBOARDING_STEPS`.
class OnboardingStep {
  const OnboardingStep({required this.key, required this.label, required this.sub, required this.icon});
  final String key; // personalizedIntake | nutritionIntake | physicalAssessmentBooked
  final String label;
  final String sub;
  final IconData icon;
}

const kOnboardingSteps = [
  OnboardingStep(
    key: "personalizedIntake",
    label: "Personalized Training Intake",
    sub: "Complete your training questionnaire",
    icon: LucideIcons.clipboardList,
  ),
  OnboardingStep(
    key: "nutritionIntake",
    label: "Nutrition Program Intake",
    sub: "Complete your nutrition questionnaire",
    icon: LucideIcons.apple,
  ),
  OnboardingStep(
    key: "physicalAssessmentBooked",
    label: "Free Physical Assessment Session",
    sub: "Book your first training session with a Coach",
    icon: LucideIcons.dumbbell,
  ),
];

/// Mirrors intakeHelpers.js `getOnboardingStatus`'s single-field reads —
/// `client.intake[key].completed` for the two form steps, plus an actual
/// booked physical-assessment session (`Booking.isPhysicalAssessment`, the
/// real column the coach/web side already writes) for the third.
bool onboardingStepDone(ClientRecord client, List<Booking> bookings, String clientId, String stepKey) {
  switch (stepKey) {
    case "personalizedIntake":
      return client.intake["personalTraining"]?.completed ?? false;
    case "nutritionIntake":
      return client.intake["nutritional"]?.completed ?? false;
    case "physicalAssessmentBooked":
      return (client.intake["physical"]?.completed ?? false) ||
          bookings.any((b) => b.clientId == clientId && b.isPhysicalAssessment);
    default:
      return false;
  }
}

/// Mirrors intakeHelpers.js `hasSessionPlan` — only session-based
/// memberships/packages (maxSessions > 0) prompt for the physical assessment.
bool hasSessionPlan(MembershipPlan? plan) => plan != null && (plan.maxSessions ?? 0) > 0;

/// Mirrors intakeHelpers.js `getOnboardingAlerts`.
List<OnboardingStep> getOnboardingAlerts(ClientRecord client, List<Booking> bookings, String clientId, MembershipPlan? plan) {
  final showAssessment = hasSessionPlan(plan);
  return kOnboardingSteps.where((step) {
    if (step.key == "physicalAssessmentBooked" && !showAssessment) return false;
    return !onboardingStepDone(client, bookings, clientId, step.key);
  }).toList();
}
