import "dart:async";

import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";

import "../theme/app_colors.dart";
import "../../data/models/live_session.dart";

/// How long is left of the session.
///
/// Counts DOWN from the session's own length to zero, because that is the
/// question people in a session actually have. It is worked out from
/// `started_at` plus the booked duration rather than from when this widget
/// was built, so it survives the coach moving between clients, backing out
/// to the roster and coming back, or the screen rebuilding — all of which
/// used to look like the session restarting.
///
/// The same widget serves the coach and the client, so both see the same
/// number ticking down rather than two clocks that drift apart.
class SessionTimer extends StatefulWidget {
  const SessionTimer({
    super.key,
    required this.run,
    this.compact = false,
    this.onRanOut,
    this.label,
  });

  final LiveSession run;

  /// A tighter form for sitting inline next to a title.
  final bool compact;

  /// Fired once when the clock reaches zero, so the coach's screen can close
  /// the session off. Only the coach passes this: the client's copy of the
  /// clock reaches zero too, and two devices both trying to end the same
  /// session is a race with nothing to gain.
  final VoidCallback? onRanOut;

  /// Overrides the "LIVE" badge text.
  final String? label;

  @override
  State<SessionTimer> createState() => _SessionTimerState();
}

class _SessionTimerState extends State<SessionTimer> {
  Timer? _tick;
  bool _firedRanOut = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      // Once, on the transition — not every tick afterwards, or the session
      // would be ended over and over for as long as the screen is open.
      if (!_firedRanOut && widget.run.hasRunOut) {
        _firedRanOut = true;
        widget.onRanOut?.call();
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// m:ss, or h:mm:ss for anything over an hour — a 90-minute session
  /// reading "73:20" is harder to parse at a glance than "1:13:20".
  String _left() {
    final d = widget.run.remaining ?? Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, "0");
    return h > 0 ? "$h:${m.toString().padLeft(2, "0")}:$sec" : "$m:$sec";
  }

  /// Under five minutes the clock turns amber — enough warning to start
  /// wrapping up without it nagging for the whole session.
  bool get _nearlyDone {
    final d = widget.run.remaining;
    return d != null && d <= const Duration(minutes: 5);
  }

  @override
  Widget build(BuildContext context) {
    final text = _left();
    final accent = _nearlyDone ? AppColors.warning : AppColors.gold;

    if (widget.compact) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: accent,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: _nearlyDone ? accent : AppColors.goldDim),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A filled dot reads as "recording" at a glance, which is what a
          // running session is.
          Icon(LucideIcons.circle, size: 8, color: accent),
          const SizedBox(width: 6),
          Text(
            widget.label ?? "LIVE",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              // Fixed-width digits, so the row doesn't jitter every second.
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          const Text("left", style: TextStyle(fontSize: 10.5, color: AppColors.mute)),
        ],
      ),
    );
  }
}
