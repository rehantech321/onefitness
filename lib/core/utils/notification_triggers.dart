import "../supabase/supabase_service.dart";

/// Notifications spec — event-triggered emails. Each function is
/// deliberately fire-and-forget (best-effort, swallows its own errors) so a
/// notification failure can never block or roll back the real action it's
/// attached to (a plan getting assigned, an attendance mark landing) — same
/// principle stripe-webhook's `sendReferralEmail` already follows.
Future<void> notifyPlanAssigned({
  required String toEmail,
  required String toName,
  required String kind, // "workout" | "nutrition"
}) async {
  if (toEmail.isEmpty) return;
  final label = kind == "workout" ? "workout" : "nutrition";
  try {
    await SupabaseService.sendEmail(
      to: toEmail,
      subject: "Your new $label plan is ready",
      text: "Hi $toName,\n\nYour coach just assigned you a new $label plan. Open the ONE Fitness app to check it out.\n\n— ONE Fitness",
    );
  } catch (_) {}
}

const kSessionMilestones = [10, 25, 50, 100];

/// Fires once when [totalCheckedIn] (this client's total checked-in session
/// count, AFTER the attendance mark that triggered this call) lands exactly
/// on one of [kSessionMilestones] — called right after a booking is marked
/// checked-in, with the freshly-recounted total, so it only ever fires on
/// the one booking that actually crosses the line.
Future<void> notifySessionMilestoneIfCrossed({
  required String toEmail,
  required String toName,
  required int totalCheckedIn,
}) async {
  if (toEmail.isEmpty || !kSessionMilestones.contains(totalCheckedIn)) return;
  try {
    await SupabaseService.sendEmail(
      to: toEmail,
      subject: "You just hit $totalCheckedIn sessions!",
      text: "Hi $toName,\n\nCongratulations — you've completed $totalCheckedIn sessions at ONE Fitness. Keep up the great work!\n\n— ONE Fitness",
    );
  } catch (_) {}
}
