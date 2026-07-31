import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/blocked_time.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors BlockTimeForm.jsx — blocking never fails or force-cancels
/// existing bookings; overlapping bookings are shown as a non-blocking FYI.
Future<void> showBlockTimeSheet(BuildContext context, WidgetRef ref, {required String date, required String trainerId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _BlockTimeBody(date: date, trainerId: trainerId),
    ),
  );
}

class _BlockTimeBody extends ConsumerStatefulWidget {
  const _BlockTimeBody({required this.date, required this.trainerId});
  final String date;
  final String trainerId;

  @override
  ConsumerState<_BlockTimeBody> createState() => _BlockTimeBodyState();
}

class _BlockTimeBodyState extends ConsumerState<_BlockTimeBody> {
  late String _trainerId = widget.trainerId;
  bool _allDay = true;
  final _start = TextEditingController(text: "09:00");
  final _end = TextEditingController(text: "17:00");
  final _reason = TextEditingController();

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    _reason.dispose();
    super.dispose();
  }

  int? _toMin(String hhmm) {
    final parts = hhmm.split(":");
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  @override
  Widget build(BuildContext context) {
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final trainers = ref.watch(trainersProvider);
    final bookings = ref.watch(allBookingsProvider);

    final startMin = _allDay ? null : _toMin(_start.text);
    final endMin = _allDay ? null : _toMin(_end.text);
    final overlapping = bookings.where((b) {
      if (b.trainerId != _trainerId || b.date != widget.date || b.status == "cancelled") return false;
      if (_allDay) return true;
      return startMin != null && endMin != null && b.slot >= startMin && b.slot < endMin;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Block Time"),
          if (isOwner) ...[
            const Text("COACH", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: trainers.map((t) {
                final selected = _trainerId == t.id;
                return InkWell(
                  onTap: () => setState(() => _trainerId = t.id),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg,
                      border: Border.all(color: selected ? AppColors.gold : AppColors.line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(t.name, style: TextStyle(fontSize: 12, color: selected ? AppColors.gold : AppColors.txt)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          InkWell(
            onTap: () => setState(() => _allDay = !_allDay),
            child: Row(
              children: [
                Icon(_allDay ? Icons.toggle_on : Icons.toggle_off, size: 30, color: _allDay ? AppColors.gold : AppColors.mute),
                const SizedBox(width: 8),
                const Text("Block the whole day", style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          if (!_allDay) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: FieldLabeled(label: "Start (HH:MM)", child: AppField(controller: _start))),
                const SizedBox(width: 8),
                Expanded(child: FieldLabeled(label: "End (HH:MM)", child: AppField(controller: _end))),
              ],
            ),
          ],
          const SizedBox(height: 10),
          FieldLabeled(label: "Reason (optional)", child: AppField(controller: _reason)),
          if (overlapping.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.08), border: Border.all(color: const Color(0xFFA8632F)), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${overlapping.length} existing booking${overlapping.length == 1 ? '' : 's'} overlap this window:", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFD68A4F))),
                  const SizedBox(height: 4),
                  ...overlapping.map((b) => Text("• ${fmtSlot(b.slot)}", style: const TextStyle(fontSize: 12, color: AppColors.mute))),
                  const SizedBox(height: 4),
                  const Text("Blocking won't cancel these — you'll need to reach out or cancel them yourself.", style: TextStyle(fontSize: 11, color: AppColors.mute)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          BtnGold(
            full: true,
            onPressed: () {
              ref.read(blockedTimesProvider.notifier).add(BlockedTime(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    trainerId: _trainerId,
                    date: widget.date,
                    allDay: _allDay,
                    startMin: startMin,
                    endMin: endMin,
                    reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
                  ));
              Navigator.of(context).pop();
            },
            child: const Text("Block time"),
          ),
        ],
      ),
    );
  }
}
