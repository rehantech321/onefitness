import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/booking_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/utils/membership_utils.dart";
import "../../../core/utils/merge_token_utils.dart";
import "../../../core/utils/notification_triggers.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/blocked_time.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/models/trainer.dart";
import "../../../data/models/waitlist_entry.dart";
import "../../../data/models/waiver_doc.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";
import "../drawer_screens/waiver_signing_screen.dart";
import "booking_cancel_screen.dart";
import "booking_picking_screen.dart";
import "date_strip.dart";
import "upcoming_session_card.dart";
import "waitlist_offer_banner.dart";

/// Mirrors BookSession.jsx, trimmed to the everyday linear flow: browse
/// upcoming sessions, pick a session type -> discipline -> time slot,
/// confirm, or cancel/reschedule an existing booking. Recurring multi-day
/// booking and the waitlist are not built yet — each is its own sizeable
/// feature.
class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key, required this.onGoMemberships, required this.onGoSignatures, this.initialDate, this.initialReschedule});

  final VoidCallback onGoMemberships;
  final VoidCallback onGoSignatures;

  /// Set when arriving from a dashboard calendar tap on an empty future
  /// date (see client_shell.dart's pickCalendarDate) — jumps the date strip
  /// straight there instead of starting on today.
  final String? initialDate;

  /// Set when arriving from a "Reschedule" tap (DayDetailScreen or the
  /// upcoming-sessions list) — pre-fills the type/discipline/date from the
  /// booking being moved, same as tapping Reschedule from within this screen.
  final Booking? initialReschedule;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  late String _date = widget.initialReschedule?.date ?? widget.initialDate ?? isoToday();
  String? _chosenType;
  String? _chosenDisc;
  PendingPick? _picking;
  Booking? _cancelTarget;
  Booking? _rescheduling;
  dynamic _denied; // BookingCheck?

  /// Which held plan the pending pick will be charged to — decided by
  /// canBookOffering when the slot was tapped, written onto the booking.
  String? _pickPlanId;
  bool _showAllUpcoming = false;
  bool _busy = false;
  String? _bookingError;
  final Set<String> _waitlistBusyKeys = {};

  /// The waiver being signed inside the booking flow, and what to pick back
  /// up once it's signed (the slot the client tapped, or their waitlist join).
  WaiverDoc? _signingDoc;
  VoidCallback? _afterSigning;

  List<WaiverDoc> _outstandingDocs() {
    final info = ref.read(clientInfoProvider);
    return outstandingWaivers(
      allDocs: ref.read(waiversProvider),
      signatures: ref.read(clientRecordProvider).signatures,
      clientPlanId: info.membershipPlanId,
    );
  }

  /// Shows the "Signature needed" screen; its button opens the waiver right
  /// here, and [resume] runs once everything is signed.
  void _needsSignature(BookingCheck check, VoidCallback resume) => setState(() {
        _denied = check;
        _afterSigning = resume;
      });

  void _startSigning() {
    final docs = _outstandingDocs();
    if (docs.isEmpty) {
      widget.onGoSignatures();
      return;
    }
    setState(() {
      _denied = null;
      _signingDoc = docs.first;
    });
  }

  /// After a signature: sign the next outstanding document if there is one,
  /// otherwise go straight back to the session the client was booking.
  void _signingFinished() {
    final next = _outstandingDocs();
    if (next.isNotEmpty) {
      setState(() => _signingDoc = next.first);
      return;
    }
    final resume = _afterSigning;
    setState(() {
      _signingDoc = null;
      _afterSigning = null;
      _bookingError = null;
    });
    resume?.call();
  }

  void _cancelSigning() => setState(() {
        _signingDoc = null;
        _afterSigning = null;
      });

  String _waitlistKey(String trainerId, String date, int slot) => "$trainerId|$date|$slot";

  @override
  void initState() {
    super.initState();
    final reschedule = widget.initialReschedule;
    if (reschedule != null) {
      _rescheduling = reschedule;
      _chosenType = reschedule.sessionType;
      _chosenDisc = reschedule.discipline;
    }
  }

  void _showError(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _pickType(String? t) => setState(() {
        _chosenType = t;
        _chosenDisc = null;
      });

  void _startReschedule(Booking b) => setState(() {
        _rescheduling = b;
        _chosenType = b.sessionType;
        _chosenDisc = b.discipline;
        _date = b.date;
        _picking = null;
      });

  Future<void> _confirmCancel() async {
    if (_busy) return;
    final b = _cancelTarget!;
    setState(() => _busy = true);
    try {
      await SupabaseService.deleteBooking(b.id);
      ref.read(clientBookingsProvider.notifier).cancelBooking(b.id);
      // The slot list reads the gym-wide list, so it has to drop the booking
      // too — otherwise the cancelled session keeps showing as "Booked".
      ref.read(allBookingsProvider.notifier).cancelBooking(b.id);
      // A client cancelling their own booking can only ever be "free" or
      // "late" — a no-show is by definition something the client never
      // reported, so self-cancel never produces one (see cancelWindow).
      final settings = ref.read(platformSettingsProvider);
      if (cancelWindow(b, lateCancellationHours: settings.lateCancellationHours) != "free") {
        final info = ref.read(clientInfoProvider);
        final trainer = ref.read(trainersProvider).where((t) => t.id == b.trainerId);
        final charge = attendanceChargeFor(
          b,
          "late-cancel",
          clientName: info.name,
          trainerName: trainer.isNotEmpty ? trainer.first.name : null,
          lateCancellationFeeCents: settings.lateCancellationFeeCents,
          noShowFeeCents: settings.noShowFeeCents,
        );
        if (charge != null) {
          SupabaseService.insertCharge(charge).then((saved) => ref.read(chargesProvider.notifier).add(saved)).catchError((Object e) {
            // ignore: avoid_print
            print("[cancel charge] failed to save: $e");
          });
        }
      }
      setState(() {
        _busy = false;
        _cancelTarget = null;
      });
    } catch (e) {
      setState(() => _busy = false);
      _showError("Couldn't cancel that session — check your connection and try again.");
    }
  }

  void _onSlotTap(Trainer t, String sessionType, String discipline, int slot, bool mine, bool isFull) {
    if (mine || isFull) return;
    final info = ref.read(clientInfoProvider);
    final bookings = ref.read(clientBookingsProvider);
    String? chargePlanId;
    if (_rescheduling == null) {
      final held = heldAccessPlans(info, ref.read(membershipPlansProvider));
      final settings = ref.read(platformSettingsProvider);
      final waiverCheck = waiverGateCheck(info: info, record: ref.read(clientRecordProvider), waiverDocs: ref.read(waiversProvider));
      if (waiverCheck != null) {
        _needsSignature(waiverCheck, () => _onSlotTap(t, sessionType, discipline, slot, mine, isFull));
        return;
      }
      final check = canBookOffering(
        info,
        sessionType,
        bookings,
        _date,
        slot,
        held,
        minBookingLeadHours: settings.minBookingLeadHours,
        maxBookingHorizonDays: settings.maxBookingHorizonDays,
      );
      if (!check.ok) {
        setState(() => _denied = check);
        return;
      }
      chargePlanId = check.planId;
    } else {
      // A reschedule moves an existing booking; it keeps whichever plan the
      // original was charged to.
      chargePlanId = _rescheduling!.planId;
    }
    // Where this session runs: the one the owner created it at (Create
    // Session → Location), else the coach's own location.
    final offering = trainerOfferingsOn(t, _date)
        .where((o) => o.slot == slot && o.sessionType == sessionType && o.discipline == discipline)
        .firstOrNull;
    setState(() {
      _picking = PendingPick(
        trainer: t,
        sessionType: sessionType,
        discipline: discipline,
        slot: slot,
        locationName: offering?.locationName,
      );
      _pickPlanId = chargePlanId;
      _bookingError = null;
    });
  }

  /// Mirrors App.jsx's `joinWaitlist` — a full slot bypasses the normal
  /// session-cap check (that's the point), but still needs a real
  /// membership to be eligible at all, same as BookSession.jsx's own
  /// `check.noMembership` gate.
  Future<void> _joinWaitlist(Trainer t, String sessionType, String discipline, int slot) async {
    final key = _waitlistKey(t.id, _date, slot);
    if (_waitlistBusyKeys.contains(key)) return;
    final info = ref.read(clientInfoProvider);
    final bookings = ref.read(clientBookingsProvider);
    final held = heldAccessPlans(info, ref.read(membershipPlansProvider));
    final settings = ref.read(platformSettingsProvider);
    final waiverCheck = waiverGateCheck(info: info, record: ref.read(clientRecordProvider), waiverDocs: ref.read(waiversProvider));
    if (waiverCheck != null) {
      _needsSignature(waiverCheck, () => _joinWaitlist(t, sessionType, discipline, slot));
      return;
    }
    final check = canBookOffering(
      info,
      sessionType,
      bookings,
      _date,
      slot,
      held,
      minBookingLeadHours: settings.minBookingLeadHours,
      maxBookingHorizonDays: settings.maxBookingHorizonDays,
    );
    if (check.noMembership) {
      setState(() => _denied = check);
      return;
    }
    final waitlist = ref.read(waitlistProvider);
    final already = waitlist.any((w) => w.clientId == info.id && w.trainerId == t.id && w.date == _date && w.slot == slot && w.status == "waiting");
    if (already) return;
    final position = waitlist.where((w) => w.trainerId == t.id && w.date == _date && w.slot == slot && w.status == "waiting").length + 1;
    setState(() => _waitlistBusyKeys.add(key));
    try {
      final saved = await SupabaseService.insertWaitlistEntry(WaitlistEntry(
        id: "",
        clientId: info.id,
        clientName: info.name,
        trainerId: t.id,
        trainerName: t.name,
        date: _date,
        slot: slot,
        sessionType: sessionType,
        discipline: discipline,
        status: "waiting",
        position: position,
        addedAt: stamp(),
      ));
      ref.read(waitlistProvider.notifier).add(saved);
    } catch (e) {
      _showError("Couldn't join the waitlist — check your connection and try again.");
    } finally {
      if (mounted) setState(() => _waitlistBusyKeys.remove(key));
    }
  }

  Future<void> _leaveWaitlist(WaitlistEntry w) async {
    final key = _waitlistKey(w.trainerId, w.date, w.slot);
    if (_waitlistBusyKeys.contains(key)) return;
    setState(() => _waitlistBusyKeys.add(key));
    try {
      await SupabaseService.deleteWaitlistEntry(w.id);
      ref.read(waitlistProvider.notifier).remove(w.id);
    } catch (e) {
      _showError("Couldn't leave the waitlist — check your connection and try again.");
    } finally {
      if (mounted) setState(() => _waitlistBusyKeys.remove(key));
    }
  }

  Future<void> _confirmBooking() async {
    if (_busy) return;
    final info = ref.read(clientInfoProvider);
    final pick = _picking!;
    final draft = Booking(
      id: "",
      clientId: info.id,
      trainerId: pick.trainer.id,
      date: _date,
      slot: pick.slot,
      sessionType: pick.sessionType,
      discipline: pick.discipline,
      locationName: pick.locationName ?? pick.trainer.locationName,
      planId: _pickPlanId,
    );
    setState(() {
      _busy = true;
      _bookingError = null;
    });
    try {
      final saved = await SupabaseService.insertBooking(draft);
      // Both lists: the client's own (their upcoming sessions) and the
      // gym-wide one the slot list reads for "Booked" / "x of 4 open".
      final allBookings = ref.read(allBookingsProvider.notifier);
      allBookings.addBooking(saved);
      final rescheduling = _rescheduling;
      if (rescheduling != null) {
        await SupabaseService.deleteBooking(rescheduling.id);
        ref.read(clientBookingsProvider.notifier).reschedule(saved, rescheduling.id);
        allBookings.cancelBooking(rescheduling.id);
        notifyPush(
          profileId: info.id,
          title: "Session rescheduled",
          body: "Your session is now ${niceDate(_date)} at ${fmtSlot(pick.slot)}.",
        );
      } else {
        ref.read(clientBookingsProvider.notifier).addBooking(saved);
        notifyPush(
          profileId: info.id,
          title: "Booking confirmed",
          body: "You're booked for ${niceDate(_date)} at ${fmtSlot(pick.slot)}.",
        );
      }
      // Notifications spec — "Low session balance": fires once, right at
      // the exact booking that brings a client down to their last 1 or 2
      // remaining sessions this period — never on every booking after, so
      // it can't spam.
      final plan = ref.read(membershipPlansProvider.notifier).byId(_pickPlanId);
      if (plan != null) {
        final remaining = effectiveMaxSessions(info, plan) - sessionsUsedThisPeriod(info, plan, ref.read(clientBookingsProvider));
        if (remaining == 1 || remaining == 2) {
          notifyPush(
            profileId: info.id,
            title: "Low session balance",
            body: "You have $remaining session${remaining == 1 ? '' : 's'} left this period.",
          );
        }
      }
      setState(() {
        _busy = false;
        _picking = null;
        _pickPlanId = null;
        _rescheduling = null;
      });
    } catch (e) {
      // ignore: avoid_print
      print("[booking confirm] failed: $e");
      if (!mounted) return;
      // The server found a waiver this device didn't know about yet — open
      // it right here, then come back to this same confirm screen.
      if (e.toString().contains("waiver-required") && _outstandingDocs().isNotEmpty) {
        setState(() {
          _busy = false;
          _signingDoc = _outstandingDocs().first;
          _afterSigning = null;
        });
        return;
      }
      setState(() {
        _busy = false;
        // Stays visible on the picking screen (not a transient SnackBar) so
        // a real failure — this device has hit genuine network drops before
        // — can't get missed and silently look like nothing happened.
        // The database itself refuses a booking without a current waiver
        // signature (enforce_waiver_before_booking) — say so plainly.
        _bookingError = _bookingErrorMessage(e);
      });
    }
  }

  /// Why the booking was refused, in the client's terms. The database checks
  /// capacity, coach double-booking and the waiver as the last word (the app's
  /// own copy of the schedule can be a few seconds stale), so its reason is
  /// the accurate one — "check your connection" is only for a real failure.
  String _bookingErrorMessage(Object e) {
    final text = e.toString();
    if (text.contains("waiver-required")) {
      return "Please sign the waiver under Signatures (in the menu) before booking.";
    }
    if (text.contains("already at capacity")) {
      return "That session just filled up. Pick another time, or join the waitlist.";
    }
    if (text.contains("overlaps this time slot")) {
      return "This coach was just booked for another session at that time. Please pick another time.";
    }
    if (text.contains("membership") || text.contains("plan")) {
      return "That session isn't covered by your current plan — see Membership for what each plan covers.";
    }
    return "Couldn't book that session — check your connection and try again.";
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(clientInfoProvider);
    final bookings = ref.watch(clientBookingsProvider);
    final trainers = ref.watch(trainersProvider);

    if (_cancelTarget != null) {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _cancelTarget = null),
        child: BookingCancelScreen(
          booking: _cancelTarget!,
          trainers: trainers,
          onBack: () => setState(() => _cancelTarget = null),
          onConfirmCancel: _confirmCancel,
        ),
      );
    }

    final signing = _signingDoc;
    if (signing != null) {
      return LocalBackScope(
        isOpen: true,
        onBack: _cancelSigning,
        child: WaiverSigningScreen(
          key: ValueKey(signing.id),
          doc: signing,
          onBack: _cancelSigning,
          onDone: _signingFinished,
          doneLabel: "Continue booking",
        ),
      );
    }

    if (_denied != null) {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() {
          _denied = null;
          _afterSigning = null;
        }),
        child: BookingDeniedScreen(
          check: _denied,
          onBack: () => setState(() {
            _denied = null;
            _afterSigning = null;
          }),
          onGoMemberships: widget.onGoMemberships,
          onGoSignatures: _startSigning,
        ),
      );
    }

    if (_picking != null) {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() {
          _picking = null;
          _bookingError = null;
        }),
        child: BookingPickingScreen(
          pick: _picking!,
          date: _date,
          onBack: () => setState(() {
            _picking = null;
            _bookingError = null;
          }),
          onConfirm: _confirmBooking,
          busy: _busy,
          error: _bookingError,
        ),
      );
    }

    final held = heldAccessPlans(info, ref.watch(membershipPlansProvider));
    final myUpcoming = bookings.where((b) => b.clientId == info.id && b.date.compareTo(isoToday()) >= 0).toList()
      ..sort((a, b) => (a.date + a.slot.toString().padLeft(4, '0')).compareTo(b.date + b.slot.toString().padLeft(4, '0')));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // First thing on the screen, above even the sessions-remaining
          // line: an offer is time-limited and passes to someone else if
          // missed, so nothing on this page is more urgent.
          const WaitlistOfferBanner(),
          // Above the upcoming-sessions grid, not below it: how many sessions
          // are left is the thing that decides whether booking another one is
          // even possible, so it shouldn't sit under a list the client has to
          // scroll past (or expand) to reach.
          if (held.isNotEmpty && _rescheduling == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _MembershipBanner(info: info, plans: held, bookings: bookings),
            ),

          if (myUpcoming.isNotEmpty) ...[
            const SectionLabel("Your upcoming sessions"),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // Fixed count, not max-extent: 4 across on every screen, with
              // the cards themselves flexing to whatever width that leaves.
              // At 4 columns a card is roughly half the width it had at 3, so
              // the actions inside stack instead of sitting side by side —
              // see UpcomingSessionCard, which lays itself out from its own
              // measured width rather than assuming either shape.
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisExtent: 130,
                crossAxisSpacing: 6,
                mainAxisSpacing: 8,
              ),
              itemCount: (_showAllUpcoming ? myUpcoming : myUpcoming.take(4).toList()).length,
              itemBuilder: (context, i) {
                final b = (_showAllUpcoming ? myUpcoming : myUpcoming.take(4).toList())[i];
                return UpcomingSessionCard(
                  booking: b,
                  trainers: trainers,
                  onReschedule: _startReschedule,
                  onCancel: (b) => setState(() => _cancelTarget = b),
                );
              },
            ),
            if (myUpcoming.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => setState(() => _showAllUpcoming = !_showAllUpcoming),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.gold,
                      side: const BorderSide(color: AppColors.line),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                    child: Text(
                      _showAllUpcoming ? "Show fewer" : "View all ${myUpcoming.length} upcoming sessions",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 22),
          ],

          if (_rescheduling != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.1),
                border: Border.all(color: AppColors.gold),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 1), child: Icon(LucideIcons.calendar, size: 16, color: AppColors.gold)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 12, color: AppColors.txt, height: 1.5),
                        children: [
                          const TextSpan(text: "Rescheduling "),
                          TextSpan(
                            text: "${dayLabel(_rescheduling!.date)} · ${fmtSlot(_rescheduling!.slot)}",
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const TextSpan(text: " — pick a new time."),
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _rescheduling = null),
                    style: TextButton.styleFrom(foregroundColor: AppColors.mute, padding: EdgeInsets.zero, minimumSize: Size.zero),
                    child: const Text("Stop", style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),

          // No plan means nothing here can be booked, so the schedule isn't
          // offered at all — showing every open slot to someone who can't
          // take any of them just reads as broken. Their upcoming sessions
          // (from a plan that has since ended) still list above; only the
          // pick-and-book steps are replaced. Staff booking themselves are
          // exempt, same as every membership check.
          if (held.isEmpty && !info.isStaff)
            _NoPlanGate(onGoMemberships: widget.onGoMemberships)
          else
          Builder(builder: (context) {
          // Only one type the client can book (e.g. a single Semi-Private
          // membership) — step 1 would be a one-option question, so it's
          // skipped and Booking opens straight on step 2, Choose a Discipline.
          final types = _bookableTypes(
            plans: held,
            trainers: trainers,
            offeredTypes: ref.watch(platformSettingsProvider).offeredSessionTypes,
          );
          final onlyType = types.length == 1 ? types.first : null;
          final chosenType = _chosenType ?? onlyType;
          final changeType = onlyType == null ? () => _pickType(null) : null;
          return LocalBackScope(
            // With step 1 skipped, step 2 is the start — nothing to go back to.
            isOpen: _chosenDisc != null || (_chosenType != null && onlyType == null),
            onBack: () => setState(() {
              if (_chosenDisc != null) {
                _chosenDisc = null;
              } else {
                _chosenType = null;
              }
            }),
            child: chosenType == null
                ? _StepOne(
                    plans: held,
                    isStaff: info.isStaff,
                    trainers: trainers,
                    offeredTypes: ref.watch(platformSettingsProvider).offeredSessionTypes,
                    onPick: _pickType,
                  )
                : _chosenDisc == null
                    ? _StepTwo(
                        chosenType: chosenType,
                        trainers: trainers,
                        onChangeType: changeType,
                        onPick: (d) => setState(() {
                          _chosenType = chosenType;
                          _chosenDisc = d;
                        }),
                      )
                    : _StepThree(
                        date: _date,
                        chosenType: chosenType,
                        chosenDisc: _chosenDisc!,
                        info: info,
                        trainers: trainers,
                        // Gym-wide, not clientBookingsProvider's self-scoped `bookings`
                        // above — capacity/fullness has to account for every client's
                        // bookings on this trainer/date/slot, not just the signed-in
                        // client's own (which would make a slot never show full unless
                        // they themselves already occupy it).
                        bookings: ref.watch(allBookingsProvider),
                        blockedTimes: ref.watch(blockedTimesProvider),
                        waitlist: ref.watch(waitlistProvider),
                        gymLocationName: ref.watch(platformSettingsProvider).locationName,
                        onDateChange: (d) => setState(() => _date = d),
                        onChangeType: changeType == null
                            ? null
                            : () => setState(() {
                                  _chosenType = null;
                                  _chosenDisc = null;
                                }),
                        onChangeDisc: () => setState(() => _chosenDisc = null),
                        onSlotTap: _onSlotTap,
                        onJoinWaitlist: _joinWaitlist,
                        onLeaveWaitlist: _leaveWaitlist,
                        waitlistBusyKeys: _waitlistBusyKeys,
                        semiPrivateCap: ref.watch(platformSettingsProvider).semiPrivateCap,
                      ),
          );
          }),
        ],
      ),
    );
  }
}

/// One line per held plan — a client with a membership and a package needs
/// to see both balances, since each session type may draw on a different
/// one. The banner takes the colour of the lowest balance.
class _MembershipBanner extends StatelessWidget {
  const _MembershipBanner({required this.info, required this.plans, required this.bookings});
  final dynamic info;
  final List<MembershipPlan> plans;
  final List<Booking> bookings;

  @override
  Widget build(BuildContext context) {
    final lines = [
      for (final plan in plans)
        (
          plan: plan,
          remaining: (effectiveMaxSessions(info, plan) - sessionsUsedThisPeriod(info, plan, bookings))
              .clamp(0, effectiveMaxSessions(info, plan)),
        ),
    ];
    final lowest = lines.map((l) => l.remaining).reduce((a, b) => a < b ? a : b);
    final color = lowest > 3 ? AppColors.grn : (lowest > 0 ? const Color(0xFFD68A4F) : const Color(0xFFC97F7F));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Padding(
              padding: EdgeInsets.only(top: l == lines.first ? 0 : 4),
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: "${l.remaining} session${l.remaining != 1 ? 's' : ''} remaining  ",
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: l.remaining > 0 ? AppColors.txt : const Color(0xFFC97F7F)),
                    ),
                    TextSpan(
                      text: "— ${l.plan.name}${l.plan.kind == PlanKind.membership ? " this month" : ""}",
                      style: const TextStyle(fontSize: 12, color: AppColors.mute),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The session types this client can pick in step 1 — what any plan they
/// hold covers (every type for staff booking themselves, who hold none),
/// limited to what the gym offers (Customize Platform → Services), plus
/// Large Group, which comes with any membership as long as a coach runs it.
List<String> _bookableTypes({
  required List<MembershipPlan> plans,
  required List<Trainer> trainers,
  required List<String> offeredTypes,
}) {
  final covered = (plans.isEmpty
          ? const ["semi-private", "one-on-one"]
          : plans.expand((p) => p.allowedTypes).toSet().toList())
      .where(offeredTypes.contains)
      .toList();
  final anyLargeGroupOffered = offeredTypes.contains("large-group") && trainers.any(
    (t) => t.offeredAvailability.any((b) => b.sessionType == "large-group" && b.byDay.values.any((s) => s.isNotEmpty)),
  );
  return [...covered, if (anyLargeGroupOffered) "large-group"];
}

class _StepOne extends StatelessWidget {
  const _StepOne({
    required this.plans,
    required this.onPick,
    required this.trainers,
    required this.offeredTypes,
    this.isStaff = false,
  });

  /// Customize Platform → Services. A type the gym has switched off is not
  /// offered even if a plan technically covers it.
  final List<String> offeredTypes;

  /// Everything the client holds — a type is offered if any of them covers
  /// it. Empty only for staff booking themselves, who see every type.
  final List<MembershipPlan> plans;
  final ValueChanged<String> onPick;
  final List<Trainer> trainers;
  final bool isStaff;

  @override
  Widget build(BuildContext context) {
    final types = _bookableTypes(plans: plans, trainers: trainers, offeredTypes: offeredTypes);
    final allowedTypes = types;
    final anyLargeGroupOffered = types.contains("large-group");
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel("Step 1 — What kind of session?"),
        if (allowedTypes.contains("semi-private"))
          AppCard(
            onTap: () => onPick("semi-private"),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Semi-Private", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                SizedBox(height: 3),
                Text(
                  "Share your coach while following your own personalized workout. Expert coaching, "
                  "individualized guidance, and accountability in a small group setting.",
                  style: TextStyle(fontSize: 13, color: AppColors.mute, height: 1.5),
                ),
              ],
            ),
          ),
        if (allowedTypes.contains("one-on-one"))
          AppCard(
            onTap: () => onPick("one-on-one"),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("One-on-One", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                SizedBox(height: 3),
                Text(
                  "Your trainer's full attention in a private session tailored entirely to your goals, "
                  "fitness level, and needs.",
                  style: TextStyle(fontSize: 13, color: AppColors.mute, height: 1.5),
                ),
              ],
            ),
          ),
        if (anyLargeGroupOffered)
          AppCard(
            onTap: () => onPick("large-group"),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Large Group", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 3),
                Text(
                  "Hike and Outdoor HIIT classes — 1 hour, capacity ${capFor("large-group")}, starting on the "
                  "hour every hour. Included with any active membership.",
                  style: const TextStyle(fontSize: 13, color: AppColors.mute, height: 1.5),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// What a client with no active plan sees instead of the booking steps.
/// Nothing on the schedule is bookable for them, so rather than list slots
/// they'd be refused on, this says why and sends them to the one place that
/// changes it.
class _NoPlanGate extends StatelessWidget {
  const _NoPlanGate({required this.onGoMemberships});
  final VoidCallback onGoMemberships;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.goldDim),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(LucideIcons.lock, size: 16, color: AppColors.gold),
              SizedBox(width: 8),
              Text("Booking needs a plan", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "Sessions are booked against a membership or package. Pick one in the Membership Hub and the full schedule opens up here.",
            style: TextStyle(fontSize: 12.5, color: AppColors.mute, height: 1.5),
          ),
          const SizedBox(height: 14),
          BtnGold(
            full: true,
            onPressed: onGoMemberships,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.creditCard, size: 15, color: Colors.white),
                SizedBox(width: 6),
                Text("See plans and what each covers"),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepTwo extends StatelessWidget {
  const _StepTwo({required this.chosenType, required this.trainers, this.onChangeType, required this.onPick});
  final String chosenType;
  final List<Trainer> trainers;

  /// Null when the client can only book one session type — nothing to change to.
  final VoidCallback? onChangeType;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final offered = <String>{};
    for (final t in trainers) {
      for (final block in t.offeredAvailability) {
        if (block.sessionType == chosenType) {
          offered.add(block.discipline);
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(sessionTypeLabel(chosenType), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gold)),
            if (onChangeType != null) ...[
              const SizedBox(width: 8),
              const Text("›", style: TextStyle(fontSize: 13, color: AppColors.mute)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onChangeType,
                child: const Text("Change", style: TextStyle(fontSize: 12, color: AppColors.mute, decoration: TextDecoration.underline)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        const SectionLabel("Step 2 — Choose a discipline"),
        if (offered.isEmpty)
          HintBox(text: "No ${sessionTypeLabel(chosenType).toLowerCase()} sessions are set up yet. Check back soon or contact ONE Fitness.")
        else
          ...offered.map((d) => AppCard(
                onTap: () => onPick(d),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(disciplineLabel(d), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text("${sessionTypeLabel(chosenType)} · ${disciplineLabel(d)}", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                        ],
                      ),
                    ),
                    const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mute),
                  ],
                ),
              )),
      ],
    );
  }
}

class _JumpToChip extends StatelessWidget {
  const _JumpToChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(border: Border.all(color: AppColors.line), color: AppColors.card, borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.mute)),
      ),
    );
  }
}

class _SlotAvailability {
  _SlotAvailability({required this.trainer, required this.open, required this.cap, required this.mine, this.locationName});
  final Trainer trainer;
  final int open;
  final int cap;
  final bool mine;

  /// Where this session runs, when it was created at one of the gym's other
  /// locations — otherwise the coach's or the gym's main one.
  final String? locationName;
}

class _StepThree extends StatefulWidget {
  const _StepThree({
    required this.date,
    required this.chosenType,
    required this.chosenDisc,
    required this.info,
    required this.trainers,
    required this.bookings,
    required this.blockedTimes,
    required this.waitlist,
    required this.onDateChange,
    this.onChangeType,
    required this.onChangeDisc,
    required this.onSlotTap,
    required this.onJoinWaitlist,
    required this.onLeaveWaitlist,
    required this.waitlistBusyKeys,
    required this.semiPrivateCap,
    required this.gymLocationName,
  });

  /// Customize Platform → Location, shown on a slot whose coach has no
  /// location of their own.
  final String gymLocationName;
  final String date;
  final String chosenType;
  final String chosenDisc;
  final dynamic info;
  final List<Trainer> trainers;

  /// Gym-wide (every client's bookings), not just the signed-in client's —
  /// capacity/fullness must account for everyone occupying this trainer/
  /// date/slot. The "mine" flag below still filters back down to `info.id`
  /// per booking, so a single shared list serves both purposes correctly.
  final List<Booking> bookings;

  /// Gym-wide ad-hoc Block Time entries — a slot a coach has blocked off
  /// must stop being offered here, same as [fallsInUnavailability]'s
  /// recurring-window check just below it.
  final List<BlockedTime> blockedTimes;
  final List<WaitlistEntry> waitlist;
  final ValueChanged<String> onDateChange;
  /// Null when the client can only book one session type — nothing to change to.
  final VoidCallback? onChangeType;
  final VoidCallback onChangeDisc;
  final void Function(Trainer, String, String, int, bool, bool) onSlotTap;
  final void Function(Trainer, String, String, int) onJoinWaitlist;
  final void Function(WaitlistEntry) onLeaveWaitlist;
  final Set<String> waitlistBusyKeys;
  final int semiPrivateCap;

  @override
  State<_StepThree> createState() => _StepThreeState();
}

class _StepThreeState extends State<_StepThree> {
  // Stable per-slot keys (not recreated every build) so "Jump to" can
  // scroll a specific slot into view via Scrollable.ensureVisible — the
  // Flutter equivalent of scrollIntoView against a DOM id.
  final Map<int, GlobalKey> _slotKeys = {};
  GlobalKey _keyFor(int slot) => _slotKeys.putIfAbsent(slot, GlobalKey.new);

  void _jumpTo(int slot) {
    final ctx = _slotKeys[slot]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.date;
    final chosenType = widget.chosenType;
    final chosenDisc = widget.chosenDisc;
    final info = widget.info;
    final trainers = widget.trainers;
    final bookings = widget.bookings;
    final waitlist = widget.waitlist;
    final onDateChange = widget.onDateChange;
    final onChangeType = widget.onChangeType;
    final onChangeDisc = widget.onChangeDisc;
    final onSlotTap = widget.onSlotTap;
    final sunday = isSunday(date);

    final bySlot = <int, List<_SlotAvailability>>{};
    {
      for (final t in trainers) {
        if (fallsInUnavailability(t, date)) continue;
        for (final o in trainerOfferingsOn(t, date)) {
          // The weekly pattern never runs on Sunday; a session the owner
          // created on a Sunday date deliberately does.
          if (sunday && !o.oneOff) continue;
          if (o.sessionType != chosenType || o.discipline != chosenDisc) continue;
          if (fallsInBlockedTime(widget.blockedTimes, t.id, date, o.slot)) continue;
          final used = bookedCount(bookings, t.id, date, o.slot);
          final cap = capFor(o.sessionType, semiPrivateCap: widget.semiPrivateCap);
          final mine = bookings.any((b) => b.clientId == info.id && b.trainerId == t.id && b.date == date && b.slot == o.slot);
          bySlot.putIfAbsent(o.slot, () => []).add(_SlotAvailability(trainer: t, open: cap - used, cap: cap, mine: mine, locationName: o.locationName));
        }
      }
      // A session that's already started (or already passed) today can't
      // be booked — every other date on the calendar is entirely future,
      // so this only ever trims today's slot list.
      if (date == isoToday()) {
        final now = DateTime.now();
        final nowMin = now.hour * 60 + now.minute;
        bySlot.removeWhere((slot, _) => slot <= nowMin);
      }
    }
    final slots = bySlot.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Text(sessionTypeLabel(chosenType), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gold)),
            const Text("›", style: TextStyle(fontSize: 13, color: AppColors.mute)),
            Text(disciplineLabel(chosenDisc), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gold)),
            if (onChangeType != null)
              GestureDetector(
                onTap: onChangeType,
                child: const Text("Change type", style: TextStyle(fontSize: 11, color: AppColors.mute, decoration: TextDecoration.underline)),
              ),
            GestureDetector(
              onTap: onChangeDisc,
              child: const Text("Change discipline", style: TextStyle(fontSize: 11, color: AppColors.mute, decoration: TextDecoration.underline)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        DateStrip(date: date, onSelect: onDateChange, disablePast: true),
        if (slots.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text("Jump to:", style: TextStyle(fontSize: 11, color: AppColors.mute)),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final slot in slots) ...[
                          _JumpToChip(label: fmtSlotCompactAmPm(slot), onTap: () => _jumpTo(slot)),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (sunday)
          const HintBox(text: "ONE Fitness is closed on Sundays. Pick another day.")
        else if (trainers.isEmpty)
          const HintBox(text: "No trainers set up yet.")
        else if (slots.isEmpty)
          HintBox(text: "No ${sessionTypeLabel(chosenType).toLowerCase()} ${disciplineLabel(chosenDisc)} sessions available on this day yet.")
        else
          ...slots.map((slot) {
            final avail = bySlot[slot]!;
            return Padding(
              key: _keyFor(slot),
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fmtSlot(slot), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.gold)),
                  const SizedBox(height: 8),
                  ...avail.map((a) {
                    final isFull = a.open <= 0 && !a.mine;
                    final onWaitlistMatches = waitlist.where(
                      (w) => w.clientId == info.id && w.trainerId == a.trainer.id && w.date == date && w.slot == slot && w.status == "waiting",
                    );
                    final onWaitlist = onWaitlistMatches.isEmpty ? null : onWaitlistMatches.first;
                    final waitlistBusy = widget.waitlistBusyKeys.contains("${a.trainer.id}|$date|$slot");
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        children: [
                          InkWell(
                            onTap: (a.mine || isFull) ? null : () => onSlotTap(a.trainer, chosenType, chosenDisc, slot, a.mine, isFull),
                            borderRadius: BorderRadius.circular(10),
                            child: Opacity(
                              opacity: isFull && onWaitlist == null ? 0.65 : 1,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: a.mine
                                      ? AppColors.gold.withValues(alpha: 0.1)
                                      : onWaitlist != null
                                          ? const Color(0xFFD68A4F).withValues(alpha: 0.06)
                                          : AppColors.card,
                                  border: Border.all(
                                    color: a.mine
                                        ? AppColors.gold
                                        : onWaitlist != null
                                            ? const Color(0xFFD68A4F).withValues(alpha: 0.35)
                                            : (a.open > 0 ? AppColors.line : const Color(0xFF222222)),
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Avatar(src: a.trainer.photo, name: a.trainer.name, size: 38, active: a.mine),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Session type leads the card — what's
                                          // being booked matters more than who's
                                          // running it, and every slot in a day
                                          // otherwise opens with the same coach
                                          // name repeated down the list.
                                          Text(
                                            "${sessionTypeLabel(chosenType)} · ${disciplineLabel(chosenDisc)}",
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(a.trainer.displayTitle, style: const TextStyle(fontSize: 12, color: AppColors.txt)),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(top: 3),
                                            child: GestureDetector(
                                              onTap: () => CoachProfileCard.show(context, a.trainer),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: const [
                                                  Text("Meet the Coach", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.mute)),
                                                  SizedBox(width: 3),
                                                  Icon(LucideIcons.chevronRight, size: 11, color: AppColors.mute),
                                                ],
                                              ),
                                            ),
                                          ),
                                          // Where this session runs: the location
                                          // it was created at, else the coach's
                                          // own, else the gym's main one.
                                          if ((a.locationName ?? a.trainer.locationName ?? widget.gymLocationName).isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 3),
                                              child: Row(
                                                children: [
                                                  const Icon(LucideIcons.mapPin, size: 11, color: AppColors.mute),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    a.locationName ?? a.trainer.locationName ?? widget.gymLocationName,
                                                    style: const TextStyle(fontSize: 11, color: AppColors.mute),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (a.mine)
                                      const Text("Booked ✓", style: TextStyle(fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w700))
                                    else if (a.open > 0)
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text("${a.open}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.gold)),
                                          Text("of ${a.cap} open", style: const TextStyle(fontSize: 10, color: AppColors.mute)),
                                        ],
                                      )
                                    else if (onWaitlist != null)
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          const Text("Waitlist", style: TextStyle(fontSize: 11, color: Color(0xFFD68A4F), fontWeight: FontWeight.w700)),
                                          Text("#${onWaitlist.position ?? '—'}", style: const TextStyle(fontSize: 10, color: AppColors.mute)),
                                        ],
                                      )
                                    else
                                      const Text("Full", style: TextStyle(fontSize: 12, color: Color(0xFF8A5A5A), fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (isFull && !a.mine)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: SizedBox(
                                width: double.infinity,
                                child: onWaitlist != null
                                    ? OutlinedButton(
                                        onPressed: waitlistBusy ? null : () => widget.onLeaveWaitlist(onWaitlist),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFFC97F7F),
                                          side: const BorderSide(color: Color(0xFF6B3B3B)),
                                          padding: const EdgeInsets.symmetric(vertical: 7),
                                        ),
                                        child: Text(
                                          "Leave waitlist (position #${onWaitlist.position ?? '—'})",
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      )
                                    : OutlinedButton(
                                        onPressed: waitlistBusy ? null : () => widget.onJoinWaitlist(a.trainer, chosenType, chosenDisc, slot),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFFD68A4F),
                                          side: const BorderSide(color: Color(0xFFD68A4F)),
                                          backgroundColor: const Color(0xFFD68A4F).withValues(alpha: 0.1),
                                          padding: const EdgeInsets.symmetric(vertical: 7),
                                        ),
                                        child: const Text("+ Join waitlist", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                      ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
      ],
    );
  }
}
