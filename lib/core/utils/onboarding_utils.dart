import "package:lucide_flutter/lucide_flutter.dart";
import "package:flutter/widgets.dart" show IconData;
import "../../data/models/booking.dart";
import "../../data/models/client_record.dart";
import "../../data/models/membership_plan.dart";
import "intake_entitlements.dart";

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

/// Which onboarding step corresponds to which intake assessment — the two
/// vocabularies differ (the dashboard's step keys vs. the form catalogue's
/// assessment keys), and entitlements are expressed in the latter.
const _stepToAssessment = {
  "personalizedIntake": "personalTraining",
  "nutritionIntake": "nutritional",
  "physicalAssessmentBooked": "physical",
};

/// Mirrors intakeHelpers.js `getOnboardingAlerts`, plus purchase gating.
///
/// [entitlements] filters out steps the client hasn't unlocked. Prompting
/// someone to "complete your training questionnaire" and then handing them a
/// locked form would be a dead end — and the dashboard's prompt deep-links
/// straight into the form, so this is also what stops that link bypassing the
/// lock entirely.
List<OnboardingStep> getOnboardingAlerts(
  ClientRecord client,
  List<Booking> bookings,
  String clientId,
  MembershipPlan? plan, {
  required IntakeEntitlements entitlements,
}) {
  final showAssessment = hasSessionPlan(plan);
  return kOnboardingSteps.where((step) {
    if (step.key == "physicalAssessmentBooked" && !showAssessment) return false;
    final assessmentKey = _stepToAssessment[step.key];
    if (assessmentKey != null && !entitlements.allows(assessmentKey)) return false;
    return !onboardingStepDone(client, bookings, clientId, step.key);
  }).toList();
}
