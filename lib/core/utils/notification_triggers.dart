import "../../data/models/measurement.dart";
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

/// Push counterpart to every email trigger above/below that also appears on
/// the PUSH NOTIFICATION list — deliberately generic (one function, not a
/// wrapper per event) since a push is just a short title/body, unlike the
/// longer per-event email copy. Silently a no-op end-to-end until the
/// recipient has a registered device token (see SupabaseService.
/// sendPushNotification's own doc comment).
Future<void> notifyPush({
  required String profileId,
  required String title,
  required String body,
  Map<String, String>? data,
}) async {
  if (profileId.isEmpty) return;
  try {
    await SupabaseService.sendPushNotification(profileId: profileId, title: title, body: body, data: data);
  } catch (_) {}
}

/// Fires once when [totalCheckedIn] (this client's total checked-in session
/// count, AFTER the attendance mark that triggered this call) lands exactly
/// on one of [kSessionMilestones] — called right after a booking is marked
/// checked-in, with the freshly-recounted total, so it only ever fires on
/// the one booking that actually crosses the line. Sends both the email and
/// (if [profileId] is given) the matching push in one call, since they
/// share the exact same "did we just cross a milestone" gate.
Future<void> notifySessionMilestoneIfCrossed({
  required String toEmail,
  required String toName,
  required int totalCheckedIn,
  String? profileId,
}) async {
  if (!kSessionMilestones.contains(totalCheckedIn)) return;
  if (toEmail.isNotEmpty) {
    try {
      await SupabaseService.sendEmail(
        to: toEmail,
        subject: "You just hit $totalCheckedIn sessions!",
        text: "Hi $toName,\n\nCongratulations — you've completed $totalCheckedIn sessions at ONE Fitness. Keep up the great work!\n\n— ONE Fitness",
      );
    } catch (_) {}
  }
  if (profileId != null) {
    notifyPush(profileId: profileId, title: "Milestone reached! 🎉", body: "You've completed $totalCheckedIn sessions at ONE Fitness.");
  }
}

/// "Coach comments on a workout, progress photo, or measurement" — fires to
/// the client whenever a coach saves a comment on one of their entries.
/// [kind] is purely for the email wording ("workout session" | "progress
/// photo" | "measurement entry").
Future<void> notifyCoachComment({
  required String toEmail,
  required String toName,
  required String kind,
}) async {
  if (toEmail.isEmpty) return;
  try {
    await SupabaseService.sendEmail(
      to: toEmail,
      subject: "Your coach left you a comment",
      text: "Hi $toName,\n\nYour coach just left a comment on one of your $kind entries. Open the ONE Fitness app to see it.\n\n— ONE Fitness",
    );
  } catch (_) {}
}

/// Mirrors helpers.js `parseLeadingNum` — measurement fields are free text
/// (e.g. "185" or "185 lbs"), so this pulls the leading numeric portion.
double? parseLeadingNum(String? s) {
  if (s == null || s.isEmpty) return null;
  final m = RegExp(r"\d+(\.\d+)?").firstMatch(s);
  return m == null ? null : double.tryParse(m.group(0)!);
}

/// "Goal reached" — fires once, the first time a client's logged weight
/// lands within half a pound of their stated goal weight (intake's
/// `goalWeight` — nutritional intake takes precedence, same fallback order
/// challenge scoring already uses). [priorMeasurements] is the list BEFORE
/// [latest] was added, so this can tell "just crossed" from "was already
/// there" and never re-fire on every measurement after the first.
Future<void> notifyGoalReachedIfCrossed({
  required String toEmail,
  required String toName,
  required List<Measurement> priorMeasurements,
  required Measurement latest,
  required double? goalWeight,
}) async {
  if (toEmail.isEmpty || goalWeight == null) return;
  final latestWeight = parseLeadingNum(latest.weight);
  if (latestWeight == null || (latestWeight - goalWeight).abs() > 0.5) return;
  final alreadyThereBefore = priorMeasurements
      .map((m) => parseLeadingNum(m.weight))
      .whereType<double>()
      .any((w) => (w - goalWeight).abs() <= 0.5);
  if (alreadyThereBefore) return;
  try {
    await SupabaseService.sendEmail(
      to: toEmail,
      subject: "You reached your goal weight!",
      text: "Hi $toName,\n\nCongratulations — your latest measurement shows you've reached your goal weight. Amazing work!\n\n— ONE Fitness",
    );
  } catch (_) {}
}
