import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "package:uuid/uuid.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/booking_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/utils/membership_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/models/trainer.dart";
import "../../../data/models/waitlist_entry.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

const _kWeekdayOptions = [(1, "Mon"), (2, "Tue"), (3, "Wed"), (4, "Thu"), (5, "Fri"), (6, "Sat")]; // Sunday closed, same as everywhere else

class _Occurrence {
  _Occurrence({required this.date, required this.weekday, required this.status, this.reason, this.decision});
  final String date;
  final int weekday;
  String status; // "bookable" | "full" | "skipped"
  String? reason;
  String? decision; // "waitlist" | "skip" — "full" only
}

class _Summary {
  const _Summary({required this.booked, required this.waitlisted, required this.skipped});
  final int booked;
  final int waitlisted;
  final int skipped;
}

/// Mirrors AdvancedBookingFlow.jsx — set a weekly pattern (days + time) and
/// book every matching occurrence over a chosen range at once, instead of
/// picking one session at a time. A full slot can be requested for the
/// owner's waitlist (status "pending-approval") rather than skipped outright.
class AdvancedBookingScreen extends ConsumerStatefulWidget {
  const AdvancedBookingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<AdvancedBookingScreen> createState() => _AdvancedBookingScreenState();
}

class _AdvancedBookingScreenState extends ConsumerState<AdvancedBookingScreen> {
  String _step = "type"; // type | discipline | coach | pattern | range | gate | review | summary
  String? _sessionType;
  String? _discipline;
  String? _trainerId;
  final List<int> _days = [];
  int _timeSlot = 9 * 60; // minutes from midnight, default 9:00 AM
  String? _rangeChoice;
  List<int> _availableWeekdays = [];
  List<int> _unavailableWeekdays = [];
  List<_Occurrence> _occurrences = [];
  bool _busy = false;
  _Summary? _summary;

  void _back() => widget.onDone();

  Trainer? _trainerOf(List<Trainer> trainers) {
    final matches = trainers.where((t) => t.id == _trainerId);
    return matches.isNotEmpty ? matches.first : null;
  }

  Widget _breadcrumb(VoidCallback onBack) => TextButton.icon(
        onPressed: onBack,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.mute,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(LucideIcons.chevronLeft, size: 15),
        label: const Text("Back", style: TextStyle(fontSize: 13)),
      );

  void _computeOccurrences({
    required ClientInfo info,
    required MembershipPlan plan,
    required List<Booking> bookings,
    required Trainer trainer,
  }) {
    final slot = _timeSlot;
    final remaining = (effectiveMaxSessions(info, plan) - sessionsUsedThisPeriod(info, plan, bookings)).clamp(0, 1 << 30);
    final noBudgetCap = isAssessmentType(_sessionType!);
    final weeksCount = _rangeChoice == "2w"
        ? 2
        : _rangeChoice == "4w"
            ? 4
            : (remaining / (_availableWeekdays.isEmpty ? 1 : _availableWeekdays.length)).ceil().clamp(1, 1 << 30);

    final candidates = <(String, int)>[];
    for (var w = 0; w < weeksCount; w++) {
      for (final wd in _availableWeekdays) {
        final date = occurrenceDate(isoToday(), wd, w);
        if (date.compareTo(isoToday()) >= 0) candidates.add((date, wd));
      }
    }
    candidates.sort((a, b) => a.$1.compareTo(b.$1));

    final provisional = [...bookings];
    var usedBudget = 0;
    _occurrences = candidates.map((c) {
      final atCap = bookedCount(provisional, trainer.id, c.$1, slot) >= capFor(_sessionType!);
      final budgetLeft = noBudgetCap ? true : (remaining - usedBudget) > 0;
      final check = canBookOffering(info, _sessionType!, provisional, c.$1, slot, plan);
      if (check.ok && !atCap && budgetLeft) {
        provisional.add(Booking(
          id: "",
          clientId: info.id,
          trainerId: trainer.id,
          date: c.$1,
          slot: slot,
          sessionType: _sessionType!,
          discipline: _discipline!,
        ));
        if (!noBudgetCap) usedBudget++;
        return _Occurrence(date: c.$1, weekday: c.$2, status: "bookable");
      }
      if (atCap) return _Occurrence(date: c.$1, weekday: c.$2, status: "full");
      return _Occurrence(date: c.$1, weekday: c.$2, status: "skipped", reason: !budgetLeft ? "No sessions left in your plan" : (check.msg ?? check.reason ?? "Unavailable"));
    }).toList();
  }

  Future<void> _confirm({required ClientInfo info, required Trainer trainer}) async {
    setState(() => _busy = true);
    final seriesId = const Uuid().v4();
    var booked = 0, waitlisted = 0;
    var skipped = _occurrences.where((o) => o.status == "skipped").length;
    for (final o in _occurrences) {
      if (o.status == "bookable") {
        final draft = Booking(
          id: "",
          clientId: info.id,
          trainerId: trainer.id,
          date: o.date,
          slot: _timeSlot,
          sessionType: _sessionType!,
          discipline: _discipline!,
        );
        try {
          final saved = await SupabaseService.insertBooking(draft);
          ref.read(clientBookingsProvider.notifier).addBooking(saved);
          ref.read(allBookingsProvider.notifier).addBooking(saved);
          booked++;
        } catch (_) {
          skipped++;
        }
      } else if (o.status == "full" && o.decision == "waitlist") {
        try {
          final entry = await SupabaseService.insertWaitlistEntry(WaitlistEntry(
            id: "",
            clientId: info.id,
            clientName: info.name,
            trainerId: trainer.id,
            trainerName: trainer.name,
            date: o.date,
            slot: _timeSlot,
            sessionType: _sessionType!,
            discipline: _discipline,
            status: "pending-approval",
            requestedAt: stamp(),
            seriesId: seriesId,
          ));
          ref.read(waitlistProvider.notifier).add(entry);
          waitlisted++;
        } catch (_) {
          skipped++;
        }
      } else if (o.status == "full") {
        skipped++;
      }
    }
    if (!mounted) return;
    setState(() {
      _summary = _Summary(booked: booked, waitlisted: waitlisted, skipped: skipped);
      _busy = false;
      _step = "summary";
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(clientInfoProvider);
    final trainers = ref.watch(trainersProvider);
    final bookings = ref.watch(clientBookingsProvider);
    final plan = ref.watch(membershipPlansProvider.notifier).byId(info.membershipPlanId);

    if (plan == null) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _breadcrumb(_back),
            const SizedBox(height: 10),
            const HintBox(text: "You need an active membership or package to use Advanced Booking."),
          ],
        ),
      );
    }

    switch (_step) {
      case "type":
        final allowed = plan.allowedTypes.isNotEmpty ? plan.allowedTypes : const ["semi-private", "one-on-one"];
        final options = kSessionTypeLabels.entries.where((e) => allowed.contains(e.key)).toList();
        return _StepScaffold(
          breadcrumb: _breadcrumb(_back),
          title: "Advanced Booking — session type",
          hint: "Set a weekly pattern and book multiple sessions at once.",
          children: options.map((e) => _OptionCard(
                label: e.value,
                onTap: () => setState(() {
                  _sessionType = e.key;
                  _discipline = null;
                  _step = "discipline";
                }),
              )).toList(),
        );

      case "discipline":
        final offered = <String>{};
        for (final t in trainers) {
          for (var wd = 0; wd <= 6; wd++) {
            for (final o in trainerOfferings(t, wd)) {
              if (o.sessionType == _sessionType) offered.add(o.discipline);
            }
          }
        }
        final options = kDisciplineLabels.entries.where((e) => offered.contains(e.key)).toList();
        return _StepScaffold(
          breadcrumb: _breadcrumb(() => setState(() => _step = "type")),
          title: "Discipline",
          children: options.isEmpty
              ? [HintBox(text: "No ${sessionTypeLabel(_sessionType!).toLowerCase()} sessions are set up yet.")]
              : options.map((e) => _OptionCard(label: e.value, onTap: () => setState(() {
                    _discipline = e.key;
                    _step = "coach";
                  }))).toList(),
        );

      case "coach":
        final offering = trainers.where((t) {
          for (var wd = 0; wd <= 6; wd++) {
            if (trainerOfferings(t, wd).any((o) => o.sessionType == _sessionType && o.discipline == _discipline)) return true;
          }
          return false;
        }).toList();
        return _StepScaffold(
          breadcrumb: _breadcrumb(() => setState(() => _step = "discipline")),
          title: "Choose your coach",
          children: offering.isEmpty
              ? [HintBox(text: "No coach currently offers ${disciplineLabel(_discipline!)}.")]
              : offering.map((t) => _OptionCard(
                    label: t.name,
                    onTap: () => setState(() {
                      _trainerId = t.id;
                      _step = "pattern";
                    }),
                    onMeetCoach: () => CoachProfileCard.show(context, t),
                  )).toList(),
        );

      case "pattern":
        final trainer = _trainerOf(trainers);
        return StatefulBuilder(builder: (context, setLocalState) {
          void toggleDay(int d) => setState(() {
                if (_days.contains(d)) {
                  _days.remove(d);
                } else {
                  _days.add(d);
                }
              });
          return SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _breadcrumb(() => setState(() => _step = "coach")),
                const SizedBox(height: 10),
                const SectionLabel("Set your weekly pattern"),
                Text(
                  "${sessionTypeLabel(_sessionType!)} · ${disciplineLabel(_discipline!)} · ${trainer?.name ?? ""}",
                  style: const TextStyle(fontSize: 12, color: AppColors.mute),
                ),
                const SizedBox(height: 16),
                const Text("Days of the week", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _kWeekdayOptions.map((opt) {
                    final on = _days.contains(opt.$1);
                    return InkWell(
                      onTap: () => toggleDay(opt.$1),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: on ? AppColors.gold : AppColors.line),
                          color: on ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg,
                        ),
                        child: Text(opt.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? AppColors.gold : AppColors.mute)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text("Time", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: _timeSlot ~/ 60, minute: _timeSlot % 60),
                    );
                    if (picked != null) setState(() => _timeSlot = picked.hour * 60 + picked.minute);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(8)),
                    child: Text(fmtSlot(_timeSlot), style: const TextStyle(fontSize: 14, color: AppColors.txt)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    "Any time — if ${trainer?.name ?? "your coach"} doesn't normally teach at this time on a chosen day, we'll flag it before booking anything.",
                    style: const TextStyle(fontSize: 11, color: AppColors.mute),
                  ),
                ),
                const SizedBox(height: 16),
                BtnGold(
                  onPressed: _days.isEmpty ? null : () => setState(() => _step = "range"),
                  full: true,
                  child: const Text("Next"),
                ),
              ],
            ),
          );
        });

      case "range":
        final remaining = (effectiveMaxSessions(info, plan) - sessionsUsedThisPeriod(info, plan, bookings)).clamp(0, 1 << 30);
        void chooseRange(String choice) {
          final trainer = _trainerOf(trainers);
          if (trainer == null) return;
          final avail = <int>[], unavail = <int>[];
          for (final wd in _days) {
            final offered = trainerOfferings(trainer, wd).any((o) => o.sessionType == _sessionType && o.discipline == _discipline && o.slot == _timeSlot);
            (offered ? avail : unavail).add(wd);
          }
          setState(() {
            _rangeChoice = choice;
            _availableWeekdays = avail;
            _unavailableWeekdays = unavail;
            if (unavail.isNotEmpty) {
              _step = "gate";
            } else {
              _occurrences = [];
              if (avail.isNotEmpty) _computeOccurrences(info: info, plan: plan, bookings: bookings, trainer: trainer);
              _step = "review";
            }
          });
        }

        return _StepScaffold(
          breadcrumb: _breadcrumb(() => setState(() => _step = "pattern")),
          title: "How far out?",
          hint: "You have $remaining session${remaining != 1 ? "s" : ""} remaining on ${plan.name}.",
          children: [
            _OptionCard(label: "2 weeks", onTap: () => chooseRange("2w")),
            _OptionCard(label: "4 weeks", onTap: () => chooseRange("4w")),
            _OptionCard(
              label: "Full membership",
              sub: "Books out as many of your $remaining remaining session${remaining != 1 ? "s" : ""} as your pattern allows.",
              disabled: remaining <= 0,
              onTap: remaining <= 0 ? null : () => chooseRange("full"),
            ),
          ],
        );

      case "gate":
        final dayLabels = _unavailableWeekdays.map((wd) => _kWeekdayOptions.firstWhere((o) => o.$1 == wd).$2).join("/");
        final trainer = _trainerOf(trainers);
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 40, 18, 18),
          child: Column(
            children: [
              const Icon(LucideIcons.circleSlash, size: 36, color: Color(0xFFD68A4F)),
              const SizedBox(height: 16),
              Text("$dayLabels at ${fmtSlot(_timeSlot)} isn't available", style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  "${trainer?.name ?? "Your coach"} doesn't teach ${sessionTypeLabel(_sessionType!)} · ${disciplineLabel(_discipline!)} at that time on $dayLabels."
                  "${_availableWeekdays.isNotEmpty ? " You can continue with your other selected days, or cancel this request." : " None of your selected days are available with this coach at this time."}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.mute, height: 1.6),
                ),
              ),
              const SizedBox(height: 26),
              if (_availableWeekdays.isNotEmpty)
                BtnGold(
                  full: true,
                  onPressed: () {
                    if (trainer == null) return;
                    setState(() {
                      _occurrences = [];
                      _computeOccurrences(info: info, plan: plan, bookings: bookings, trainer: trainer);
                      _step = "review";
                    });
                  },
                  child: Text("Continue without $dayLabels"),
                ),
              const SizedBox(height: 10),
              BtnGhost(full: true, onPressed: _back, child: const Text("Cancel request")),
            ],
          ),
        );

      case "review":
        final trainer = _trainerOf(trainers);
        final bookableCount = _occurrences.where((o) => o.status == "bookable").length;
        final fullOnes = _occurrences.where((o) => o.status == "full").toList();
        final unresolvedFull = fullOnes.any((o) => o.decision == null);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _breadcrumb(_back),
              const SizedBox(height: 10),
              SectionLabel("Review — ${_occurrences.length} session${_occurrences.length != 1 ? "s" : ""} in range"),
              Text(
                "${sessionTypeLabel(_sessionType!)} · ${disciplineLabel(_discipline!)} · ${trainer?.name ?? ""} · ${fmtSlot(_timeSlot)}",
                style: const TextStyle(fontSize: 12, color: AppColors.mute),
              ),
              const SizedBox(height: 14),
              if (_occurrences.isEmpty)
                const HintBox(text: "No sessions in range.")
              else
                ..._occurrences.map((o) {
                  return AppCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(o.date, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              if (o.status == "bookable")
                                const Padding(padding: EdgeInsets.only(top: 2), child: Text("✓ Will be booked", style: TextStyle(fontSize: 11, color: Color(0xFF4EC97A)))),
                              if (o.status == "skipped")
                                Padding(padding: const EdgeInsets.only(top: 2), child: Text("Skipped — ${o.reason}", style: const TextStyle(fontSize: 11, color: AppColors.mute))),
                              if (o.status == "full")
                                const Padding(padding: EdgeInsets.only(top: 2), child: Text("Session is full", style: TextStyle(fontSize: 11, color: Color(0xFFD68A4F)))),
                            ],
                          ),
                        ),
                        if (o.status == "full") ...[
                          _DecisionChip(
                            label: "Request waitlist",
                            selected: o.decision == "waitlist",
                            color: AppColors.gold,
                            onTap: () => setState(() => o.decision = "waitlist"),
                          ),
                          const SizedBox(width: 6),
                          _DecisionChip(
                            label: "Skip this session",
                            selected: o.decision == "skip",
                            color: const Color(0xFFC97F7F),
                            onTap: () => setState(() => o.decision = "skip"),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              if (fullOnes.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 4, bottom: 4), child: HintBox(text: "Waitlist requests need the owner's approval before they're confirmed bookings.")),
              const SizedBox(height: 14),
              BtnGold(
                full: true,
                onPressed: (_busy || _occurrences.isEmpty || unresolvedFull || trainer == null) ? null : () => _confirm(info: info, trainer: trainer),
                child: Text(_busy ? "Booking…" : unresolvedFull ? "Resolve full sessions above" : "Confirm $bookableCount booking${bookableCount != 1 ? "s" : ""}"),
              ),
            ],
          ),
        );

      case "summary":
        final s = _summary;
        if (s == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 40, 18, 18),
          child: Column(
            children: [
              const Icon(LucideIcons.check, size: 36, color: AppColors.gold),
              const SizedBox(height: 16),
              const Text("Advanced Booking complete", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text("✓ ${s.booked} session${s.booked != 1 ? "s" : ""} booked", style: const TextStyle(fontSize: 13))),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text("⏳ ${s.waitlisted} waitlist request${s.waitlisted != 1 ? "s" : ""} submitted — pending owner approval", style: const TextStyle(fontSize: 13)),
                    ),
                    if (s.skipped > 0)
                      Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text("— ${s.skipped} skipped", style: const TextStyle(fontSize: 13, color: AppColors.mute))),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              BtnGold(full: true, onPressed: _back, child: const Text("Done")),
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({required this.breadcrumb, required this.title, this.hint, required this.children});
  final Widget breadcrumb;
  final String title;
  final String? hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          breadcrumb,
          const SizedBox(height: 10),
          SectionLabel(title),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, style: const TextStyle(fontSize: 12, color: AppColors.mute)),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.label, this.sub, this.onTap, this.disabled = false, this.onMeetCoach});
  final String label;
  final String? sub;
  final VoidCallback? onTap;
  final bool disabled;
  final VoidCallback? onMeetCoach;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: AppCard(
        onTap: onTap,
        margin: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: const TextStyle(fontSize: 11, color: AppColors.mute))),
            if (onMeetCoach != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: GestureDetector(
                  onTap: onMeetCoach,
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
    );
  }
}

class _DecisionChip extends StatelessWidget {
  const _DecisionChip({required this.label, required this.selected, required this.color, required this.onTap});
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : AppColors.line),
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? color : AppColors.mute)),
      ),
    );
  }
}
