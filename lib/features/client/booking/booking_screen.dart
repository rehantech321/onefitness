import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/booking_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/utils/membership_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/mock/mock_data.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/client_providers.dart";
import "booking_cancel_screen.dart";
import "booking_picking_screen.dart";
import "date_strip.dart";
import "upcoming_session_card.dart";

/// Mirrors BookSession.jsx, trimmed to the everyday linear flow: browse
/// upcoming sessions, pick a session type -> discipline -> time slot,
/// confirm, or cancel/reschedule an existing booking. Recurring multi-day
/// booking, the waitlist, in-booking challenge browsing, and the "Meet the
/// Coach" profile card are not built yet — each is its own sizeable feature.
class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key, required this.onGoMemberships});

  final VoidCallback onGoMemberships;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  String _date = isoToday();
  String? _chosenType;
  String? _chosenDisc;
  PendingPick? _picking;
  Booking? _cancelTarget;
  Booking? _rescheduling;
  dynamic _denied; // BookingCheck?
  bool _showAllUpcoming = false;

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

  void _confirmCancel() {
    final b = _cancelTarget!;
    ref.read(clientBookingsProvider.notifier).cancelBooking(b.id);
    setState(() => _cancelTarget = null);
  }

  void _onSlotTap(Trainer t, String sessionType, String discipline, int slot, bool mine, bool isFull) {
    if (mine || isFull) return;
    final info = ref.read(clientInfoProvider);
    final bookings = ref.read(clientBookingsProvider);
    if (_rescheduling == null) {
      final check = canBookOffering(info, sessionType, bookings, _date, slot);
      if (!check.ok) {
        setState(() => _denied = check);
        return;
      }
    }
    setState(() => _picking = PendingPick(trainer: t, sessionType: sessionType, discipline: discipline, slot: slot));
  }

  void _confirmBooking() {
    final info = ref.read(clientInfoProvider);
    final pick = _picking!;
    final newBooking = Booking(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      clientId: info.id,
      trainerId: pick.trainer.id,
      date: _date,
      slot: pick.slot,
      sessionType: pick.sessionType,
      discipline: pick.discipline,
      locationName: pick.trainer.locationName,
    );
    if (_rescheduling != null) {
      ref.read(clientBookingsProvider.notifier).reschedule(newBooking, _rescheduling!.id);
    } else {
      ref.read(clientBookingsProvider.notifier).addBooking(newBooking);
    }
    setState(() {
      _picking = null;
      _rescheduling = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(clientInfoProvider);
    final bookings = ref.watch(clientBookingsProvider);
    final trainers = ref.watch(trainersProvider);

    if (_cancelTarget != null) {
      return BookingCancelScreen(
        booking: _cancelTarget!,
        trainers: trainers,
        onBack: () => setState(() => _cancelTarget = null),
        onConfirmCancel: _confirmCancel,
      );
    }

    if (_denied != null) {
      return BookingDeniedScreen(
        check: _denied,
        onBack: () => setState(() => _denied = null),
        onGoMemberships: widget.onGoMemberships,
      );
    }

    if (_picking != null) {
      return BookingPickingScreen(
        pick: _picking!,
        date: _date,
        onBack: () => setState(() => _picking = null),
        onConfirm: _confirmBooking,
      );
    }

    final plan = MockData.planById(info.membershipPlanId);
    final myUpcoming = bookings.where((b) => b.clientId == info.id && b.date.compareTo(isoToday()) >= 0).toList()
      ..sort((a, b) => (a.date + a.slot.toString().padLeft(4, '0')).compareTo(b.date + b.slot.toString().padLeft(4, '0')));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (myUpcoming.isNotEmpty) ...[
            const SectionLabel("Your upcoming sessions"),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 0.72,
              children: (_showAllUpcoming ? myUpcoming : myUpcoming.take(4).toList())
                  .map((b) => UpcomingSessionCard(
                        booking: b,
                        trainers: trainers,
                        onReschedule: _startReschedule,
                        onCancel: (b) => setState(() => _cancelTarget = b),
                      ))
                  .toList(),
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

          if (_chosenType == null)
            _StepOne(plan: plan, onPick: _pickType)
          else if (_chosenDisc == null)
            _StepTwo(
              chosenType: _chosenType!,
              trainers: trainers,
              onChangeType: () => _pickType(null),
              onPick: (d) => setState(() => _chosenDisc = d),
            )
          else
            _StepThree(
              date: _date,
              chosenType: _chosenType!,
              chosenDisc: _chosenDisc!,
              info: info,
              trainers: trainers,
              bookings: bookings,
              onDateChange: (d) => setState(() => _date = d),
              onChangeType: () => setState(() {
                _chosenType = null;
                _chosenDisc = null;
              }),
              onChangeDisc: () => setState(() => _chosenDisc = null),
              onSlotTap: _onSlotTap,
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
    final checkedIn = bookings.where((b) => b.attendanceStatus == "checked-in").toList();
    final used = sessionsUsedThisPeriod(info, plan, checkedIn);
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
  const _StepOne({required this.plan, required this.onPick});
  final MembershipPlan? plan;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final allowedTypes = plan?.allowedTypes ?? const ["semi-private", "one-on-one"];
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
        if (plan == null)
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

class _SlotAvailability {
  _SlotAvailability({required this.trainer, required this.open, required this.cap, required this.mine});
  final Trainer trainer;
  final int open;
  final int cap;
  final bool mine;
}

class _StepThree extends StatelessWidget {
  const _StepThree({
    required this.date,
    required this.chosenType,
    required this.chosenDisc,
    required this.info,
    required this.trainers,
    required this.bookings,
    required this.onDateChange,
    required this.onChangeType,
    required this.onChangeDisc,
    required this.onSlotTap,
  });

  final String date;
  final String chosenType;
  final String chosenDisc;
  final dynamic info;
  final List<Trainer> trainers;
  final List<Booking> bookings;
  final ValueChanged<String> onDateChange;
  final VoidCallback onChangeType;
  final VoidCallback onChangeDisc;
  final void Function(Trainer, String, String, int, bool, bool) onSlotTap;

  @override
  Widget build(BuildContext context) {
    final sunday = isSunday(date);
    final wd = weekdayOf(date);

    final bySlot = <int, List<_SlotAvailability>>{};
    if (!sunday) {
      for (final t in trainers) {
        for (final o in trainerOfferings(t, wd)) {
          if (o.sessionType != chosenType || o.discipline != chosenDisc) continue;
          final used = bookedCount(bookings, t.id, date, o.slot);
          final cap = capFor(o.sessionType);
          final mine = bookings.any((b) => b.clientId == info.id && b.trainerId == t.id && b.date == date && b.slot == o.slot);
          bySlot.putIfAbsent(o.slot, () => []).add(_SlotAvailability(trainer: t, open: cap - used, cap: cap, mine: mine));
        }
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
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fmtSlot(slot), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.gold)),
                  const SizedBox(height: 8),
                  ...avail.map((a) {
                    final isFull = a.open <= 0 && !a.mine;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => onSlotTap(a.trainer, chosenType, chosenDisc, slot, a.mine, isFull),
                        borderRadius: BorderRadius.circular(10),
                        child: Opacity(
                          opacity: isFull ? 0.65 : 1,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: a.mine ? AppColors.gold.withValues(alpha: 0.1) : AppColors.card,
                              border: Border.all(color: a.mine ? AppColors.gold : (a.open > 0 ? AppColors.line : const Color(0xFF222222))),
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
                                else
                                  const Text("Full", style: TextStyle(fontSize: 12, color: Color(0xFF8A5A5A), fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
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
