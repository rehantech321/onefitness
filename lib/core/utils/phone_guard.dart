import "package:flutter/widgets.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../data/providers/platform_settings_provider.dart";
import "../../data/providers/trainer_providers.dart";

/// Keeps the gym's own support number (Customize Platform → Location) from
/// being saved as a client's or coach's personal phone. Texts and calls
/// meant for that person would otherwise go to the gym's line instead.
///
/// The owner is exempt. The gym's line is usually the owner's own phone, so
/// their own profile — and any profile they fill in themselves — is a
/// deliberate choice, not the mistake this guard exists to catch. Coaches
/// and clients are still stopped.

/// Digits only, with a leading US country code dropped, so "818-223-7001",
/// "(818) 223 7001" and "+1 818 223 7001" all compare equal.
String _digits(String raw) {
  final d = raw.replaceAll(RegExp(r"\D"), "");
  return d.length == 11 && d.startsWith("1") ? d.substring(1) : d;
}

bool isGymSupportNumber(String phone, String supportPhone) {
  final a = _digits(phone);
  return a.length >= 7 && a == _digits(supportPhone);
}

const kGymNumberError =
    "That's the gym's own number. Please enter your own phone number.";

/// [kGymNumberError] when [phone] is the gym's support number, else null.
/// Null for the owner whoever they're editing — see the note above.
/// Takes a BuildContext so plain StatefulWidgets can use it too.
String? gymNumberError(BuildContext context, String phone) {
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(trainerAuthProvider) == "owner") return null;
  final support = container.read(platformSettingsProvider).supportPhone;
  return isGymSupportNumber(phone, support) ? kGymNumberError : null;
}
