import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";

import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/activity_entry.dart";
import "../../../data/models/report_range.dart";

/// Who changed what, and when.
///
/// Until now nothing recorded it: settings changes went to an audit table
/// shown to nobody, and a session cancelled or a price edited left no trace
/// beyond the row it altered — so "who cancelled this?" had no answer.
///
/// Read-only by design. An audit trail that can be edited from the screen
/// that displays it isn't one; nothing in the app can write or erase an
/// entry, and the database refuses it to anyone but the owner.
final activityLogProvider = FutureProvider<List<ActivityEntry>>((ref) async {
  return SupabaseService.loadActivityLog();
});

class ActivityLogReport extends ConsumerStatefulWidget {
  const ActivityLogReport({super.key, required this.range});
  final ReportRange range;

  @override
  ConsumerState<ActivityLogReport> createState() => _ActivityLogReportState();
}

class _ActivityLogReportState extends ConsumerState<ActivityLogReport> {
  ActivityFilter _filter = ActivityFilter.all;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(activityLogProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      ),
      error: (e, _) => const HintBox(
        text: "Couldn't load the activity log. Only the owner can see it — if you're signed in as a coach, that's why.",
      ),
      data: (all) {
        // The date range from the hub still applies, so "last month" means
        // the same thing here as in every other report.
        final inRange = all.where((e) {
          final t = e.atTime;
          return t != null && widget.range.includes(t.toIso8601String().substring(0, 10));
        }).toList();
        final shown = inRange.where(_filter.matches).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final f in ActivityFilter.values)
                  _FilterChip(
                    label: f.label,
                    count: inRange.where(f.matches).length,
                    selected: f == _filter,
                    onTap: () => setState(() => _filter = f),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: DownloadCsvButton(
                filename: "activity-log.csv",
                rows: [
                  ["When", "Who", "Action", "What", "Client", "Detail"],
                  for (final e in shown)
                    [
                      e.at,
                      e.actorName ?? "",
                      e.action,
                      e.entity,
                      e.subject ?? "",
                      e.summary,
                    ],
                ],
              ),
            ),
            if (shown.isEmpty)
              HintBox(
                text: all.isEmpty
                    ? "Nothing recorded yet. From now on, every sale, edit, and session moved or cancelled appears here."
                    : "Nothing in this range matches that filter.",
              )
            else
              for (final e in shown) _Row(entry: e),
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry});
  final ActivityEntry entry;

  ({IconData icon, Color colour}) get _look => switch (entry.action) {
        "sold" || "charged" => (icon: LucideIcons.dollarSign, colour: AppColors.gold),
        "cancelled" => (icon: LucideIcons.x, colour: AppColors.danger),
        "moved" => (icon: LucideIcons.arrowRight, colour: AppColors.warning),
        "booked" => (icon: LucideIcons.calendarPlus, colour: AppColors.grn),
        "deleted" => (icon: LucideIcons.trash2, colour: AppColors.danger),
        "created" => (icon: LucideIcons.plus, colour: AppColors.grn),
        "attendance" => (icon: LucideIcons.userCheck, colour: AppColors.mute),
        _ => (icon: LucideIcons.pencil, colour: AppColors.mute),
      };

  String get _when {
    final t = entry.atTime;
    if (t == null) return "";
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? "am" : "pm";
    return "${months[t.month - 1]} ${t.day}, $h:${t.minute.toString().padLeft(2, "0")}$ampm";
  }

  @override
  Widget build(BuildContext context) {
    final look = _look;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(look.icon, size: 14, color: look.colour),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.summary,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3)),
                const SizedBox(height: 2),
                Text(
                  // "System" is the honest answer for a Stripe webhook or a
                  // scheduled job — better than attributing it to a person.
                  "${entry.actorName ?? "System"} · $_when",
                  style: const TextStyle(fontSize: 11, color: AppColors.mute),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold : AppColors.card,
          border: Border.all(color: selected ? AppColors.gold : AppColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          "$label ($count)",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.onGold : AppColors.txt,
          ),
        ),
      ),
    );
  }
}
