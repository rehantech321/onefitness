import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";

import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/session_timer.dart";
import "../../../data/models/live_session.dart";
import "../../../data/providers/beep_providers.dart";
import "beep_bar.dart";

/// What a client sees on every screen while their coach has a session running:
///
///  * a one-time "Your session has started" window the moment the coach
///    starts it (or when the client opens the app mid-session), and
///  * a pinned bar with the countdown, the Beep Your Coach button and a way
///    to message the coach, for as long as the session is live.
///
/// Both are driven by [liveSessionsProvider], which the realtime channel on
/// `session_runs` keeps current. RLS only returns sessions the client is
/// booked into, so nothing here needs to re-check eligibility.
class ClientLiveSessionLayer extends ConsumerStatefulWidget {
  const ClientLiveSessionLayer({
    super.key,
    required this.screen,
    required this.onOpenChat,
  });

  /// The client shell's current screen, so the pinned bar can step aside
  /// where it would double up (the workout tab already carries a beep bar)
  /// or collide with another pinned button.
  final String screen;
  final VoidCallback onOpenChat;

  @override
  ConsumerState<ClientLiveSessionLayer> createState() => _ClientLiveSessionLayerState();
}

class _ClientLiveSessionLayerState extends ConsumerState<ClientLiveSessionLayer> {
  /// Runs already announced, so the window opens once per session.
  final Set<String> _announced = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _announceNew(ref.read(liveSessionsProvider));
    });
  }

  void _announceNew(List<LiveSession> runs) {
    for (final run in runs) {
      if (!run.supportsBeep || _announced.contains(run.id)) continue;
      _announced.add(run.id);
      _showStartedDialog(run);
      break;
    }
  }

  Future<void> _showStartedDialog(LiveSession run) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.play, size: 20, color: AppColors.gold),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "Your session has started",
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "Your coach has started the session. Head over — you can beep "
                "or message them from here at any time.",
                style: TextStyle(fontSize: 12.5, color: AppColors.mute, height: 1.4),
              ),
              const SizedBox(height: 12),
              SessionTimer(run: run, label: "SESSION LIVE"),
              const SizedBox(height: 14),
              const BeepBar(exerciseNames: [], focusIndex: 0),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  widget.onOpenChat();
                },
                icon: const Icon(LucideIcons.messageSquare, size: 16),
                label: const Text("Message your coach"),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text("Close"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<LiveSession>>(liveSessionsProvider, (_, next) => _announceNew(next));

    final runs = ref.watch(liveSessionsProvider);
    final live = runs.where((r) => r.supportsBeep);
    // The workout tab renders its own BeepBar next to the exercise being done.
    if (live.isEmpty || widget.screen == "plans") return const SizedBox.shrink();

    return Positioned(
      left: 12,
      right: 12,
      // The Booking tab pins its own button at the bottom.
      bottom: widget.screen == "booking" ? 62 : 8,
      child: Material(
        color: AppColors.card,
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(child: BeepBar(exerciseNames: [], focusIndex: 0)),
              IconButton(
                tooltip: "Message your coach",
                onPressed: widget.onOpenChat,
                icon: Icon(LucideIcons.messageSquare, color: AppColors.gold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
