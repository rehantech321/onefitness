import "dart:async";

import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "../../core/supabase/supabase_service.dart";
import "../models/live_session.dart";

/// Every session currently running, as far as this signed-in user is allowed
/// to see. RLS already narrows it: a coach sees their own, a client sees only
/// sessions they're booked into.
///
/// Kept as a list rather than a single value because a coach can have a
/// session running while also appearing in another's roster, and because the
/// realtime stream delivers whole rows either way.
class LiveSessionsNotifier extends Notifier<List<LiveSession>> {
  @override
  List<LiveSession> build() => const [];

  void setAll(List<LiveSession> next) => state = next;

  /// Applies one realtime row. Ending a session is an update, not a delete,
  /// so a row arriving with ended_at set has to remove it from the live list
  /// rather than be merged in — otherwise Beep Your Coach would stay switched
  /// on after the coach finished.
  void apply(LiveSession run) {
    final without = state.where((r) => r.id != run.id).toList();
    state = run.isLive ? [...without, run] : without;
  }

  void remove(String id) => state = state.where((r) => r.id != id).toList();

  /// The running session this client can beep in.
  ///
  /// Takes no client id on purpose: the policies on `session_runs` already
  /// decide that, returning only sessions the signed-in person is booked
  /// into. Re-filtering here by a locally-held id would be a second,
  /// weaker copy of a rule the database already enforces — and the one that
  /// would be wrong if they ever disagreed.
  LiveSession? get beepable {
    for (final r in state) {
      if (r.supportsBeep) return r;
    }
    return null;
  }
}

final liveSessionsProvider =
    NotifierProvider<LiveSessionsNotifier, List<LiveSession>>(LiveSessionsNotifier.new);

/// Beeps for whichever session is currently on screen.
///
/// Scoped to one run rather than held globally: a coach only ever looks at
/// the session they're running, and a client only at their own, so there's
/// nothing to gain from keeping yesterday's beeps around.
class BeepsNotifier extends Notifier<List<Beep>> {
  @override
  List<Beep> build() => const [];

  void setAll(List<Beep> next) => state = next;

  void apply(Beep beep) {
    final without = state.where((b) => b.id != beep.id).toList();
    // A cancelled beep is gone from both sides — the spec is explicit that
    // cancelling clears it on the coach's side too.
    state = beep.isCancelled ? without : [...without, beep];
  }

  void clear() => state = const [];

  /// What the coach still has to answer, in the order they should see it:
  /// oldest first, except a Spot always jumps to the top.
  List<Beep> openFor(String trainerId) {
    final open = state.where((b) => b.trainerId == trainerId && b.isOpen).toList()
      ..sort(compareBeepPriority);
    return open;
  }

  /// This client's own beeps that are still standing, newest first — what
  /// they see as "Coach is coming" or "Coach notified", and can cancel.
  List<Beep> mineFor(String clientId) {
    final mine = state.where((b) => b.clientId == clientId && !b.isCancelled).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return mine;
  }
}

final beepsProvider = NotifierProvider<BeepsNotifier, List<Beep>>(BeepsNotifier.new);

/// Subscribes to both tables for as long as someone is signed in.
///
/// Realtime rather than push is the primary path on purpose: the spec wants
/// alerts to arrive instantly and an unacknowledged Spot to re-buzz every ten
/// seconds, and push can promise neither. The coach has the session screen
/// open by definition — they just started it.
class BeepRealtime {
  BeepRealtime(this._ref);
  final Ref _ref;

  RealtimeChannel? _runsChannel;
  RealtimeChannel? _beepsChannel;

  Future<void> start() async {
    await stop();
    try {
      _ref.read(liveSessionsProvider.notifier).setAll(await SupabaseService.loadLiveSessions());
    } catch (_) {
      // A failed first load is not fatal — the subscriptions below still
      // deliver anything that changes from here on.
    }

    _runsChannel = SupabaseService.client
        .channel("session_runs_live")
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: "public",
          table: "session_runs",
          callback: (payload) {
            final row = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
            if (row.isEmpty) return;
            final run = LiveSession.fromJson(row);
            if (run == null) return;
            if (payload.eventType == PostgresChangeEvent.delete) {
              _ref.read(liveSessionsProvider.notifier).remove(run.id);
            } else {
              _ref.read(liveSessionsProvider.notifier).apply(run);
            }
          },
        )
        .subscribe();

    _beepsChannel = SupabaseService.client
        .channel("beeps_live")
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: "public",
          table: "beeps",
          callback: (payload) {
            final row = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
            if (row.isEmpty) return;
            final beep = Beep.fromJson(row);
            if (beep == null) return;
            _ref.read(beepsProvider.notifier).apply(beep);
          },
        )
        .subscribe();
  }

  Future<void> stop() async {
    final runs = _runsChannel;
    final beeps = _beepsChannel;
    _runsChannel = null;
    _beepsChannel = null;
    if (runs != null) await SupabaseService.client.removeChannel(runs);
    if (beeps != null) await SupabaseService.client.removeChannel(beeps);
  }
}

final beepRealtimeProvider = Provider<BeepRealtime>((ref) {
  final rt = BeepRealtime(ref);
  ref.onDispose(rt.stop);
  return rt;
});
