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
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/models/trainer.dart";
import "../../../data/models/waitlist_entry.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";
import "booking_cancel_screen.dart";
import "booking_picking_screen.dart";
import "date_strip.dart";
import "upcoming_session_card.dart";

/// Mirrors BookSession.jsx, trimmed to the everyday linear flow: browse
/// upcoming sessions, pick a session type -> discipline -> time slot,
/// confirm, or cancel/reschedule an existing booking. Recurring multi-day
/// booking and the waitlist are not built yet — each is its own sizeable
/// feature.
class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key, required this.onGoMemberships, this.initialDate, this.initialReschedule});

  final VoidCallback onGoMemberships;

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
  bool _showAllUpcoming = false;
  bool _busy = false;
  String? _bookingError;
  final Set<String> _waitlistBusyKeys = {};

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
    if (_rescheduling == null) {
      final plan = ref.read(membershipPlansProvider.notifier).byId(info.membershipPlanId);
      final settings = ref.read(platformSettingsProvider);
      final check = canBookOffering(
        info,
        sessionType,
        bookings,
        _date,
        slot,
        plan,
        minBookingLeadHours: settings.minBookingLeadHours,
        maxBookingHorizonDays: settings.maxBookingHorizonDays,
      );
      if (!check.ok) {
        setState(() => _denied = check);
        return;
      }
    }
    setState(() {
      _picking = PendingPick(trainer: t, sessionType: sessionType, discipline: discipline, slot: slot);
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
    final plan = ref.read(membershipPlansProvider.notifier).byId(info.membershipPlanId);
    final settings = ref.read(platformSettingsProvider);
    final check = canBookOffering(
      info,
      sessionType,
      bookings,
      _date,
      slot,
      plan,
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
      locationName: pick.trainer.locationName,
    );
    setState(() {
      _busy = true;
      _bookingError = null;
    });
    try {
      final saved = await SupabaseService.insertBooking(draft);
      final rescheduling = _rescheduling;
      if (rescheduling != null) {
        await SupabaseService.deleteBooking(rescheduling.id);
        ref.read(clientBookingsProvider.notifier).reschedule(saved, rescheduling.id);
      } else {
        ref.read(clientBookingsProvider.notifier).addBooking(saved);
      }
      setState(() {
        _busy = false;
        _picking = null;
        _rescheduling = null;
      });
    } catch (e) {
      // ignore: avoid_print
      print("[booking confirm] failed: $e");
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Stays visible on the picking screen (not a transient SnackBar) so
        // a real failure — this device has hit genuine network drops before
        // — can't get missed and silently look like nothing happened.
        _bookingError = "Couldn't book that session — check your connection and try again.";
      });
    }
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

    if (_denied != null) {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _denied = null),
        child: BookingDeniedScreen(
          check: _denied,
          onBack: () => setState(() => _denied = null),
          onGoMemberships: widget.onGoMemberships,
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

    final plan = ref.watch(membershipPlansProvider.notifier).byId(info.membershipPlanId);
    final myUpcoming = bookings.where((b) => b.clientId == info.id && b.date.compareTo(isoToday()) >= 0).toList()
      ..sort((a, b) => (a.date + a.slot.toString().padLeft(4, '0')).compareTo(b.date + b.slot.toString().padLeft(4, '0')));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (myUpcoming.isNotEmpty) ...[
            const SectionLabel("Your upcoming sessions"),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                mainAxisExtent: 176,
                crossAxisSpacing: 8,
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

          if (plan != null && _rescheduling == null) _MembershipBanner(info: info, plan: plan, bookings: bookings),

          LocalBackScope(
            isOpen: _chosenType != null,
            onBack: () => setState(() {
              if (_chosenDisc != null) {
                _chosenDisc = null;
              } else {
                _chosenType = null;
              }
            }),
            child: _chosenType == null
                ? _StepOne(plan: plan, isStaff: info.isStaff, trainers: trainers, onPick: _pickType)
                : _chosenDisc == null
                    ? _StepTwo(
                        chosenType: _chosenType!,
                        trainers: trainers,
                        onChangeType: () => _pickType(null),
                        onPick: (d) => setState(() => _chosenDisc = d),
                      )
                    : _StepThree(
                        date: _date,
                        chosenType: _chosenType!,
                        chosenDisc: _chosenDisc!,
                        info: info,
                        trainers: trainers,
                        // Gym-wide, not clientBookingsProvider's self-scoped `bookings`
                        // above — capacity/fullness has to account for every client's
                        // bookings on this trainer/date/slot, not just the signed-in
                        // client's own (which would make a slot never show full unless
                        // they themselves already occupy it).
                        bookings: ref.watch(allBookingsProvider),
                        waitlist: ref.watch(waitlistProvider),
                        onDateChange: (d) => setState(() => _date = d),
                        onChangeType: () => setState(() {
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
          ),
        ],
      ),
    );
  }
}

class _MembershipBanner extends StatelessWidget {
  const _MembershipBanner({required this.info, required this.plan, required this.bookings});
  final dynamic info;
  final MembershipPlan plan;
  final List<Booking> bookings;

  @override
  Widget build(BuildContext context) {
    final used = sessionsUsedThisPeriod(info, plan, bookings);
    final max = effectiveMaxSessions(info, plan);
    final remaining = (max - used).clamp(0, max);
    final color = remaining > 3 ? AppColors.grn : (remaining > 0 ? const Color(0xFFD68A4F) : const Color(0xFFC97F7F));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: "$remaining session${remaining != 1 ? 's' : ''} remaining  ",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: remaining > 0 ? AppColors.txt : const Color(0xFFC97F7F)),
                  ),
                  TextSpan(text: "— ${plan.name}", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepOne extends StatelessWidget {
  const _StepOne({required this.plan, required this.onPick, required this.trainers, this.isStaff = false});
  final MembershipPlan? plan;
  final ValueChanged<String> onPick;
  final List<Trainer> trainers;
  final bool isStaff;

  @override
  Widget build(BuildContext context) {
    final allowedTypes = plan?.allowedTypes ?? const ["semi-private", "one-on-one"];
    // Large Group is included with ANY active membership — not gated to a
    // specific plan tier like allowedTypes — and visible for browsing even
    // with no membership at all. Only hidden if literally no coach offers it.
    final anyLargeGroupOffered = trainers.any(
      (t) => t.availability.any((b) => b.sessionType == "large-group" && b.byDay.values.any((s) => s.isNotEmpty)),
    );
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
        if (plan == null && !isStaff)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              "You can browse the full schedule, but you'll need a membership to actually book a session.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.mute),
            ),
          ),
      ],
    );
  }
}

class _StepTwo extends StatelessWidget {
  const _StepTwo({required this.chosenType, required this.trainers, required this.onChangeType, required this.onPick});
  final String chosenType;
  final List<Trainer> trainers;
  final VoidCallback onChangeType;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final offered = <String>{};
    for (final t in trainers) {
      for (final block in t.availability) {
        if (block.sessionType == chosenType) offered.add(block.discipline);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(sessionTypeLabel(chosenType), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gold)),
            const SizedBox(width: 8),
            const Text("›", style: TextStyle(fontSize: 13, color: AppColors.mute)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onChangeType,
              child: const Text("Change", style: TextStyle(fontSize: 12, color: AppColors.mute, decoration: TextDecoration.underline)),
            ),
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
  _SlotAvailability({required this.trainer, required this.open, required this.cap, required this.mine});
  final Trainer trainer;
  final int open;
  final int cap;
  final bool mine;
}

class _StepThree extends StatefulWidget {
  const _StepThree({
    required this.date,
    required this.chosenType,
    required this.chosenDisc,
    required this.info,
    required this.trainers,
    required this.bookings,
    required this.waitlist,
    required this.onDateChange,
    required this.onChangeType,
    required this.onChangeDisc,
    required this.onSlotTap,
    required this.onJoinWaitlist,
    required this.onLeaveWaitlist,
    required this.waitlistBusyKeys,
    required this.semiPrivateCap,
  });

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
  final List<WaitlistEntry> waitlist;
  final ValueChanged<String> onDateChange;
  final VoidCallback onChangeType;
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
    final wd = weekdayOf(date);

    final bySlot = <int, List<_SlotAvailability>>{};
    if (!sunday) {
      for (final t in trainers) {
        if (fallsInUnavailability(t, date)) continue;
        for (final o in trainerOfferings(t, wd)) {
          if (o.sessionType != chosenType || o.discipline != chosenDisc) continue;
          final used = bookedCount(bookings, t.id, date, o.slot);
          final cap = capFor(o.sessionType, semiPrivateCap: widget.semiPrivateCap);
          final mine = bookings.any((b) => b.clientId == info.id && b.trainerId == t.id && b.date == date && b.slot == o.slot);
          bySlot.putIfAbsent(o.slot, () => []).add(_SlotAvailability(trainer: t, open: cap - used, cap: cap, mine: mine));
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
                                          Text(a.trainer.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                          Text(
                                            "${disciplineLabel(chosenDisc)} · ${sessionTypeLabel(chosenType)}",
                                            style: const TextStyle(fontSize: 12, color: AppColors.mute),
                                          ),
                                          if (a.trainer.locationName != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 3),
                                              child: Row(
                                                children: [
                                                  const Icon(LucideIcons.mapPin, size: 11, color: AppColors.goldDim),
                                                  const SizedBox(width: 3),
                                                  Text(a.trainer.locationName!, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                                                ],
                                              ),
                                            ),
                                          Padding(
                                            padding: const EdgeInsets.only(top: 5),
                                            child: GestureDetector(
                                              onTap: () => CoachProfileCard.show(context, a.trainer),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: const [
                                                  Text("Meet the Coach", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gold)),
                                                  SizedBox(width: 3),
                                                  Icon(LucideIcons.chevronRight, size: 11, color: AppColors.gold),
                                                ],
                                              ),
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
