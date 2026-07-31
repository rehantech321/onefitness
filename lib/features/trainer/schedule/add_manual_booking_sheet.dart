import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/utils/scheduling_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/client_info.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
import "client_search_picker.dart";

const _sessionTypes = ["semi-private", "one-on-one", "large-group", "assessment-call", "assessment-in-person"];
const _disciplines = ["personal-training", "boxing", "hike", "outdoor-hiit", "stretch", "stick-mobility", "yoga"];

/// Mirrors AddManualBookingModal.jsx — the coach/owner "book anything" tool.
/// Bypasses client-facing availability/membership gating on purpose, but
/// still enforces the trainer double-booking and capacity checks; the
/// owner may push past those with a confirmation, a coach cannot.
Future<void> showAddManualBookingSheet(BuildContext context, WidgetRef ref, {required String initialDate}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _AddManualBookingBody(initialDate: initialDate),
    ),
  );
}

class _AddManualBookingBody extends ConsumerStatefulWidget {
  const _AddManualBookingBody({required this.initialDate});
  final String initialDate;

  @override
  ConsumerState<_AddManualBookingBody> createState() => _AddManualBookingBodyState();
}

class _AddManualBookingBodyState extends ConsumerState<_AddManualBookingBody> {
  ClientInfo? _client;
  bool _picking = true;
  String? _trainerId;
  String _sessionType = "semi-private";
  String _discipline = "personal-training";
  late final _date = TextEditingController(text: widget.initialDate);
  final _time = TextEditingController(text: "09:00");
  String? _error;

  @override
  void dispose() {
    _date.dispose();
    _time.dispose();
    super.dispose();
  }

  int? get _slotMinutes {
    final parts = _time.text.split(":");
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(trainerRosterProvider);
    final trainers = ref.watch(trainersProvider);
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    _trainerId ??= isOwner ? (trainers.isNotEmpty ? trainers.first.id : null) : trainerAuth;
    final isAssessment = _sessionType.startsWith("assessment");

    if (_picking) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel("Book a Session"),
            ClientSearchPicker(roster: roster, onSelect: (c) => setState(() {
                  _client = c;
                  _picking = false;
                })),
          ],
        ),
      );
    }

    final bookings = ref.watch(allBookingsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(name: _client!.name, size: 32),
              const SizedBox(width: 10),
              Expanded(child: Text(_client!.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              TextButton(onPressed: () => setState(() => _picking = true), child: const Text("Change", style: TextStyle(fontSize: 12))),
            ],
          ),
          const SizedBox(height: 14),
          if (isOwner) ...[
            const Text("COACH", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
            const SizedBox(height: 6),
            _ChoiceRow<String>(value: _trainerId, options: trainers.map((t) => (t.id, t.name)).toList(), onChanged: (v) => setState(() => _trainerId = v)),
            const SizedBox(height: 12),
          ],
          const Text("SESSION TYPE", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 6),
          _ChoiceRow<String>(value: _sessionType, options: _sessionTypes.map((t) => (t, sessionTypeLabel(t))).toList(), onChanged: (v) => setState(() => _sessionType = v ?? _sessionType)),
          if (!isAssessment) ...[
            const SizedBox(height: 12),
            const Text("DISCIPLINE", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
            const SizedBox(height: 6),
            _ChoiceRow<String>(value: _discipline, options: _disciplines.map((d) => (d, disciplineLabel(d))).toList(), onChanged: (v) => setState(() => _discipline = v ?? _discipline)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: FieldLabeled(label: "Date (YYYY-MM-DD)", child: AppField(controller: _date))),
              const SizedBox(width: 8),
              Expanded(child: FieldLabeled(label: "Time (HH:MM, 24h)", child: AppField(controller: _time))),
            ],
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12))),
          const SizedBox(height: 16),
          BtnGold(
            full: true,
            onPressed: () {
              final slot = _slotMinutes;
              final trainerId = _trainerId;
              if (slot == null || trainerId == null || _date.text.trim().isEmpty) {
                setState(() => _error = "Coach, date, and time are all required.");
                return;
              }
              final effectiveDiscipline = isAssessment ? "programmer" : _discipline;
              final conflict = findTrainerConflict(bookings, trainerId, _date.text.trim(), slot, _sessionType, effectiveDiscipline);
              if (conflict != null && !isOwner) {
                setState(() => _error = "This coach already has a different session at that time — contact the owner to override.");
                return;
              }
              final cap = capacityInfo(bookings, trainerId, _date.text.trim(), slot, _sessionType);
              if (cap.atCap && conflict == null && !isOwner) {
                setState(() => _error = "That session is already at capacity (${cap.cap}) — contact the owner to override.");
                return;
              }
              ref.read(allBookingsProvider.notifier).addBooking(Booking(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    clientId: _client!.id,
                    trainerId: trainerId,
                    date: _date.text.trim(),
                    slot: slot,
                    sessionType: _sessionType,
                    discipline: effectiveDiscipline,
                    isPhysicalAssessment: isAssessment,
                  ));
              Navigator.of(context).pop();
            },
            child: const Text("Book session"),
          ),
        ],
      ),
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({required this.value, required this.options, required this.onChanged});
  final T? value;
  final List<(T, String)> options;
  final ValueChanged<T?> onChanged;

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
