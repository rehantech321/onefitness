import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/utils/booking_utils.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
import "../../client/booking/booking_screen.dart";

/// Mirrors App.jsx's "selfbook" trainerMode — a coach (never the owner)
/// booking themselves into another coach's session, "leading by example".
/// Reuses the exact same client-facing BookingScreen by scoping a nested
/// ProviderScope to a synthetic isStaff ClientInfo (bypasses the membership
/// gate entirely — see canBookOffering) and the roster of every OTHER
/// coach, while still syncing real bookings back into the shared
/// allBookingsProvider so every other screen (another coach's own
/// dashboard, Reports, etc.) sees them immediately, same as the web's
/// single shared `bookings` state.
class SelfBookScreen extends ConsumerWidget {
  const SelfBookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authId = ref.watch(trainerAuthProvider);
    final trainers = ref.watch(trainersProvider);
    final allBookings = ref.watch(allBookingsProvider);
    if (authId == null) return const SizedBox.shrink();

    final me = trainers.where((t) => t.id == authId);
    final selfInfo = ClientInfo(
      id: authId,
      name: me.isNotEmpty ? me.first.name : "You",
      city: me.isNotEmpty ? cityFromAddress(me.first.locationAddress) : null,
      isStaff: true,
    );
    final otherTrainers = trainers.where((t) => t.id != authId).toList();
    final myBookings = allBookings.where((b) => b.clientId == authId).toList();

    return ProviderScope(
      overrides: [
        clientInfoProvider.overrideWith(() => _StaticClientInfoNotifier(selfInfo)),
        trainersProvider.overrideWith(() => _StaticTrainersNotifier(otherTrainers)),
        clientBookingsProvider.overrideWith(() => _SyncedSelfBookingsNotifier(
              initial: myBookings,
              onAdd: (b) => ref.read(allBookingsProvider.notifier).addBooking(b),
              onCancel: (id) => ref.read(allBookingsProvider.notifier).cancelBooking(id),
              onReschedule: (newBooking, originalId) {
                ref.read(allBookingsProvider.notifier).addBooking(newBooking);
                ref.read(allBookingsProvider.notifier).cancelBooking(originalId);
              },
            )),
      ],
      child: BookingScreen(onGoMemberships: () {}),
    );
  }
}

class _StaticClientInfoNotifier extends ClientInfoNotifier {
  _StaticClientInfoNotifier(this._initial);
  final ClientInfo _initial;
  @override
  ClientInfo build() => _initial;
}

class _StaticTrainersNotifier extends TrainersNotifier {
  _StaticTrainersNotifier(this._initial);
  final List<Trainer> _initial;
  @override
  List<Trainer> build() => _initial;
}

class _SyncedSelfBookingsNotifier extends ClientBookingsNotifier {
  _SyncedSelfBookingsNotifier({required List<Booking> initial, required this.onAdd, required this.onCancel, required this.onReschedule})
      : _initial = initial;

  final List<Booking> _initial;
  final void Function(Booking) onAdd;
  final void Function(String) onCancel;
  final void Function(Booking newBooking, String originalId) onReschedule;

  @override
  List<Booking> build() => _initial;

  @override
  void addBooking(Booking b) {
    super.addBooking(b);
    onAdd(b);
  }

  @override
  void cancelBooking(String id) {
    super.cancelBooking(id);
    onCancel(id);
  }

  @override
  void reschedule(Booking newBooking, String originalId) {
    super.reschedule(newBooking, originalId);
    onReschedule(newBooking, originalId);
  }
}
