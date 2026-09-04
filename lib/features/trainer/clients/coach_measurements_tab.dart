import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/notification_triggers.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/trainer_providers.dart";

/// Coach-side view of a client's measurement log — this app's first,
/// there's no earlier tab for it (see Notifications spec audit). Read-only
/// list plus one comment box per entry (Notifications spec — "Coach
/// comments on a measurement").
class CoachMeasurementsTab extends ConsumerStatefulWidget {
  const CoachMeasurementsTab({super.key, required this.clientId});
  final String clientId;

  @override
  ConsumerState<CoachMeasurementsTab> createState() => _CoachMeasurementsTabState();
}

class _CoachMeasurementsTabState extends ConsumerState<CoachMeasurementsTab> {
  final Map<String, TextEditingController> _controllers = {};
  String? _savingId;

  TextEditingController _controllerFor(String id, String? current) =>
      _controllers.putIfAbsent(id, () => TextEditingController(text: current ?? ""));

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveComment(String measurementId) async {
    final record = ref.read(trainerClientRecordsProvider)[widget.clientId];
    if (record == null) return;
    final text = _controllers[measurementId]?.text.trim() ?? "";
    setState(() => _savingId = measurementId);
    try {
      final next = record.measurements.map((m) => m.id == measurementId ? m.copyWith(coachComment: text, coachCommentAt: stamp()) : m).toList();
      await SupabaseService.updateClientMeasurements(widget.clientId, next);
      ref.read(trainerClientRecordsProvider.notifier).update(widget.clientId, (r) => r.copyWith(measurements: next));
      if (text.isNotEmpty) {
        final info = ref.read(trainerRosterProvider).where((c) => c.id == widget.clientId);
        if (info.isNotEmpty) {
          notifyCoachComment(toEmail: info.first.email ?? "", toName: info.first.name, kind: "measurement entry");
        }
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Comment saved.")));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save — check your connection and try again.")));
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = ref.watch(trainerClientRecordsProvider)[widget.clientId];
    final entries = (record?.measurements ?? const []).toList()..sort((a, b) => b.date.compareTo(a.date));

    if (entries.isEmpty) {
      return const Padding(padding: EdgeInsets.all(18), child: HintBox(text: "No measurements logged yet."));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Measurements"),
          ...entries.map((m) {
            final filled = m.fields.where((f) => f.$3 != null && f.$3!.isNotEmpty).toList();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.date, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: filled
                          .map((f) => Text("${f.$2}: ${f.$3}", style: const TextStyle(fontSize: 12, color: AppColors.mute)))
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                    const Text("COACH COMMENT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.mute, letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    AppField(controller: _controllerFor(m.id, m.coachComment), placeholder: "Leave a note on this entry…", maxLines: 2),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: BtnGhost(
                        onPressed: _savingId == m.id ? null : () => _saveComment(m.id),
                        child: Text(_savingId == m.id ? "Saving…" : "Save comment"),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
