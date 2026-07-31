import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/attention_utils.dart";
import "../../../core/utils/client_status_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
import "../../client/booking/date_strip.dart";
import "../shell/trainer_shell_state.dart";

/// Mirrors TrainerHome.jsx — the coach/owner dashboard: greeting header,
/// owner-only stat row, "Needs Attention" list, a collapsible day calendar,
/// and that day's sessions grouped by time with inline attendance actions.
/// The full-screen "Start Session" carousel and per-client trainer notes
/// (FlagAlert) aren't built yet — the button is wired to a placeholder.
class TrainerHomeScreen extends ConsumerStatefulWidget {
  const TrainerHomeScreen({super.key});

  @override
  ConsumerState<TrainerHomeScreen> createState() => _TrainerHomeScreenState();
}

class _TrainerHomeScreenState extends ConsumerState<TrainerHomeScreen> {
  late String _viewDate = isoToday();
  bool _calendarOpen = false;

  @override
  Widget build(BuildContext context) {
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";
    final roster = ref.watch(trainerRosterProvider);
    final trainers = ref.watch(trainersProvider);
    final bookings = ref.watch(allBookingsProvider);
    final clientRecords = ref.watch(trainerClientRecordsProvider);

    final me = trainers.where((t) => t.id == trainerAuth);
    final myName = isOwner ? "Owner" : (me.isNotEmpty ? me.first.name : "Coach");

    // Dashboard/schedule scope to just this coach's own clients; owner sees everyone.
    final myRoster = isOwner ? roster : roster.where((c) => c.primaryTrainerId == trainerAuth).toList();

    final needsAttention = [
      ...computeNeedsAttention(myRoster, clientRecords),
      ...computeUnloggedAttendance(myRoster, bookings),
    ];
    final grouped = <String, List<AttentionItem>>{};
    for (final n in needsAttention) {
      grouped.putIfAbsent(n.label, () => []).add(n);
    }

    final dayBookings = bookings.where((b) => b.date == _viewDate && (isOwner || b.trainerId == trainerAuth)).toList()
      ..sort((a, b) => a.slot.compareTo(b.slot));
    final byTime = <int, List<Booking>>{};
    for (final b in dayBookings) {
      byTime.putIfAbsent(b.slot, () => []).add(b);
    }
    final slots = byTime.keys.toList()..sort();

    void goMode(String mode) => ref.read(trainerModeProvider.notifier).go(mode);
    void showComingSoon(String what) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$what coming in a later pass.")));
    void openClient(String clientId) {
      ref.read(selectedClientIdProvider.notifier).select(clientId);
      goMode("clients");
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(name: isOwner ? "Owner" : myName, size: 48, active: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Hi, ${isOwner ? "Owner" : myName.split(" ").first}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    Text(dayLabel(isoToday()), style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => ref.read(trainerAuthProvider.notifier).signOut(),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.mute, side: const BorderSide(color: AppColors.line)),
                child: const Text("Sign out", style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (isOwner)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  _StatBox(label: "Clients", value: "${myRoster.length}", onTap: () => goMode("clients")),
                  const SizedBox(width: 10),
                  _StatBox(label: "Trainers", value: "${trainers.length}", onTap: () => goMode("staff")),
                  const SizedBox(width: 10),
                  _StatBox(
                    label: "Today",
                    value: "${bookings.where((b) => b.date == isoToday() && (isOwner || b.trainerId == trainerAuth)).length}",
                    onTap: () => goMode("schedule"),
                  ),
                ],
              ),
            ),
          const SectionLabel("Needs Attention"),
          if (needsAttention.isEmpty)
            const HintBox(text: "Nothing needs your attention right now ✓")
          else
            ...grouped.entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${entry.key.toUpperCase()} (${entry.value.length})",
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFD68A4F), letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 6),
                      ...entry.value.map((n) {
                        final matches = roster.where((c) => c.id == n.clientId);
                        if (matches.isEmpty) return const SizedBox.shrink();
                        final c = matches.first;
                        return AppCard(
                          onTap: () {
                            if (n.bookingId != null) {
                              setState(() {
                                _viewDate = n.date!;
                                _calendarOpen = true;
                              });
                            } else {
                              openClient(c.id);
                            }
                          },
                          child: Row(
                            children: [
                              Avatar(name: c.name, size: 30),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    if (n.bookingId != null)
                                      Text(
                                        "${dayLabel(n.date!)}${n.date == isoToday() ? ' · Today' : ''} · ${fmtSlot(n.slot!)}",
                                        style: const TextStyle(fontSize: 11, color: AppColors.mute),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                )),
          InkWell(
            onTap: () => setState(() => _calendarOpen = !_calendarOpen),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
              margin: const EdgeInsets.only(top: 4),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line), bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(dayLabel(_viewDate), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      if (_viewDate == isoToday())
                        const Text(" · Today", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gold)),
                    ],
                  ),
                  Icon(_calendarOpen ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 16, color: AppColors.mute),
                ],
              ),
            ),
          ),
          if (_calendarOpen) DateStrip(date: _viewDate, onSelect: (d) => setState(() => _viewDate = d)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SectionLabel(isOwner ? "Sessions" : "Your sessions"),
              TextButton(
                onPressed: () => goMode("schedule"),
                style: TextButton.styleFrom(foregroundColor: AppColors.gold, padding: EdgeInsets.zero, minimumSize: Size.zero),
                child: const Text("Full schedule →", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (slots.isEmpty)
            const HintBox(text: "No sessions booked this day.")
          else
            ...slots.map((slot) {
              final group = byTime[slot]!;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            fmtSlot(slot),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.gold, letterSpacing: 1),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => showComingSoon("Session carousel"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                          ),
                          child: const Text("▶ Start Session", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...group.map((b) {
                      final matches = roster.where((c) => c.id == b.clientId);
                      final client = matches.isNotEmpty ? matches.first : null;
                      final rec = clientRecords[b.clientId];
                      final status = rec != null ? computeClientStatus(rec) : null;
                      final t = trainers.where((x) => x.id == b.trainerId);
                      return AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: client != null ? () => openClient(client.id) : null,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Avatar(name: client?.name ?? "?", size: 32),
                                        if (status != null)
                                          Positioned(bottom: -1, right: -1, child: StatusDot(status: status, size: 9)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(client?.name ?? "Removed", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                            if (b.attendanceStatus != null) ...[
                                              const SizedBox(width: 6),
                                              _AttendanceBadge(status: b.attendanceStatus!),
                                            ],
                                          ],
                                        ),
                                        Text(
                                          [disciplineLabel(b.discipline), if (isOwner && t.isNotEmpty) t.first.name].join(" · "),
                                          style: const TextStyle(fontSize: 11, color: AppColors.mute),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (client != null) const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
                                ],
                              ),
                            ),
                            if (client != null) ...[
                              const SizedBox(height: 9),
                              Wrap(
                                spacing: 5,
                                runSpacing: 5,
                                children: kAttendanceOptions.map((opt) {
                                  final active = b.attendanceStatus == opt.key;
                                  return InkWell(
                                    onTap: () => ref.read(allBookingsProvider.notifier).updateAttendance(b.id, active ? null : opt.key),
                                    borderRadius: BorderRadius.circular(7),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                                      decoration: BoxDecoration(
                                        color: active ? opt.color.withValues(alpha: 0.13) : Colors.transparent,
                                        border: Border.all(color: active ? opt.color : AppColors.line),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: Text(
                                        opt.label,
                                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: active ? opt.color : AppColors.mute),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.gold)),
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.mute, letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class AttendanceOption {
  const AttendanceOption(this.key, this.label, this.color);
  final String key;
  final String label;
  final Color color;
}

const kAttendanceOptions = [
  AttendanceOption("checked-in", "Check In", AppColors.grn),
  AttendanceOption("early-cancel", "Early Cancel", AppColors.info),
  AttendanceOption("late-cancel", "Late Cancel", AppColors.warning),
  AttendanceOption("no-show", "No Show", AppColors.danger),
];

const _attendanceLabels = {"checked-in": "Check In", "early-cancel": "Early Cancel", "late-cancel": "Late Cancel", "no-show": "No Show"};

class _AttendanceBadge extends StatelessWidget {
  const _AttendanceBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final opt = kAttendanceOptions.firstWhere((o) => o.key == status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(border: Border.all(color: opt.color), borderRadius: BorderRadius.circular(5)),
      child: Text(_attendanceLabels[status] ?? status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: opt.color)),
    );
  }
}
