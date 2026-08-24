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
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";

const _kWeekdayOptions = [(1, "Mon"), (2, "Tue"), (3, "Wed"), (4, "Thu"), (5, "Fri"), (6, "Sat")]; // Sunday closed, same as everywhere else

/// One "days of the week + time" combination — the client can stack
/// several of these (e.g. "Mon/Wed 6am" + "Fri 5pm") instead of a single
/// shared time across every chosen day.
class _Bracket {
  _Bracket({List<int>? days, this.time = 9 * 60}) : days = days ?? [];
  final List<int> days;
  int time;
}

class _Occurrence {
  _Occurrence({required this.date, required this.weekday, required this.slot, required this.status, this.reason, this.decision, this.trainerId});
  final String date;
  final int weekday;
  final int slot;
  String status; // "bookable" | "full" | "skipped"
  String? reason;
  String? decision; // "waitlist" | "skip" — "full" only
  String? trainerId; // set once resolved (auto-matched coach), null while "full"/"skipped"
}

class _Summary {
  const _Summary({required this.booked, required this.waitlisted, required this.skipped});
  final int booked;
  final int waitlisted;
  final int skipped;
}

/// Mirrors AdvancedBookingFlow.jsx — set a weekly pattern (one or more
/// day/time brackets) and book every matching occurrence over a chosen
/// range at once, instead of picking one session at a time. Diverges from
/// the web source by design, per product direction: no explicit "choose
/// your coach" step — the client's own city (already collected at
/// signup) narrows which coaches are considered, and each occurrence
/// auto-matches whichever eligible coach actually teaches that day/time
/// and has room, the same way the regular (non-advanced) booking screen
/// already shows a coach per slot rather than asking upfront. A full slot
/// can still be requested for the owner's waitlist ("pending-approval")
/// rather than skipped outright.
class AdvancedBookingScreen extends ConsumerStatefulWidget {
  const AdvancedBookingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<AdvancedBookingScreen> createState() => _AdvancedBookingScreenState();
}

class _AdvancedBookingScreenState extends ConsumerState<AdvancedBookingScreen> {
  String _step = "type"; // type | discipline | pattern | range | review | summary
  String? _sessionType;
  String? _discipline;
  List<Trainer> _eligibleTrainers = [];
  final List<_Bracket> _brackets = [_Bracket()];
  String? _rangeChoice;
  List<_Occurrence> _occurrences = [];
  bool _busy = false;
  _Summary? _summary;

  void _back() => widget.onDone();

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

  /// Narrows to coaches in the client's own city offering this session
  /// type + discipline at all — "city auto-detected" replaces the old
  /// explicit coach picker. Falls back to every coach offering it if the
  /// client has no city on file, or none of them match it, rather than
  /// hard-blocking booking over a missing/mistyped city string.
  List<Trainer> _matchCoaches(List<Trainer> trainers, String? city) {
    bool offersIt(Trainer t) {
      for (var wd = 0; wd <= 6; wd++) {
        if (trainerOfferings(t, wd).any((o) => o.sessionType == _sessionType && o.discipline == _discipline)) return true;
      }
      return false;
    }

    final offering = trainers.where(offersIt).toList();
    if (city == null || city.trim().isEmpty) return offering;
    final inCity = offering.where((t) {
      final trainerCity = cityFromAddress(t.locationAddress);
      return trainerCity != null && trainerCity.trim().toLowerCase() == city.trim().toLowerCase();
    }).toList();
    return inCity.isNotEmpty ? inCity : offering;
  }

  void _computeOccurrences({required ClientInfo info, required MembershipPlan plan, required List<Booking> bookings}) {
    final settings = ref.read(platformSettingsProvider);
    final remaining = (effectiveMaxSessions(info, plan) - sessionsUsedThisPeriod(info, plan, bookings)).clamp(0, 1 << 30);
    final noBudgetCap = isAssessmentType(_sessionType!);
    final totalWeeklySlots = _brackets.fold<int>(0, (sum, b) => sum + b.days.length);
    final weeksCount = _rangeChoice == "2w"
        ? 2
        : _rangeChoice == "4w"
            ? 4
            : (remaining / (totalWeeklySlots == 0 ? 1 : totalWeeklySlots)).ceil().clamp(1, 1 << 30);

    final today = isoToday();
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final candidates = <(String, int, int)>[]; // date, weekday, slot
    for (var w = 0; w < weeksCount; w++) {
      for (final bracket in _brackets) {
        for (final wd in bracket.days) {
          final date = occurrenceDate(isoToday(), wd, w);
          final dateCmp = date.compareTo(today);
          // Today's own already-started/passed slots can't be booked —
          // any other future date has no such restriction.
          if (dateCmp > 0 || (dateCmp == 0 && bracket.time > nowMin)) candidates.add((date, wd, bracket.time));
        }
      }
    }
    candidates.sort((a, b) {
      final byDate = a.$1.compareTo(b.$1);
      return byDate != 0 ? byDate : a.$3.compareTo(b.$3);
    });

    final provisional = [...bookings];
    var usedBudget = 0;
    _occurrences = candidates.map((c) {
      final date = c.$1, weekday = c.$2, slot = c.$3;

      Trainer? match;
      var anyOffered = false;
      for (final t in _eligibleTrainers) {
        final offers = trainerOfferings(t, weekday).any((o) => o.sessionType == _sessionType && o.discipline == _discipline && o.slot == slot);
        if (!offers) continue;
        anyOffered = true;
        if (bookedCount(provisional, t.id, date, slot) < capFor(_sessionType!, semiPrivateCap: settings.semiPrivateCap)) {
          match = t;
          break;
        }
      }

      if (match == null) {
        if (!anyOffered) {
          return _Occurrence(date: date, weekday: weekday, slot: slot, status: "skipped", reason: "No coach offers this at that time");
        }
        return _Occurrence(date: date, weekday: weekday, slot: slot, status: "full");
      }

      final budgetLeft = noBudgetCap ? true : (remaining - usedBudget) > 0;
      final check = canBookOffering(
        info,
        _sessionType!,
        provisional,
        date,
        slot,
        plan,
        minBookingLeadHours: settings.minBookingLeadHours,
        maxBookingHorizonDays: settings.maxBookingHorizonDays,
      );
      if (check.ok && budgetLeft) {
        provisional.add(Booking(id: "", clientId: info.id, trainerId: match.id, date: date, slot: slot, sessionType: _sessionType!, discipline: _discipline!));
        if (!noBudgetCap) usedBudget++;
        return _Occurrence(date: date, weekday: weekday, slot: slot, status: "bookable", trainerId: match.id);
      }
      return _Occurrence(date: date, weekday: weekday, slot: slot, status: "skipped", reason: !budgetLeft ? "No sessions left in your plan" : (check.msg ?? check.reason ?? "Unavailable"));
    }).toList();
  }

  Future<void> _confirm({required ClientInfo info, required List<Trainer> trainers}) async {
    setState(() => _busy = true);
    final seriesId = const Uuid().v4();
    var booked = 0, waitlisted = 0;
    var skipped = _occurrences.where((o) => o.status == "skipped").length;
    for (final o in _occurrences) {
      if (o.status == "bookable" && o.trainerId != null) {
        final draft = Booking(id: "", clientId: info.id, trainerId: o.trainerId!, date: o.date, slot: o.slot, sessionType: _sessionType!, discipline: _discipline!);
        try {
          final saved = await SupabaseService.insertBooking(draft);
          ref.read(clientBookingsProvider.notifier).addBooking(saved);
          ref.read(allBookingsProvider.notifier).addBooking(saved);
          booked++;
        } catch (_) {
          skipped++;
        }
      } else if (o.status == "full" && o.decision == "waitlist") {
        // A "full" occurrence never resolved to a specific coach — request
        // the waitlist against whichever eligible coach actually teaches
        // this slot (there's always at least one, or it would have been
        // "skipped" instead).
        Trainer? anyTeaching;
        for (final t in _eligibleTrainers) {
          if (trainerOfferings(t, o.weekday).any((of) => of.sessionType == _sessionType && of.discipline == _discipline && of.slot == o.slot)) {
            anyTeaching = t;
            break;
          }
        }
        if (anyTeaching == null) {
          skipped++;
          continue;
        }
        try {
          final entry = await SupabaseService.insertWaitlistEntry(WaitlistEntry(
            id: "",
            clientId: info.id,
            clientName: info.name,
            trainerId: anyTeaching.id,
            trainerName: anyTeaching.name,
            date: o.date,
            slot: o.slot,
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
              : options.map((e) => _OptionCard(
                    label: e.value,
                    onTap: () => setState(() {
                      _discipline = e.key;
                      _eligibleTrainers = _matchCoaches(trainers, info.city);
                      _brackets
                        ..clear()
                        ..add(_Bracket());
                      _step = "pattern";
                    }),
                  )).toList(),
        );

      case "pattern":
        if (_eligibleTrainers.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _breadcrumb(() => setState(() => _step = "discipline")),
                const SizedBox(height: 10),
                HintBox(text: "No coach currently offers ${disciplineLabel(_discipline!)}."),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _breadcrumb(() => setState(() => _step = "discipline")),
              const SizedBox(height: 10),
              const SectionLabel("Set your weekly pattern"),
              Text(
                "${sessionTypeLabel(_sessionType!)} · ${disciplineLabel(_discipline!)} · ${info.city?.trim().isNotEmpty == true ? info.city : "Any location"}",
                style: const TextStyle(fontSize: 12, color: AppColors.mute),
              ),
              const SizedBox(height: 16),
              ..._brackets.asMap().entries.map((entry) => _BracketEditor(
                    index: entry.key,
                    bracket: entry.value,
                    canRemove: _brackets.length > 1,
                    onChanged: () => setState(() {}),
                    onRemove: () => setState(() => _brackets.removeAt(entry.key)),
                  )),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: TextButton.icon(
                  onPressed: () => setState(() => _brackets.add(_Bracket())),
                  style: TextButton.styleFrom(foregroundColor: AppColors.gold, padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                  icon: const Icon(LucideIcons.plus, size: 15),
                  label: const Text("Add Another Bracket", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 16),
                child: Text(
                  "Any time — if it isn't normally taught on a chosen day, we'll auto-match you with another coach or flag it before booking anything.",
                  style: TextStyle(fontSize: 11, color: AppColors.mute),
                ),
              ),
              BtnGold(
                onPressed: _brackets.any((b) => b.days.isNotEmpty) ? () => setState(() => _step = "range") : null,
                full: true,
                child: const Text("Next"),
              ),
            ],
          ),
        );

      case "range":
        final remaining = (effectiveMaxSessions(info, plan) - sessionsUsedThisPeriod(info, plan, bookings)).clamp(0, 1 << 30);
        void chooseRange(String choice) {
          setState(() {
            _rangeChoice = choice;
            _occurrences = [];
            _computeOccurrences(info: info, plan: plan, bookings: bookings);
            _step = "review";
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

      case "review":
        final bookableCount = _occurrences.where((o) => o.status == "bookable").length;
        final fullOnes = _occurrences.where((o) => o.status == "full").toList();
        final unresolvedFull = fullOnes.any((o) => o.decision == null);
        Trainer? trainerFor(String? id) {
          if (id == null) return null;
          final m = trainers.where((t) => t.id == id);
          return m.isNotEmpty ? m.first : null;
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _breadcrumb(_back),
              const SizedBox(height: 10),
              SectionLabel("Review — ${_occurrences.length} session${_occurrences.length != 1 ? "s" : ""} in range"),
              Text(
                "${sessionTypeLabel(_sessionType!)} · ${disciplineLabel(_discipline!)}",
                style: const TextStyle(fontSize: 12, color: AppColors.mute),
              ),
              const SizedBox(height: 14),
              if (_occurrences.isEmpty)
                const HintBox(text: "No sessions in range.")
              else
                ..._occurrences.map((o) {
                  final coach = trainerFor(o.trainerId);
                  return AppCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("${o.date} · ${fmtSlot(o.slot)}", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              if (o.status == "bookable")
                                Padding(padding: const EdgeInsets.only(top: 2), child: Text("✓ Will be booked${coach != null ? " with ${coach.name}" : ""}", style: const TextStyle(fontSize: 11, color: Color(0xFF4EC97A)))),
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
                onPressed: (_busy || _occurrences.isEmpty || unresolvedFull) ? null : () => _confirm(info: info, trainers: trainers),
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
  const _OptionCard({required this.label, this.sub, this.onTap, this.disabled = false});
  final String label;
  final String? sub;
  final VoidCallback? onTap;
  final bool disabled;

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

/// One day/time bracket's editor — days-of-week chips + a time field,
/// mirroring the pattern step's original single-bracket UI, repeated once
/// per bracket the client has added.
class _BracketEditor extends StatelessWidget {
  const _BracketEditor({required this.index, required this.bracket, required this.canRemove, required this.onChanged, required this.onRemove});
  final int index;
  final _Bracket bracket;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    void toggleDay(int d) {
      if (bracket.days.contains(d)) {
        bracket.days.remove(d);
      } else {
        bracket.days.add(d);
      }
      onChanged();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Bracket ${index + 1}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.mute)),
              if (canRemove)
                InkWell(
                  onTap: onRemove,
                  child: const Text("Remove", style: TextStyle(fontSize: 11, color: AppColors.errorText, decoration: TextDecoration.underline)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text("Days of the week", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _kWeekdayOptions.map((opt) {
              final on = bracket.days.contains(opt.$1);
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
          const SizedBox(height: 12),
          const Text("Time", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Builder(builder: (context) {
            return InkWell(
              onTap: () async {
                final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: bracket.time ~/ 60, minute: bracket.time % 60));
                if (picked != null) {
                  bracket.time = picked.hour * 60 + picked.minute;
                  onChanged();
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(8)),
                child: Text(fmtSlot(bracket.time), style: const TextStyle(fontSize: 14, color: AppColors.txt)),
              ),
            );
          }),
        ],
      ),
    );
  }
}
