import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "package:url_launcher/url_launcher.dart";
import "../theme/app_colors.dart";
import "../../data/providers/platform_settings_provider.dart";
import "../../data/providers/trainer_providers.dart";
import "widgets.dart";

/// The gym's phone number as typed by the owner, as dialable digits —
/// "818-223-7001", "(818) 223 7001" and "+1 818 223 7001" all work.
String dialableNumber(String raw) => raw.replaceAll(RegExp(r"[^0-9+]"), "");

/// Nicely spaced US-style display for a plain 10-digit number; anything else
/// (an international number, an extension) is shown exactly as it was typed.
String prettyPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r"[^0-9]"), "");
  if (raw.trim().startsWith("+") || digits.length != 10) return raw.trim();
  return "${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}";
}

/// Opens the phone's own dialer on [raw], pre-filled but not dialled — the
/// person still presses call. Returns false when the device has no dialer
/// (a tablet without a SIM, most emulators).
Future<bool> callNumber(String raw) async {
  final number = dialableNumber(raw);
  if (number.isEmpty) return false;
  try {
    return await launchUrl(Uri(scheme: "tel", path: number));
  } catch (_) {
    return false;
  }
}

/// A call button for the Chat screens — tapping it dials the gym. Hidden
/// when no number is set (Customize Platform → Location).
class CallGymButton extends ConsumerWidget {
  const CallGymButton({super.key, this.compact = false});

  /// Icon only, for a tight header row.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = ref.watch(platformSettingsProvider).supportPhone;
    if (phone.trim().isEmpty) return const SizedBox.shrink();

    Future<void> call() async {
      final ok = await callNumber(phone);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't open the dialer — call ${prettyPhone(phone)}.")),
        );
      }
    }

    if (compact) {
      return IconButton(
        tooltip: "Call ${prettyPhone(phone)}",
        onPressed: call,
        icon: const Icon(LucideIcons.phone, size: 18, color: AppColors.gold),
      );
    }
    return OutlinedButton.icon(
      onPressed: call,
      style: OutlinedButton.styleFrom(foregroundColor: AppColors.gold, side: const BorderSide(color: AppColors.goldDim)),
      icon: const Icon(LucideIcons.phone, size: 14),
      label: Text("Call ${prettyPhone(phone)}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// The Support page in both menus: the gym's number, one tap to call.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(platformSettingsProvider);
    final phone = settings.supportPhone.trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel("Support"),
          // The empty state used to tell everyone — clients included — to
          // "add one under Customize Platform → Location". That's a screen
          // only the owner can open, so a client was being handed an
          // instruction they can't act on and no way to get help.
          if (phone.isEmpty)
            HintBox(
              text: ref.watch(trainerAuthProvider) == "owner"
                  ? "No support number set yet. Add one under Customize Platform → Location and it will appear here, on the Support page, and on the Chat call button — for clients and coaches alike."
                  : "No support number has been set up yet. In the meantime, message your coach from the Chat tab and they'll help.",
            )
          else
            AppCard(
              borderColor: AppColors.goldDim,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settings.businessName.isEmpty ? "Call us" : "Call ${settings.businessName}",
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Questions about your membership, a booking or anything else — give us a call.",
                    style: TextStyle(fontSize: 12.5, color: AppColors.mute, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(LucideIcons.phone, size: 16, color: AppColors.gold),
                      const SizedBox(width: 8),
                      Text(
                        prettyPhone(phone),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.gold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  BtnGold(
                    full: true,
                    onPressed: () async {
                      final ok = await callNumber(phone);
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Couldn't open the dialer — call ${prettyPhone(phone)}.")),
                        );
                      }
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.phone, size: 15, color: Colors.white),
                        SizedBox(width: 8),
                        Text("Call now"),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (settings.locationName.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            const SectionLabel("Where to find us"),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(settings.locationName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  if (settings.locationAddress.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(settings.locationAddress, style: const TextStyle(fontSize: 12.5, color: AppColors.mute)),
                    ),
                  if (settings.locationHint.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(settings.locationHint, style: const TextStyle(fontSize: 12, color: AppColors.mute, height: 1.4)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
