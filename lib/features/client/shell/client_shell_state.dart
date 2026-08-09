import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../data/models/booking.dart";

/// Mirrors ClientShell.jsx's local `screen` state — which of the
/// bottom-nav/drawer destinations is currently showing.
class ClientScreenNotifier extends Notifier<String> {
  @override
  String build() => "dashboard";

  void go(String screen) => state = screen;
}

final clientScreenProvider = NotifierProvider<ClientScreenNotifier, String>(ClientScreenNotifier.new);

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

final pendingIntakeFormKeyProvider = NotifierProvider<PendingIntakeFormKeyNotifier, String?>(PendingIntakeFormKeyNotifier.new);

/// Set right before navigating to the "day" screen from a Workout Calendar
/// tap on a date that has a dot — DayDetailScreen reads and shows this date.
class PendingDayDetailDateNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? date) => state = date;
}

final pendingDayDetailDateProvider = NotifierProvider<PendingDayDetailDateNotifier, String?>(PendingDayDetailDateNotifier.new);

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

final pendingBookingTargetProvider = NotifierProvider<PendingBookingTargetNotifier, BookingTarget?>(PendingBookingTargetNotifier.new);
