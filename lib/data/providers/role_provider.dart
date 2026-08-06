import "package:flutter_riverpod/flutter_riverpod.dart";

/// Mirrors App.jsx's top-level `role` state — "trainer" (Coach) or "client",
/// switched via the Coach/Client pill toggle in the shared Header.
class RoleNotifier extends Notifier<String> {
  @override
  String build() => "client";

  void set(String value) => state = value;
}

final roleProvider = NotifierProvider<RoleNotifier, String>(RoleNotifier.new);
