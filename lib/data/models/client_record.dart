import "challenge.dart";
import "comm_message.dart";
import "habit_def.dart";
import "habit_log_entry.dart";
import "intake_schema.dart";
import "measurement.dart";
import "nutrition_plan.dart";
import "program_day.dart";
import "progress_photo.dart";
import "saved_program.dart";
import "session_feedback.dart";
import "signature.dart";
import "trainer_note.dart";
import "workout_log.dart";

/// Mirrors the per-client record loaded via sb.loadClientRecord (App.jsx
/// `clientRecords`) — trimmed to what the dashboard / calendar need.
class ClientRecord {
  const ClientRecord({
    required this.id,
    this.loggedDates = const [],
    this.habits = const [],
    this.customHabits = const [],
    this.habitLogByDate = const {},
    this.tourSeenDashboard = false,
    this.tourSeenDrawer = false,
    this.onboardingComplete = true,
    this.comms = const [],
    this.savedPrograms = const [],
    this.programDays = const [],
    this.workoutLogs = const [],
    this.nutrition,
    this.signatures = const [],
    this.challengeProgress = const {},
    this.intake = const {},
    this.measurements = const [],
    this.photos = const [],
    this.trainerNotes = const [],
    this.sessionFeedback = const [],
    this.savedNutritionPrograms = const [],
    this.challengeBadges = const [],
    this.adoptedSignatureImage,
    this.adoptedInitialsImage,
    this.photoVideoOptOut = false,
    this.guardianName,
  });

  final String id;

  /// Union of client.logs + client.workoutLogs dates (ISO yyyy-MM-dd) — a day
  /// counts as "logged" if either the old free-text log or the new structured
  /// workout log has an entry for it.
  final List<String> loggedDates;

  /// Habit ids a coach has configured for this client (empty = no habit
  /// tracker card on the dashboard).
  final List<String> habits;

  /// Client-specific custom habits a coach has added (always active, no
  /// separate enable/disable step — unlike the shared default habit set).
  final List<HabitDef> customHabits;

  /// date -> that day's habit log (checked habits + energy/motivation).
  final Map<String, HabitLogEntry> habitLogByDate;

  final bool tourSeenDashboard;
  final bool tourSeenDrawer;

  /// Stands in for the real onboarding/intake status (personalized intake,
  /// nutrition intake, physical assessment booked) until that feature is
  /// built — true hides the "Complete your onboarding" banner.
  final bool onboardingComplete;

  /// Newest-first communication log (Comms.jsx `client.comms`).
  final List<CommMessage> comms;

  /// Named/assigned workout program snapshots (client.savedPrograms) — the
  /// history shown in the Programs sub-tab, distinct from [programDays]
  /// below (the live split currently being built/edited).
  final List<SavedProgram> savedPrograms;

  /// The client's live, currently-being-built workout split
  /// (client.programDays) — what the Training sub-tab's builder actually
  /// edits, auto-saved on every change. "Save program" snapshots this into
  /// [savedPrograms] (+ the shared library) under a name and clears it.
  final List<ProgramDay> programDays;

  /// Completed logged sessions (client.workoutLogs) — drives "Last Wt"
  /// reference values and the per-cycle completed-day checkmarks.
  final List<WorkoutLogEntry> workoutLogs;

  /// Legacy flat nutrition plan (client.nutrition), read by
  /// NutritionScreenReadOnly.jsx — null means no plan assigned yet.
  final NutritionPlan? nutrition;

  /// Signed waivers/contracts (client.signatures).
  final List<SignedDocument> signatures;

  /// challengeId -> manually logged progress entries (client.challengeProgress).
  final Map<String, List<ChallengeProgressEntry>> challengeProgress;

  /// assessmentKey -> submitted intake record (client.intake).
  final Map<String, IntakeRecord> intake;

  /// Body measurement log entries (client.measurements).
  final List<Measurement> measurements;

  /// Uploaded progress photos (client.photos).
  final List<ProgressPhoto> photos;

  /// Coach-authored flag/notes on this client (client.trainerNotes).
  final List<TrainerNote> trainerNotes;

  /// Coach-logged post-session feedback (client.sessionFeedback).
  final List<SessionFeedbackEntry> sessionFeedback;

  /// AI-drafted or coach-saved nutrition target sets awaiting review or
  /// already applied (client.savedNutritionPrograms) — see NutritionBuilder.
  final List<NutritionProgramEntry> savedNutritionPrograms;

  /// Challenge badges awarded to this client (client.challengeBadges) — a
  /// winner badge and/or a "complete-{challengeId}" participation badge per
  /// finished challenge, written by a coach's "Award badges" action.
  final List<ChallengeBadge> challengeBadges;

  /// "Adopt a signature" (Variable & Signature Capture spec §3) — the
  /// client's saved initials/signature image (data URL), drawn or typed
  /// once and reused across every document's capture points; each new
  /// document still requires a fresh confirming tap/timestamp, never
  /// silently auto-applied.
  final String? adoptedSignatureImage;
  final String? adoptedInitialsImage;

  /// Snapshotted at signing time onto each [SignedDocument] too (so a later
  /// policy change doesn't retroactively alter what a past signature meant)
  /// — this is just the client's current/latest choice.
  final bool photoVideoOptOut;

  /// Last-used parent/legal guardian name (minor-signer flow) — reusable
  /// across documents, same as the adopted signature.
  final String? guardianName;

  bool loggedOn(String isoDate) => loggedDates.contains(isoDate);

  ClientRecord copyWith({
    List<CommMessage>? comms,
    List<SavedProgram>? savedPrograms,
    List<ProgramDay>? programDays,
    List<WorkoutLogEntry>? workoutLogs,
    List<String>? loggedDates,
    List<String>? habits,
    List<HabitDef>? customHabits,
    Map<String, HabitLogEntry>? habitLogByDate,
    NutritionPlan? nutrition,
    bool clearNutrition = false,
    List<SignedDocument>? signatures,
    Map<String, List<ChallengeProgressEntry>>? challengeProgress,
    Map<String, IntakeRecord>? intake,
    List<Measurement>? measurements,
    List<ProgressPhoto>? photos,
    List<TrainerNote>? trainerNotes,
    List<SessionFeedbackEntry>? sessionFeedback,
    List<NutritionProgramEntry>? savedNutritionPrograms,
    List<ChallengeBadge>? challengeBadges,
    bool? tourSeenDashboard,
    bool? tourSeenDrawer,
    String? adoptedSignatureImage,
    String? adoptedInitialsImage,
    bool? photoVideoOptOut,
    String? guardianName,
  }) =>
      ClientRecord(
        id: id,
        loggedDates: loggedDates ?? this.loggedDates,
        habits: habits ?? this.habits,
        customHabits: customHabits ?? this.customHabits,
        habitLogByDate: habitLogByDate ?? this.habitLogByDate,
        tourSeenDashboard: tourSeenDashboard ?? this.tourSeenDashboard,
        tourSeenDrawer: tourSeenDrawer ?? this.tourSeenDrawer,
        onboardingComplete: onboardingComplete,
        comms: comms ?? this.comms,
        savedPrograms: savedPrograms ?? this.savedPrograms,
        programDays: programDays ?? this.programDays,
        workoutLogs: workoutLogs ?? this.workoutLogs,
        nutrition: clearNutrition ? null : (nutrition ?? this.nutrition),
        signatures: signatures ?? this.signatures,
        challengeProgress: challengeProgress ?? this.challengeProgress,
        intake: intake ?? this.intake,
        measurements: measurements ?? this.measurements,
        photos: photos ?? this.photos,
        trainerNotes: trainerNotes ?? this.trainerNotes,
        sessionFeedback: sessionFeedback ?? this.sessionFeedback,
        savedNutritionPrograms: savedNutritionPrograms ?? this.savedNutritionPrograms,
        challengeBadges: challengeBadges ?? this.challengeBadges,
        adoptedSignatureImage: adoptedSignatureImage ?? this.adoptedSignatureImage,
        adoptedInitialsImage: adoptedInitialsImage ?? this.adoptedInitialsImage,
        photoVideoOptOut: photoVideoOptOut ?? this.photoVideoOptOut,
        guardianName: guardianName ?? this.guardianName,
      );
}
