import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";

import "../../../core/notifications/beep_sounds.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../data/models/live_session.dart";
import "../../../data/providers/beep_providers.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/platform_settings_provider.dart";

/// What the coach sees and hears when a client beeps during a live session.
///
/// Overlaid on the session screen rather than pushed as a route: the coach is
/// mid-set with someone else, and an alert that stole the screen would be
/// worse than the problem it reports. Help and Spot sit as a pop-up until
/// acknowledged; Done is a banner that clears itself so it never covers the
/// logging grid.
class CoachBeepAlerts extends ConsumerStatefulWidget {
  const CoachBeepAlerts({super.key, required this.trainerId, required this.child});

  final String trainerId;
  final Widget child;

  @override
  ConsumerState<CoachBeepAlerts> createState() => _CoachBeepAlertsState();
}

/// An unacknowledged Spot re-buzzes on this interval until the coach answers.
/// Someone is holding a loaded bar; a single missed buzz is not acceptable.
const _spotRepeat = Duration(seconds: 10);

/// How long a Done banner stays before clearing itself.
const _doneLinger = Duration(seconds: 6);

class _CoachBeepAlertsState extends ConsumerState<CoachBeepAlerts> {
  /// Beeps already announced, so a rebuild never re-sounds an old one.
  final Set<String> _announced = {};

  /// Done beeps currently showing as a banner, newest last.
  final List<Beep> _banners = [];
  final Map<String, Timer> _bannerTimers = {};

  Timer? _spotTimer;

  @override
  void initState() {
    super.initState();
    _spotTimer = Timer.periodic(_spotRepeat, (_) => _rebuzzUnansweredSpots());
  }

  @override
  void dispose() {
    _spotTimer?.cancel();
    for (final t in _bannerTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  String? _soundIdFor(BeepKind kind) {
    final s = ref.read(platformSettingsProvider).beepSounds;
    return s[kind.key];
  }

  Future<void> _rebuzzUnansweredSpots() async {
    if (!mounted) return;
    final outstanding = ref.read(beepsProvider.notifier).openFor(widget.trainerId);
    final spot = outstanding.where((b) => b.kind.isUrgent).toList();
    if (spot.isEmpty) return;
    await BeepPlayer.instance.alert(BeepKind.spot, _soundIdFor(BeepKind.spot));
  }

  /// Sounds anything that has just arrived. Driven from build rather than a
  /// stream listener because the realtime provider is the single source of
  /// truth for what exists — this only decides what has not been heard yet.
  void _announceNew(List<Beep> beeps) {
    for (final beep in beeps) {
      if (beep.trainerId != widget.trainerId) continue;
      if (beep.isCancelled || _announced.contains(beep.id)) continue;
      _announced.add(beep.id);

      unawaited(BeepPlayer.instance.alert(beep.kind, _soundIdFor(beep.kind)));

      if (beep.kind == BeepKind.done) {
        _banners.add(beep);
        _bannerTimers[beep.id] = Timer(_doneLinger, () {
          if (!mounted) return;
          setState(() => _banners.removeWhere((b) => b.id == beep.id));
          _bannerTimers.remove(beep.id);
        });
      }
    }
  }

  Future<void> _acknowledge(Beep beep) async {
    try {
      await SupabaseService.acknowledgeBeep(beep.id);
      ref.read(beepsProvider.notifier).apply(beep.copyWith(
            acknowledgedAt: DateTime.now().toUtc().toIso8601String(),
          ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't mark that acknowledged — try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(beepsProvider);
    // A cancelled beep disappears from the queue, and its banner with it.
    final liveIds = all.where((b) => !b.isCancelled).map((b) => b.id).toSet();
    _banners.removeWhere((b) => !liveIds.contains(b.id));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _announceNew(all);
    });

    final queue = ref.read(beepsProvider.notifier).openFor(widget.trainerId);
    final top = queue.isEmpty ? null : queue.first;

    return Stack(
      children: [
        widget.child,

        // Done: a small banner, deliberately out of the way of the grid.
        if (_banners.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final b in _banners.take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _DoneBanner(beep: b, name: _nameFor(b.clientId)),
                  ),
              ],
            ),
          ),

        // Help and Spot: a pop-up that stays until the coach taps it.
        if (top != null)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: _BeepPopup(
              beep: top,
              name: _nameFor(top.clientId),
              queued: queue.length - 1,
              onAcknowledge: () => _acknowledge(top),
            ),
          ),
      ],
    );
  }

  String _nameFor(String clientId) {
    final roster = ref.read(rosterProvider);
    for (final c in roster) {
      if (c.id == clientId) return c.name;
    }
    return "A client";
  }
}

class _BeepPopup extends StatelessWidget {
  const _BeepPopup({
    required this.beep,
    required this.name,
    required this.queued,
    required this.onAcknowledge,
  });

  final Beep beep;
  final String name;
  final int queued;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final urgent = beep.kind.isUrgent;
    final accent = urgent ? AppColors.danger : AppColors.gold;
    final what = urgent ? "needs a spot" : "needs help";

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: accent, width: 2),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(urgent ? LucideIcons.triangleAlert : LucideIcons.circleHelp, size: 20, color: accent),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    beep.exercise == null
                        ? "$name $what"
                        : "$name $what — ${beep.exercise}",
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.25),
                  ),
                ),
              ],
            ),
            if (queued > 0) ...[
              const SizedBox(height: 4),
              Text(
                "$queued more waiting",
                style: const TextStyle(fontSize: 11.5, color: AppColors.mute),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: onAcknowledge,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: urgent ? Colors.white : AppColors.onGold,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                ),
                child: const Text(
                  "On my way",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoneBanner extends StatelessWidget {
  const _DoneBanner({required this.beep, required this.name});
  final Beep beep;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.grn),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.check, size: 14, color: AppColors.grn),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                beep.exercise == null
                    ? "$name is done"
                    : "$name is done with ${beep.exercise}",
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
