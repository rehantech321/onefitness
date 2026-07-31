import "package:flutter_riverpod/flutter_riverpod.dart";

/// Mirrors ClientShell.jsx's local `screen` state — which of the
/// bottom-nav/drawer destinations is currently showing.
class ClientScreenNotifier extends Notifier<String> {
  @override
  String build() => "dashboard";

  void go(String screen) => state = screen;
}

final clientScreenProvider = NotifierProvider<ClientScreenNotifier, String>(ClientScreenNotifier.new);
