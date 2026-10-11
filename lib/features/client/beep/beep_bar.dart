import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";

import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/session_timer.dart";
import "../../../data/models/live_session.dart";
import "../../../data/providers/beep_providers.dart";
import "../../../data/providers/client_providers.dart";

/// The gym is large and a coach running a semi-private session can't watch
/// everyone at once. This is how a client gets their attention without
/// crossing the floor to find them.
///
/// Only rendered while the coach actually has the session running — see
/// [liveSessionsProvider]. Nothing here decides eligibility on its own: the
/// database re-checks that the session is live, semi-private, and one this
/// client is booked into before it will accept a beep at all.
class BeepBar extends ConsumerStatefulWidget {
  const BeepBar({
    super.key,
    required this.exerciseNames,
    required this.focusIndex,
    this.fullView = false,
  });

  /// Every exercise in the day, so "Done" can name the right one.
  final List<String> exerciseNames;

  /// Where the client is in the one-at-a-time view. In Full view they're
  /// scrolling freely, so this is only a starting guess and they're asked
  /// which exercise they mean.
  final int focusIndex;

  final bool fullView;

  @override
  ConsumerState<BeepBar> createState() => _BeepBarState();
}

/// 20 seconds before the same request can be sent again, so a client tapping
/// twice doesn't double-buzz a coach who is already walking over. A
/// *different* request goes straight through — someone who asked for help
/// and then found themselves stuck under a bar must not be made to wait.
const _cooldown = Duration(seconds: 20);

class _BeepBarState extends ConsumerState<BeepBar> {
  final Map<BeepKind, DateTime> _lastSent = {};
  Timer? _tick;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Redraws the cooldown countdown on the sheet without any user input.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _lastSent.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Spot is deliberately exempt: it means someone is under a loaded bar.
  Duration _remaining(BeepKind kind) {
    if (kind.isUrgent) return Duration.zero;
    final last = _lastSent[kind];
    if (last == null) return Duration.zero;
    final left = _cooldown - DateTime.now().difference(last);
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> _send(LiveSession run, BeepKind kind, String? exercise) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final beep = await SupabaseService.sendBeep(
        sessionRunId: run.id,
        trainerId: run.trainerId,
        kind: kind,
        exercise: exercise,
      );
      if (beep != null) ref.read(beepsProvider.notifier).apply(beep);
      _lastSent[kind] = DateTime.now();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(kind == BeepKind.done ? "Coach notified" : "Your coach has been beeped"),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't reach your coach — try again.")),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _cancel(Beep beep) async {
    try {
      await SupabaseService.cancelBeep(beep.id);
      ref.read(beepsProvider.notifier).apply(beep.copyWith(
            cancelledAt: DateTime.now().toUtc().toIso8601String(),
          ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't cancel that — try again.")),
      );
    }
  }

  Future<void> _openOptions(LiveSession run) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _BeepOptionsSheet(
        remaining: _remaining,
        fullView: widget.fullView,
        exerciseNames: widget.exerciseNames,
        focusIndex: widget.focusIndex,
        onPick: (kind, exercise) {
          Navigator.of(ctx).pop();
          _send(run, kind, exercise);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clientId = ref.watch(clientInfoProvider).id;
    final run = ref.watch(liveSessionsProvider.notifier).beepable;
    // Watch the list too, so the bar appears and disappears as the coach
    // starts and ends the session.
    ref.watch(liveSessionsProvider);
    if (run == null) return const SizedBox.shrink();

    final mine = ref.watch(beepsProvider.notifier).mineFor(clientId);
    ref.watch(beepsProvider);
    final standing = mine.where((b) => b.kind != BeepKind.done || !_isStale(b)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The client's own view of the session their coach started: the
        // same clock, counting down to the same moment. Without it the bar
        // appeared out of nowhere and vanished just as abruptly, with no
        // indication of how long was left to use it.
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            children: [
              SessionTimer(run: run, label: "SESSION LIVE"),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "Your coach has started the session.",
                  style: TextStyle(fontSize: 11, color: AppColors.mute),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 46,
          child: ElevatedButton.icon(
            onPressed: _sending ? null : () => _openOptions(run),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.onGold,
              disabledBackgroundColor: AppColors.goldDim,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(LucideIcons.bell, size: 17),
            label: const Text(
              "Beep Your Coach",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        for (final beep in standing)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _StandingBeep(beep: beep, onCancel: () => _cancel(beep)),
          ),
      ],
    );
  }

  /// A Done is information, not a request — it stops being worth showing the
  /// client once a little time has passed, so the bar doesn't accumulate a
  /// list of everything they've finished.
  bool _isStale(Beep b) {
    final at = b.createdAtTime;
    return at != null && DateTime.now().difference(at) > const Duration(seconds: 30);
  }
}

/// What the client sees after beeping, with the way to take it back.
class _StandingBeep extends StatelessWidget {
  const _StandingBeep({required this.beep, required this.onCancel});
  final Beep beep;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final status = beep.clientStatus;
    if (status == null) return const SizedBox.shrink();
    final answered = beep.isAcknowledged;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: answered ? AppColors.grn : AppColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            answered ? LucideIcons.check : LucideIcons.clock,
            size: 13,
            color: answered ? AppColors.grn : AppColors.mute,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              beep.exercise == null ? status : "$status · ${beep.exercise}",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: answered ? AppColors.grn : AppColors.txt,
              ),
            ),
          ),
          // Cancellable even after the coach has acknowledged, and even for
          // an accidental Done.
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.mute,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(44, 32),
            ),
            child: const Text("Cancel", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _BeepOptionsSheet extends StatefulWidget {
  const _BeepOptionsSheet({
    required this.remaining,
    required this.onPick,
    required this.exerciseNames,
    required this.focusIndex,
    required this.fullView,
  });

  final Duration Function(BeepKind) remaining;
  final void Function(BeepKind kind, String? exercise) onPick;
  final List<String> exerciseNames;
  final int focusIndex;
  final bool fullView;

  @override
  State<_BeepOptionsSheet> createState() => _BeepOptionsSheetState();
}

class _BeepOptionsSheetState extends State<_BeepOptionsSheet> {
  late int _exerciseIndex = widget.focusIndex.clamp(
    0,
    widget.exerciseNames.isEmpty ? 0 : widget.exerciseNames.length - 1,
  );

  String? get _exercise =>
      _exerciseIndex >= 0 && _exerciseIndex < widget.exerciseNames.length
          ? widget.exerciseNames[_exerciseIndex]
          : null;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Beep Your Coach",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              _exercise == null ? "Your coach will come to you." : "On ${_exercise!}",
              style: const TextStyle(fontSize: 12, color: AppColors.mute),
            ),

            // In Full view the client is scrolling freely, so which exercise
            // they mean can't be assumed — they say.
            if (widget.fullView && widget.exerciseNames.length > 1) ...[
              const SizedBox(height: 12),
              const Text(
                "WHICH EXERCISE",
                style: TextStyle(fontSize: 10, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 1),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.exerciseNames.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) {
                    final on = i == _exerciseIndex;
                    return InkWell(
                      onTap: () => setState(() => _exerciseIndex = i),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: on ? AppColors.gold : AppColors.card,
                          border: Border.all(color: on ? AppColors.gold : AppColors.line),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.exerciseNames[i],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: on ? AppColors.onGold : AppColors.mute,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 14),
            _BeepChoice(
              kind: BeepKind.help,
              icon: LucideIcons.circleHelp,
              blurb: "Something isn't right, or you're not sure what to do.",
              remaining: widget.remaining(BeepKind.help),
              onTap: () => widget.onPick(BeepKind.help, _exercise),
            ),
            const SizedBox(height: 8),
            _BeepChoice(
              kind: BeepKind.spot,
              icon: LucideIcons.users,
              blurb: "You need someone on the bar with you. Always sends.",
              remaining: widget.remaining(BeepKind.spot),
              onTap: () => widget.onPick(BeepKind.spot, _exercise),
            ),
            const SizedBox(height: 8),
            _BeepChoice(
              kind: BeepKind.done,
              icon: LucideIcons.check,
              blurb: "Finished this exercise. You move on yourself.",
              remaining: widget.remaining(BeepKind.done),
              onTap: () => widget.onPick(BeepKind.done, _exercise),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeepChoice extends StatelessWidget {
  const _BeepChoice({
    required this.kind,
    required this.icon,
    required this.blurb,
    required this.remaining,
    required this.onTap,
  });

  final BeepKind kind;
  final IconData icon;
  final String blurb;
  final Duration remaining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final waiting = remaining > Duration.zero;
    final accent = kind.isUrgent ? AppColors.danger : AppColors.gold;

    return InkWell(
      onTap: waiting ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: waiting ? AppColors.line : accent),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: waiting ? AppColors.mute : accent),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind.label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: waiting ? AppColors.mute : AppColors.txt,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    waiting
                        ? "Just sent — you can send this again in ${remaining.inSeconds}s"
                        : blurb,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.mute, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
