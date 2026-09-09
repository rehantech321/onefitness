import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/waitlist_entry.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";

/// "A spot opened up — do you want it?"
///
/// Shown at the top of Booking whenever a slot this client was waiting for
/// has been offered to them. Deliberately prominent and time-bounded: the
/// slot is held only for them until it expires, and a clear decline is what
/// moves it to the next person quickly rather than making everyone wait out
/// the window.
class WaitlistOfferBanner extends ConsumerStatefulWidget {
  const WaitlistOfferBanner({super.key});

  @override
  ConsumerState<WaitlistOfferBanner> createState() => _WaitlistOfferBannerState();
}

class _WaitlistOfferBannerState extends ConsumerState<WaitlistOfferBanner> {
  String? _busyId;
  String? _error;

  Future<void> _respond(WaitlistEntry offer, bool accept) async {
    setState(() {
      _busyId = offer.id;
      _error = null;
    });
    try {
      final booked = await SupabaseService.respondToWaitlistOffer(
        entryId: offer.id,
        accept: accept,
      );
      // Both the waitlist and the bookings list changed server-side, so
      // re-read rather than guessing at the new state.
      final waitlist = await SupabaseService.loadWaitlist();
      ref.read(waitlistProvider.notifier).setAll(waitlist);
      if (booked) {
        final bookings = await SupabaseService.loadBookings();
        final info = ref.read(clientInfoProvider);
        ref.read(allBookingsProvider.notifier).setAll(bookings);
        ref.read(clientBookingsProvider.notifier)
            .setAll(bookings.where((b) => b.clientId == info.id).toList());
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(booked
                ? "Booked — see you there."
                : "No problem — we've offered it to the next person."),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(clientInfoProvider);
    final offers = ref
        .watch(waitlistProvider)
        .where((w) => w.clientId == info.id && w.isLiveOffer)
        .toList();
    if (offers.isEmpty) return const SizedBox.shrink();

    final trainers = ref.watch(trainersProvider);

    return Column(
      children: offers.map((offer) {
        final coach = trainers.where((t) => t.id == offer.trainerId).firstOrNull;
        final busy = _busyId == offer.id;
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.1),
            border: Border.all(color: AppColors.gold),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.bellRing, size: 17, color: AppColors.gold),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "A spot just opened up",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.gold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "${dayLabel(offer.date)} at ${fmtSlot(offer.slot)}"
                "${coach != null ? " with ${coach.name}" : ""}.",
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                _heldFor(offer.offerExpiresAt),
                style: const TextStyle(fontSize: 11.5, color: AppColors.mute),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.errorText)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: BtnGold(
                      onPressed: busy ? null : () => _respond(offer, true),
                      child: Text(busy ? "Working…" : "Yes, book it"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BtnGhost(
                      onPressed: busy ? null : () => _respond(offer, false),
                      child: const Text("No thanks"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// How long they've got, in plain terms — a raw expiry timestamp would make
/// the reader do the arithmetic.
String _heldFor(DateTime? expiresAt) {
  if (expiresAt == null) return "Held for you for a short while.";
  final mins = expiresAt.difference(DateTime.now()).inMinutes;
  if (mins <= 0) return "This offer has just expired.";
  if (mins < 60) return "Held for you for another $mins min — then it passes to the next person.";
  final hours = (mins / 60).floor();
  return "Held for you for another $hours hour${hours == 1 ? "" : "s"} — then it passes to the next person.";
}
