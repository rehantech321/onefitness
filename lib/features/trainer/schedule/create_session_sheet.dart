import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/availability_block.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";
import "../shell/trainer_shell_state.dart";
import "coach_search_picker.dart";

const _sessionTypes = ["semi-private", "one-on-one", "large-group"];
const _disciplines = ["personal-training", "boxing", "hike", "outdoor-hiit", "stretch", "stick-mobility", "yoga"];

/// One time window a session will run at. [end] null means one hour.
class _TimeEntry {
  _TimeEntry({required this.start});
  int start;
  int? end;
  int get durationMin => (end ?? start + 60) - start;
}

/// Owner's "Create session": publishes bookable sessions for a coach on one
/// or more specific dates and times, without a client attached. Clients
/// then see them in Booking like any other slot, and staff can add a client
/// from the day view.
///
/// Stored as date-specific entries on the coach's availability blocks (see
/// AvailabilityBlock.dates) rather than as bookings — a booking needs a
/// client, and a session nobody has booked yet has none.
Future<void> showCreateSessionSheet(BuildContext context, WidgetRef ref, {required String initialDate}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _CreateSessionBody(initialDate: initialDate),
    ),
  );
}

class _CreateSessionBody extends ConsumerStatefulWidget {
  const _CreateSessionBody({required this.initialDate});
  final String initialDate;

  @override
  ConsumerState<_CreateSessionBody> createState() => _CreateSessionBodyState();
}

class _CreateSessionBodyState extends ConsumerState<_CreateSessionBody> {
  String _sessionType = "semi-private";
  String _discipline = "personal-training";
  Trainer? _trainer;
  bool _pickingCoach = false;
  late final List<String> _dates = [
    // Never in the past — a tapped calendar day that's gone is bumped to today.
    widget.initialDate.compareTo(isoToday()) < 0 ? isoToday() : widget.initialDate,
  ];
  final List<_TimeEntry> _times = [_TimeEntry(start: 9 * 60)];
  String? _error;
  bool _saving = false;

  Future<void> _addDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(context: context, initialDate: first, firstDate: first, lastDate: DateTime(now.year + 2));
    if (picked == null) return;
    final iso = isoDate(picked);
    if (!_dates.contains(iso)) setState(() => _dates.add(iso));
  }

  Future<void> _addTime() async {
    final last = _times.isEmpty ? 9 * 60 : _times.last.start + 60;
    final picked = await pickTime12h(context, initialMinutes: last);
    if (picked != null) setState(() => _times.add(_TimeEntry(start: picked)));
  }

  /// Merges the new sessions into the coach's availability. Same type +
  /// discipline + duration share a block so the coach's availability list
  /// stays readable; a different duration gets its own block.
  List<AvailabilityBlock> _merged(List<AvailabilityBlock> existing) {
    final blocks = [...existing];
    final byDuration = <int, List<int>>{};
    for (final t in _times) {
      byDuration.putIfAbsent(t.durationMin, () => []).add(t.start);
    }
    byDuration.forEach((duration, starts) {
      final i = blocks.indexWhere((b) => b.sessionType == _sessionType && b.discipline == _discipline && b.durationMin == duration);
      final base = i >= 0 ? blocks[i] : AvailabilityBlock(sessionType: _sessionType, discipline: _discipline, byDay: const {}, durationMin: duration);
      final dates = {for (final e in base.dates.entries) e.key: [...e.value]};
      for (final d in _dates) {
        final list = dates.putIfAbsent(d, () => []);
        for (final s in starts) {
          if (!list.contains(s)) list.add(s);
        }
        list.sort();
      }
      final next = base.copyWith(dates: dates);
      if (i >= 0) {
        blocks[i] = next;
      } else {
        blocks.add(next);
      }
    });
    return blocks;
  }

  Future<void> _save() async {
    final trainer = _trainer;
    if (trainer == null) {
      setState(() => _error = "Choose a coach.");
      return;
    }
    if (_dates.isEmpty || _times.isEmpty) {
      setState(() => _error = "Add at least one date and one time.");
      return;
    }
    for (final t in _times) {
      if (t.durationMin <= 0) {
        setState(() => _error = "End time must be after start time.");
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final availability = _merged(trainer.availability);
    try {
      await SupabaseService.updateTrainerRow(trainer.id, availability: availability);
      ref.read(trainersProvider.notifier).upsert(trainer.copyWith(availability: availability));
      if (!mounted) return;
      final n = _dates.length * _times.length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$n session${n == 1 ? '' : 's'} created for ${trainer.name}.")));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't save — check your connection and try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trainers = ref.watch(trainersProvider);
    final isOwner = ref.watch(trainerAuthProvider) == "owner";
    // Customize Platform → Services decides what's offered; a type or
    // discipline switched off there isn't on the menu here.
    final settings = ref.watch(platformSettingsProvider);
    final types = _sessionTypes.where(settings.offeredSessionTypes.contains).toList();
    final disciplines = _disciplines.where(settings.offeredDisciplines.contains).toList();

    if (_pickingCoach) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _pickingCoach = false);
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BackBar(onBack: () => setState(() => _pickingCoach = false), title: "Choose a coach"),
              const SizedBox(height: 10),
              CoachSearchPicker(
                trainers: trainers,
                selectedId: _trainer?.id,
                onSelect: (t) => setState(() {
                  _trainer = t;
                  _pickingCoach = false;
                }),
                // Adding a coach is the Staff screen's job — this closes the
                // sheet and lands there, so the owner can come straight back
                // to Create session once the coach exists.
                onCreateCoach: isOwner
                    ? () {
                        Navigator.of(context).pop();
                        ref.read(trainerModeProvider.notifier).go("staff");
                      }
                    : null,
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Create Session"),
          const SizedBox(height: 4),
          const Text(
            "Publishes a bookable session for a coach. Clients can book it, or you can add a client to it from the day view.",
            style: TextStyle(fontSize: 12, color: AppColors.mute, height: 1.4),
          ),
          const SizedBox(height: 14),
          const Text("SESSION TYPE", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 6),
          _Chips(value: _sessionType, options: types.map((t) => (t, sessionTypeLabel(t))).toList(), onChanged: (v) => setState(() => _sessionType = v)),
          const SizedBox(height: 12),
          const Text("DISCIPLINE", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 6),
          _Chips(value: _discipline, options: disciplines.map((d) => (d, disciplineLabel(d))).toList(), onChanged: (v) => setState(() => _discipline = v)),
          const SizedBox(height: 12),
          const Text("COACH", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => setState(() => _pickingCoach = true),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  if (_trainer != null) ...[Avatar(name: _trainer!.name, size: 26), const SizedBox(width: 8)],
                  Expanded(
                    child: Text(
                      _trainer?.displayTitle ?? "Search for a coach…",
                      style: TextStyle(fontSize: 14, color: _trainer == null ? AppColors.mute : AppColors.txt),
                    ),
                  ),
                  const Icon(LucideIcons.search, size: 15, color: AppColors.mute),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _ListHeader(label: "DATES", action: "Add date", onAdd: _addDate),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in _dates)
                _Pill(
                  label: dayLabel(d),
                  onRemove: _dates.length > 1 ? () => setState(() => _dates.remove(d)) : null,
                ),
            ],
          ),
          const SizedBox(height: 14),
          _ListHeader(label: "TIMES", action: "Add time", onAdd: _addTime),
          const SizedBox(height: 6),
          for (final t in _times)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TimeField(minutes: t.start, onChanged: (v) => setState(() => t.start = v)),
                  ),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("to", style: TextStyle(color: AppColors.mute, fontSize: 12))),
                  Expanded(
                    child: TimeField(
                      minutes: t.end,
                      placeholder: "${fmtSlot(t.start + 60)} (1 hr)",
                      initialWhenEmpty: t.start + 60,
                      onChanged: (v) => setState(() => t.end = v),
                      onClear: () => setState(() => t.end = null),
                    ),
                  ),
                  if (_times.length > 1)
                    IconButton(
                      onPressed: () => setState(() => _times.remove(t)),
                      icon: const Icon(LucideIcons.x, size: 15, color: AppColors.mute),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    ),
                ],
              ),
            ),
          const Text(
            "Leave the end time blank for a one-hour session.",
            style: TextStyle(fontSize: 11, color: AppColors.mute, fontStyle: FontStyle.italic),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12))),
          const SizedBox(height: 16),
          BtnGold(
            full: true,
            onPressed: _saving ? null : _save,
            child: Text(_saving ? "Creating…" : "Create session${_dates.length * _times.length == 1 ? '' : 's'}"),
          ),
        ],
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.label, required this.action, required this.onAdd});
  final String label;
  final String action;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
        TextButton.icon(
          onPressed: onAdd,
          style: TextButton.styleFrom(foregroundColor: AppColors.gold, padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero),
          icon: const Icon(LucideIcons.plus, size: 13),
          label: Text(action, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.onRemove});
  final String label;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.goldDim),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.gold)),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            InkWell(onTap: onRemove, child: const Icon(LucideIcons.x, size: 13, color: AppColors.gold)),
          ],
        ],
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.value, required this.options, required this.onChanged});
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((o) {
        final selected = value == o.$1;
        return InkWell(
          onTap: () => onChanged(o.$1),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg,
              border: Border.all(color: selected ? AppColors.gold : AppColors.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(o.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? AppColors.gold : AppColors.txt)),
          ),
        );
      }).toList(),
    );
  }
}
