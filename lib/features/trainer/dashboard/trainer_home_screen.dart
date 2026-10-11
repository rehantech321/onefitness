import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/attendee_utils.dart";
import "../../../core/utils/attention_utils.dart";
import "../../../core/utils/booking_utils.dart";
import "../../../core/utils/client_status_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/utils/notification_triggers.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/live_session.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/workout_log.dart";
import "../../../data/providers/beep_providers.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";
import "../../client/booking/date_strip.dart";
import "../../shared/session_logger_view.dart";
import "../beep/coach_beep_alerts.dart";
import "../../../core/widgets/session_timer.dart";
import "../shell/trainer_shell_state.dart";

/// Mirrors TrainerHome.jsx — the coach/owner dashboard: greeting header,
/// owner-only stat row, "Needs Attention" list, a collapsible day calendar,
/// and that day's sessions grouped by time with inline attendance actions.
/// "Start Session" runs the same SessionLoggerView a client uses to log
/// their own session (see workout_tab.dart) — picking a client first if
/// the slot has more than one, then logging on their behalf
/// (`loggedBy: "coach"`). Per-client trainer notes (FlagAlert) aren't
/// built yet.
class TrainerHomeScreen extends ConsumerStatefulWidget {
  const TrainerHomeScreen({super.key});

  @override
  ConsumerState<TrainerHomeScreen> createState() => _TrainerHomeScreenState();
}

class _TrainerHomeScreenState extends ConsumerState<TrainerHomeScreen> {
  late String _viewDate = isoToday();
  bool _calendarOpen = false;
  int? _sessionSlot;
  String? _sessionClientId;

  /// The row in `session_runs` this screen started, if any. Its existence
  /// is what switches Beep Your Coach on for the clients booked into this
  /// slot — before this, "Start Session" never left the device.
  LiveSession? _run;
  bool _startingRun = false;

  /// Starting a session the coach is already running returns the existing
  /// row rather than a second one, so backing out of this screen and
  /// coming back doesn't split the beeps in two.
  Future<void> _beginRun(int slot, List<Booking> group) async {
    if (_startingRun) return;
    setState(() {
      _startingRun = true;
      _sessionSlot = slot;
      _sessionClientId = null;
    });
    try {
      final trainerId = ref.read(trainerAuthProvider);
      final first = group.isEmpty ? null : group.first;
      final run = await SupabaseService.startSessionRun(
        trainerId: trainerId ?? "",
        date: _viewDate,
        slotMin: slot,
        sessionType: first?.sessionType ?? "semi-private",
        durationMin: first?.durationMin ?? 60,
        location: first?.locationName,
      );
      if (!mounted) return;
      setState(() => _run = run);
      if (run != null) ref.read(liveSessionsProvider.notifier).apply(run);
    } catch (e) {
      // The coach can still log the session; only Beep Your Coach is lost,
      // so this says what was lost rather than blocking the session.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session started, but Beep Your Coach couldn't be switched on.")),
      );
    } finally {
      if (mounted) setState(() => _startingRun = false);
    }
  }

  /// The session ran its full length. Closes it off without asking — the
  /// hour is simply up, and the coach has not been presented with a
  /// decision to make.
  ///
  /// The screen stays open: the coach may still be saving the last sets,
  /// and yanking them out of the logging grid at the stroke of the hour
  /// would lose work. Only the clock and Beep Your Coach stop.
  Future<void> _autoEndRun() async {
    await _endRun();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Session time is up — your clients can no longer beep you.")),
    );
  }

  /// Ending the session is what turns Beep Your Coach off for everyone in
  /// it, so it happens whenever the coach leaves this screen.
  Future<void> _endRun() async {
    final run = _run;
    _run = null;
    if (run == null) return;
    try {
      await SupabaseService.endSessionRun(run.id);
      ref.read(liveSessionsProvider.notifier).remove(run.id);
    } catch (_) {
      // Left live server-side; the next start reuses it rather than
      // stacking a second run.
    }
  }
  bool _noShowSweepDone = false;

  @override
  void initState() {
    super.initState();
    _sweepStaleAttendance();
  }

  /// Opportunistic, one-shot per screen visit — same "no cron, safe to call
  /// speculatively" shape as checkGymCitizenExpiry. A past booking nobody
  /// ever marked attendance for is auto-resolved to "no-show" so it stops
  /// sitting there for the coach to react to; still changeable after.
  Future<void> _sweepStaleAttendance() async {
    if (_noShowSweepDone) return;
    _noShowSweepDone = true;
    final trainerAuth = ref.read(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final today = isoToday();
    final stale = ref
        .read(allBookingsProvider)
        .where(
          (b) =>
              b.attendanceStatus == null &&
              b.date.compareTo(today) < 0 &&
              (isOwner || b.trainerId == trainerAuth),
        )
        .toList();
    if (stale.isEmpty) return;
    try {
      await SupabaseService.markBookingsNoShow(stale.map((b) => b.id).toList());
      if (!mounted) return;
      final notifier = ref.read(allBookingsProvider.notifier);
      for (final b in stale) {
        notifier.updateAttendance(b.id, "no-show");
      }
    } catch (_) {}
  }

  Future<void> _saveCoachSession(String clientId, WorkoutLogEntry entry) async {
    final record = ref.read(trainerClientRecordsProvider)[clientId];
    final updatedLogs = [...?record?.workoutLogs, entry];
    await SupabaseService.updateClientWorkoutLogs(clientId, updatedLogs);
    ref
        .read(trainerClientRecordsProvider.notifier)
        .update(clientId, (r) => r.copyWith(workoutLogs: updatedLogs));
  }

  @override
  Widget build(BuildContext context) {
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final roster = ref.watch(trainerRosterProvider);
    final trainers = ref.watch(trainersProvider);
    final bookings = ref.watch(allBookingsProvider);
    final liveRuns = ref.watch(liveSessionsProvider);
    final clientRecords = ref.watch(trainerClientRecordsProvider);
    final todayCharges = ref
        .watch(chargesProvider)
        .where((c) => c.date == isoToday())
        .toList();
    final settings = ref.watch(platformSettingsProvider);

    final me = trainers.where((t) => t.id == trainerAuth);
    final myName = isOwner
        ? "Owner"
        : (me.isNotEmpty ? me.first.name : "Coach");

    // Dashboard/schedule scope to just this coach's own clients; owner sees everyone.
    final myRoster = isOwner
        ? roster
        : roster.where((c) => c.primaryTrainerId == trainerAuth).toList();

    final needsAttention = [
      ...computeNeedsAttention(myRoster, clientRecords),
      ...computeUnloggedAttendance(myRoster, bookings),
      ...computeCoachCodeAlerts(myRoster),
    ];
    final grouped = <String, List<AttentionItem>>{};
    for (final n in needsAttention) {
      grouped.putIfAbsent(n.label, () => []).add(n);
    }

    final dayBookings =
        bookings
            .where(
              (b) =>
                  b.date == _viewDate &&
                  (isOwner || b.trainerId == trainerAuth),
            )
            .toList()
          ..sort((a, b) => a.slot.compareTo(b.slot));
    final byTime = <int, List<Booking>>{};
    for (final b in dayBookings) {
      byTime.putIfAbsent(b.slot, () => []).add(b);
    }
    final slots = byTime.keys.toList()..sort();

    if (_sessionSlot != null) {
      final slot = _sessionSlot!;
      final group = byTime[slot] ?? const <Booking>[];
      final loggable = group.where((b) {
        final attendee = resolveAttendee(b.clientId, roster, trainers);
        return !attendee.isStaff && roster.any((c) => c.id == b.clientId);
      }).toList();
      final activeClientId =
          _sessionClientId ??
          (loggable.length == 1 ? loggable.first.clientId : null);

      // Leaving the screen is not ending the session. A coach steps out to
      // check the schedule or another client constantly; ending the run on
      // the way out meant the clock restarted from zero every time, the
      // dashboard offered "Start Session" again as though nothing had
      // happened, and Beep Your Coach switched off under the clients still
      // training. Eleven separate runs were recorded for one slot that way.
      void closeSession() => setState(() {
        _sessionSlot = null;
        _sessionClientId = null;
      });

      // Ending it is its own, deliberate act — and it asks first, because
      // it takes Beep Your Coach away from everyone in the session.
      Future<void> endSession() async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.card,
            title: const Text("End this session?", style: TextStyle(fontSize: 15)),
            content: const Text(
              "The clock stops and your clients can no longer beep you. You can start it again if you need to.",
              style: TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Keep it running"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("End session", style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await _endRun();
        if (mounted) closeSession();
      }

      Widget sessionContent;
      if (loggable.isEmpty) {
        sessionContent = Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BackBar(onBack: closeSession, title: "Start Session"),
              const SizedBox(height: 10),
              const HintBox(text: "No loggable clients in this session."),
            ],
          ),
        );
      } else if (activeClientId == null) {
        // More than one client in this slot — pick who to log for first.
        sessionContent = SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BackBar(onBack: closeSession, title: "Session"),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    fmtSlot(slot),
                    style: const TextStyle(fontSize: 12, color: AppColors.mute),
                  ),
                  if (_run != null) ...[
                    const SizedBox(width: 10),
                    SessionTimer(run: _run!, onRanOut: _autoEndRun),
                    const Spacer(),
                    TextButton(
                      onPressed: endSession,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        minimumSize: const Size(44, 36),
                      ),
                      child: const Text("End session",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              const SectionLabel("Choose a client"),
              ...loggable.map((b) {
                final attendee = resolveAttendee(b.clientId, roster, trainers);
                return AppCard(
                  onTap: () => setState(() => _sessionClientId = b.clientId),
                  child: Row(
                    children: [
                      Avatar(name: attendee.name, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          attendee.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(
                        LucideIcons.chevronRight,
                        size: 16,
                        color: AppColors.mute,
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      } else {
        final record = clientRecords[activeClientId];
        final attendee = resolveAttendee(activeClientId, roster, trainers);
        sessionContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Row(
                children: [
                  Expanded(
                    child: BackBar(
                      onBack: closeSession,
                      title: attendee.name,
                    ),
                  ),
                  // How long the session has been running, counted from when
                  // the coach actually started it rather than from when this
                  // screen was built — so moving between clients in a
                  // semi-private session doesn't look like a restart.
                  if (_run != null) ...[
                    SessionTimer(run: _run!, compact: true, onRanOut: _autoEndRun),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: endSession,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(44, 36),
                      ),
                      child: const Text("End",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ],
              ),
            ),
            // Semi-private: flip between everyone in the slot without
            // leaving the session. Previously the coach picked one client
            // once and had to back out to reach another, which is the wrong
            // shape for a session where all four are training at the same
            // time in front of them.
            if (loggable.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: SizedBox(
                  height: 62,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: loggable.length,
                    separatorBuilder: (context, i) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final b = loggable[i];
                      final person = resolveAttendee(b.clientId, roster, trainers);
                      final active = b.clientId == activeClientId;
                      return InkWell(
                        onTap: active
                            ? null
                            : () => setState(() => _sessionClientId = b.clientId),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 76,
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          decoration: BoxDecoration(
                            color: active ? AppColors.gold : AppColors.card,
                            border: Border.all(color: active ? AppColors.gold : AppColors.line),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Avatar(name: person.name, size: 26, active: active),
                              const SizedBox(height: 3),
                              Text(
                                person.name.split(" ").first,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                                  color: active ? AppColors.onGold : AppColors.mute,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            Expanded(
              child: record == null
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: HintBox(
                        text: "This client's record hasn't loaded yet.",
                      ),
                    )
                  : SessionLoggerView(
                      // Keyed by client so flipping between them builds a
                      // fresh logger. Without this Flutter reuses the same
                      // State, and the in-progress sets typed for one client
                      // would follow the coach onto the next one — silently
                      // logging the wrong person's workout.
                      key: ValueKey(activeClientId),
                      client: record,
                      loggedBy: "coach",
                      emptyProgramText:
                          "This client doesn't have an active workout program yet.",
                      onSave: (entry) =>
                          _saveCoachSession(activeClientId, entry),
                    ),
            ),
          ],
        );
      }

      // Beeps are overlaid on the session screen rather than pushed as a
      // route: the coach is mid-set with someone else, and an alert that
      // took over the screen would be worse than the problem it reports.
      return CoachBeepAlerts(
        trainerId: trainerAuth ?? "",
        child: LocalBackScope(
          isOpen: true,
          onBack: closeSession,
          child: activeClientId != null && loggable.length > 1
              ? LocalBackScope(
                  isOpen: true,
                  onBack: () => setState(() => _sessionClientId = null),
                  child: sessionContent,
                )
              : sessionContent,
        ),
      );
    }

    void goMode(String mode) => ref.read(trainerModeProvider.notifier).go(mode);
    void openClient(String clientId) => ref.read(trainerModeProvider.notifier).openClient(clientId);

    // Staggers the greeting/stats header's entrance by 45ms per block,
    // played once when the Dashboard first mounts.
    var stagger = 0;
    Widget stag(Widget child) {
      final delay = Duration(milliseconds: 45 * stagger);
      stagger++;
      return FadeSlideIn(delay: delay, child: child);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          stag(Row(
            children: [
              Avatar(name: isOwner ? "Owner" : myName, size: 48, active: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Hi, ${isOwner ? "Owner" : myName.split(" ").first}",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      dayLabel(isoToday()),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.mute,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () {
                  SupabaseService.signOut();
                  ref.read(trainerAuthProvider.notifier).signOut();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.mute,
                  side: const BorderSide(color: AppColors.line),
                ),
                child: const Text("Sign out", style: TextStyle(fontSize: 12)),
              ),
            ],
          )),
          const SizedBox(height: 18),
          if (isOwner)
            stag(Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  _StatBox(
                    label: "Clients",
                    value: "${myRoster.length}",
                    onTap: () => goMode("clients"),
                  ),
                  const SizedBox(width: 10),
                  _StatBox(
                    label: "Trainers",
                    value: "${trainers.length}",
                    onTap: () => goMode("staff"),
                  ),
                  const SizedBox(width: 10),
                  _StatBox(
                    label: "Today",
                    value:
                        "${bookings.where((b) => b.date == isoToday() && (isOwner || b.trainerId == trainerAuth)).length}",
                    onTap: () => goMode("schedule"),
                  ),
                ],
              ),
            )),
          stag(const SectionLabel("Needs Attention")),
          if (needsAttention.isEmpty)
            const HintBox(text: "Nothing needs your attention right now ✓", bordered: false)
          else
            ...grouped.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${entry.key.toUpperCase()} (${entry.value.length})",
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFD68A4F),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...entry.value.map((n) {
                      final matches = roster.where((c) => c.id == n.clientId);
                      if (matches.isEmpty) return const SizedBox.shrink();
                      final c = matches.first;
                      return AppCard(
                        onTap: () {
                          if (n.bookingId != null) {
                            setState(() {
                              _viewDate = n.date!;
                              _calendarOpen = true;
                            });
                          } else {
                            if (n.key == "coach-code-used") {
                              ref
                                  .read(trainerRosterProvider.notifier)
                                  .update(
                                    c.id,
                                    (info) =>
                                        info.copyWith(coachCodeAlertSeen: true),
                                  );
                              SupabaseService.markCoachCodeAlertSeen(
                                c.id,
                              ).catchError((Object _) {});
                            }
                            openClient(c.id);
                          }
                        },
                        child: Row(
                          children: [
                            Avatar(name: c.name, size: 30),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (n.bookingId != null)
                                    Text(
                                      "${dayLabel(n.date!)}${n.date == isoToday() ? ' · Today' : ''} · ${fmtSlot(n.slot!)}",
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.mute,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(
                              LucideIcons.chevronRight,
                              size: 15,
                              color: AppColors.mute,
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          InkWell(
            onTap: () => setState(() => _calendarOpen = !_calendarOpen),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
              margin: const EdgeInsets.only(top: 4),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.line),
                  bottom: BorderSide(color: AppColors.line),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        dayLabel(_viewDate),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_viewDate == isoToday())
                        const Text(
                          " · Today",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.gold,
                          ),
                        ),
                    ],
                  ),
                  Icon(
                    _calendarOpen
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: 16,
                    color: AppColors.mute,
                  ),
                ],
              ),
            ),
          ),
          if (_calendarOpen)
            DateStrip(
              date: _viewDate,
              onSelect: (d) => setState(() => _viewDate = d),
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SectionLabel(isOwner ? "Sessions" : "Your sessions"),
              TextButton(
                onPressed: () => goMode("schedule"),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.gold,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                ),
                child: const Text(
                  "Full schedule →",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (slots.isEmpty)
            const HintBox(text: "No sessions booked this day.", bordered: false)
          else
            ...slots.map((slot) {
              // A past day's sessions are for review only — logging a set
              // against a session that already happened (or never did)
              // isn't a real "start", so the button is disabled instead of
              // hidden (still visible for context, just not actionable).
              final isPastDate = _viewDate.compareTo(isoToday()) < 0;
              final group = byTime[slot]!;

              // A session can't be started before it's due. The 9pm slot was
              // startable at 9:52 in the morning, which is how a coach ends
              // up logging sets against a session that hasn't happened.
              //
              // The one exception is a client who turned up early and
              // checked themselves in: their arrival is exactly the thing
              // that makes starting early legitimate, so the coach can join
              // them rather than being locked out of a session already
              // happening on the gym floor.
              final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;
              final isFutureDate = _viewDate.compareTo(isoToday()) > 0;
              // Only the client's own "I'm here — start my session" counts.
              // attendance_status is no use here: the coach's own Check In
              // button writes exactly the same value, so ticking someone
              // present at 6pm unlocked starting a 9pm session.
              final someoneArrivedEarly = group.any((b) => b.clientStartedEarly);
              final tooEarly = isFutureDate ||
                  (_viewDate == isoToday() && nowMin < slot && !someoneArrivedEarly);

              // A session this coach already has running — including one
              // left open on another device. Starting it again reuses the
              // same run rather than opening a second, so this is a rejoin.
              final alreadyLive = liveRuns.any(
                (r) => r.date == _viewDate && r.slotMin == slot && r.trainerId == trainerAuth,
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            fmtSlot(slot),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.gold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: (isPastDate || tooEarly)
                              ? null
                              : () => _beginRun(slot, group),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            disabledBackgroundColor: AppColors.gold.withValues(alpha: 0.35),
                            foregroundColor: AppColors.onGold,
                            disabledForegroundColor: AppColors.onGold.withValues(alpha: 0.6),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                          child: Text(
                            alreadyLive ? "● Live — rejoin" : "▶ Start Session",
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // A disabled button with no reason beside it reads as a
                    // broken button, so it says what it's waiting for.
                    if (tooEarly)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          isFutureDate
                              ? "Starts on ${dayLabel(_viewDate)}"
                              : "Can be started at ${fmtSlot(slot)}, or as soon as someone checks in",
                          style: const TextStyle(fontSize: 10.5, color: AppColors.mute),
                        ),
                      ),
                    const SizedBox(height: 8),
                    ...group.map((b) {
                      final attendee = resolveAttendee(
                        b.clientId,
                        roster,
                        trainers,
                      );
                      final rosterMatches = attendee.isStaff
                          ? const <ClientInfo>[]
                          : roster.where((c) => c.id == b.clientId).toList();
                      final rosterClient = rosterMatches.isNotEmpty
                          ? rosterMatches.first
                          : null;
                      final clickable =
                          !attendee.isStaff && rosterClient != null;
                      final rec = clickable ? clientRecords[b.clientId] : null;
                      final status = rec != null
                          ? computeClientStatus(rec, bookings: bookings.where((x) => x.clientId == b.clientId).toList())
                          : null;
                      final t = trainers.where((x) => x.id == b.trainerId);
                      return AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: clickable
                                  ? () => openClient(rosterClient.id)
                                  : null,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Avatar(name: attendee.name, size: 32),
                                        if (status != null)
                                          Positioned(
                                            bottom: -1,
                                            right: -1,
                                            child: StatusDot(
                                              status: status,
                                              size: 9,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              attendee.name,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (attendee.isStaff) ...[
                                              const SizedBox(width: 6),
                                              const Tag(text: "Staff"),
                                            ],
                                            if (b.attendanceStatus != null) ...[
                                              const SizedBox(width: 6),
                                              _AttendanceBadge(
                                                status: b.attendanceStatus!,
                                              ),
                                            ],
                                          ],
                                        ),
                                        Text(
                                          [
                                            disciplineLabel(b.discipline),
                                            if (isOwner && t.isNotEmpty)
                                              t.first.name,
                                          ].join(" · "),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.mute,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (clickable)
                                    const Icon(
                                      LucideIcons.chevronRight,
                                      size: 15,
                                      color: AppColors.mute,
                                    ),
                                ],
                              ),
                            ),
                            if (clickable) ...[
                              const SizedBox(height: 9),
                              Wrap(
                                spacing: 5,
                                runSpacing: 5,
                                children: kAttendanceOptions.map((opt) {
                                  final active = b.attendanceStatus == opt.key;
                                  return InkWell(
                                    onTap: () {
                                      final prev = b.attendanceStatus;
                                      final next = active ? null : opt.key;
                                      ref
                                          .read(allBookingsProvider.notifier)
                                          .updateAttendance(b.id, next);
                                      SupabaseService.updateBookingAttendance(
                                        b.id,
                                        next,
                                      ).catchError((Object _) {
                                        ref
                                            .read(allBookingsProvider.notifier)
                                            .updateAttendance(b.id, prev);
                                      });
                                      if (next == "checked-in" &&
                                          next != prev) {
                                        final total = ref
                                            .read(allBookingsProvider)
                                            .where((x) =>
                                                x.clientId == b.clientId &&
                                                x.attendanceStatus ==
                                                    "checked-in")
                                            .length;
                                        notifySessionMilestoneIfCrossed(
                                          toEmail: rosterClient.email ?? "",
                                          toName: rosterClient.name,
                                          totalCheckedIn: total,
                                          profileId: rosterClient.id,
                                        );
                                      }
                                      // Late Cancel / No-Show carry an owner-set fee, fired
                                      // once on the transition into that status — not on
                                      // every toggle, and not on transitions between two
                                      // non-feeable statuses (Attendance & Cancellation
                                      // Charging Policy, July 2026).
                                      if (next != null && next != prev) {
                                        final charge = attendanceChargeFor(
                                          b,
                                          next,
                                          clientName: attendee.name,
                                          trainerName: t.isNotEmpty
                                              ? t.first.name
                                              : null,
                                          lateCancellationFeeCents:
                                              settings.lateCancellationFeeCents,
                                          noShowFeeCents:
                                              settings.noShowFeeCents,
                                        );
                                        if (charge != null) {
                                          SupabaseService.insertCharge(charge)
                                              .then(
                                                (saved) => ref
                                                    .read(
                                                      chargesProvider.notifier,
                                                    )
                                                    .add(saved),
                                              )
                                              .catchError((Object e) {
                                                // ignore: avoid_print
                                                print(
                                                  "[attendance charge] failed to save: $e",
                                                );
                                              });
                                        }
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(7),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                        horizontal: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: active
                                            ? opt.color.withValues(alpha: 0.13)
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: active
                                              ? opt.color
                                              : AppColors.line,
                                        ),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: Text(
                                        opt.label,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: active
                                              ? opt.color
                                              : AppColors.mute,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),
          // Collecting charges is the owner's job only — coaches don't see it.
          if (isOwner && todayCharges.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: () => goMode("schedule"),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    border: Border.all(color: const Color(0xFFA8632F)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.circleSlash,
                        size: 18,
                        color: Color(0xFFD68A4F),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "${todayCharges.length} charge${todayCharges.length != 1 ? "s" : ""} to collect today",
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.txt,
                          ),
                        ),
                      ),
                      const Icon(
                        LucideIcons.chevronRight,
                        size: 16,
                        color: AppColors.mute,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.gold,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.mute,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _attendanceLabels = {
  "checked-in": "Check In",
  "early-cancel": "Early Cancel",
  "late-cancel": "Late Cancel",
  "no-show": "No Show",
};

class _AttendanceBadge extends StatelessWidget {
  const _AttendanceBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final opt = kAttendanceOptions.firstWhere((o) => o.key == status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: opt.color),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        _attendanceLabels[status] ?? status,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: opt.color,
        ),
      ),
    );
  }
}
