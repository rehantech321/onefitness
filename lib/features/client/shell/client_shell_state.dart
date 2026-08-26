import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../data/models/booking.dart";

/// Mirrors ClientShell.jsx's local `screen` state — which of the
/// bottom-nav/drawer destinations is currently showing.
///
/// The web app runs in a browser (real back/forward history for free); this
/// app has no Navigator route per screen (every destination is just this
/// one string), so hardware back has nothing to pop and would otherwise
/// exit the app. `_history` tracks the path taken to get here so
/// [goBack] can unwind it — see ClientShell's PopScope.
class ClientScreenNotifier extends Notifier<String> {
  final List<String> _history = [];

  @override
  String build() => "dashboard";

  void go(String screen) {
    if (screen == state) return;
    // Dashboard is the universal root — landing there always clears
    // history rather than pushing, so nothing stale (an old tab visit, a
    // half-finished drill-down) can resurface on a later back, and a
    // second back on Dashboard correctly exits instead of "un-clearing".
    if (screen == "dashboard") {
      state = "dashboard";
      _history.clear();
      return;
    }
    _history.add(state);
    state = screen;
  }

  void goBack() {
    state = _history.isNotEmpty ? _history.removeLast() : "dashboard";
  }
}

final clientScreenProvider = NotifierProvider<ClientScreenNotifier, String>(
  ClientScreenNotifier.new,
);

/// Set right before navigating to the "forms" screen from a dashboard
/// onboarding-step tap, so IntakeAreaScreen knows which assessment to open
/// immediately instead of showing its default list. Cleared as soon as it's
/// read, so a later visit via the drawer (not through the dashboard) shows
/// the plain list again.
class PendingIntakeFormKeyNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? key) => state = key;
}

final pendingIntakeFormKeyProvider =
    NotifierProvider<PendingIntakeFormKeyNotifier, String?>(
      PendingIntakeFormKeyNotifier.new,
    );

/// Set right before navigating to the "day" screen from a Workout Calendar
/// tap on a date that has a dot — DayDetailScreen reads and shows this date.
class PendingDayDetailDateNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? date) => state = date;
}

final pendingDayDetailDateProvider =
    NotifierProvider<PendingDayDetailDateNotifier, String?>(
      PendingDayDetailDateNotifier.new,
    );

/// Set right before navigating to the "booking" screen from anywhere other
/// than the plain bottom-bar tab — a calendar tap on an empty future date
/// (initialDate only) or a "Reschedule" tap (both fields, keyed off the
/// booking being moved). Mirrors ClientShell.jsx's local `bookingTarget`.
class BookingTarget {
  const BookingTarget({this.initialDate, this.reschedule});
  final String? initialDate;
  final Booking? reschedule;
}

class PendingBookingTargetNotifier extends Notifier<BookingTarget?> {
  @override
  BookingTarget? build() => null;

  void set(BookingTarget? target) => state = target;
}

final pendingBookingTargetProvider =
    NotifierProvider<PendingBookingTargetNotifier, BookingTarget?>(
      PendingBookingTargetNotifier.new,
    );
