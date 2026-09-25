import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/client_providers.dart";

/// Saves a phone number onto the signed-in client's profile and keeps the
/// in-memory copy in step. Shared by the full-screen prompt below and the
/// dialog, so there's one place that knows how a number is stored.
Future<void> savePhoneNumber(WidgetRef ref, String phone) async {
  final id = ref.read(clientInfoProvider).id;
  await SupabaseService.updateClientRow(id, phone: phone);
  ref.read(clientInfoProvider.notifier).update((i) => i.copyWith(phone: phone));
}

/// Loose on purpose: numbers arrive with spaces, dashes, brackets and
/// country codes. Enough digits to be a real number is the whole test.
bool isUsablePhone(String raw) =>
    raw.replaceAll(RegExp(r"[^0-9]"), "").length >= 7;

/// Whether the signed-in client still needs to give us a number.
bool clientNeedsPhone(WidgetRef ref) =>
    (ref.read(clientInfoProvider).phone ?? "").trim().isEmpty;

/// A compact version of [AddPhoneScreen] for places that shouldn't leave the
/// current screen — picking In App / SMS in Chat, where taking the client
/// away from the conversation to a separate page would lose their place.
///
/// Returns true once a number is saved, false if they backed out.
Future<bool> promptForPhoneDialog(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PhoneDialog(ref: ref, reason: reason),
  );
  return saved ?? false;
}

/// A StatefulWidget rather than a controller created beside `showDialog`:
/// the dialog keeps building through its close animation, so a controller
/// disposed the moment `showDialog` returns is used after disposal and
/// throws. Owning it here ties its life to the dialog's own.
class _PhoneDialog extends StatefulWidget {
  const _PhoneDialog({required this.ref, required this.reason});
  final WidgetRef ref;
  final String reason;

  @override
  State<_PhoneDialog> createState() => _PhoneDialogState();
}

class _PhoneDialogState extends State<_PhoneDialog> {
  late final _controller = TextEditingController(
    text: widget.ref.read(clientInfoProvider).phone ?? "",
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final phone = _controller.text.trim();
    if (!isUsablePhone(phone)) {
      setState(() => _error = "Enter a number your coach can reach you on.");
      return;
    }
    setState(() => _busy = true);
    try {
      await savePhoneNumber(widget.ref, phone);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't save — check your connection.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text(
        "Add your phone number",
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.reason, style: const TextStyle(fontSize: 13, height: 1.5)),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.phone,
            autofocus: true,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: "e.g. (555) 010-0199",
              hintStyle: const TextStyle(color: AppColors.mute, fontSize: 14),
              filled: true,
              fillColor: AppColors.bg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _busy ? null : _save(),
          ),
          const SizedBox(height: 8),
          const Text(
            "Saved to your profile. Only your coach and ONE Fitness staff can see it, and you can change it any time in Profile Settings.",
            style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: AppColors.mute),
          child: const Text("Not now"),
        ),
        TextButton(
          onPressed: _busy ? null : _save,
          style: TextButton.styleFrom(foregroundColor: AppColors.gold),
          child: Text(_busy ? "Saving…" : "Save",
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

/// Asked for at the one point it's genuinely needed — buying a plan, which
/// commits the client to in-person sessions a coach has to coordinate.
///
/// Signup deliberately doesn't require a phone number (Apple guideline
/// 5.1.1: don't demand personal information that isn't essential to the
/// core function). This is that information becoming essential, with the
/// reason stated plainly rather than collected up front "just in case".
class AddPhoneScreen extends ConsumerStatefulWidget {
  const AddPhoneScreen({
    super.key,
    required this.onBack,
    required this.onSaved,
    this.reason =
        "Your coach needs your phone number to coordinate your sessions.",
  });

  final VoidCallback onBack;

  /// Runs once the number is stored — the caller carries on with whatever
  /// it was doing (buying the plan, confirming the booking).
  final VoidCallback onSaved;

  final String reason;

  @override
  ConsumerState<AddPhoneScreen> createState() => _AddPhoneScreenState();
}

class _AddPhoneScreenState extends ConsumerState<AddPhoneScreen> {
  late final _phone = TextEditingController(
    text: ref.read(clientInfoProvider).phone ?? "",
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final phone = _phone.text.trim();
    if (!isUsablePhone(phone)) {
      setState(() => _error = "Enter a phone number your coach can reach you on.");
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await savePhoneNumber(ref, phone);
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't save your number — check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BackBar(onBack: widget.onBack, title: "Add your phone number"),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.08),
              border: Border.all(color: AppColors.gold),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              widget.reason,
              style: const TextStyle(fontSize: 13, color: AppColors.txt, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          FieldLabeled(
            label: "Phone number",
            child: AppField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              placeholder: "e.g. (555) 010-0199",
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              "Only your coach and ONE Fitness staff can see this. You can change it any time in Profile Settings.",
              style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
          ],
          const SizedBox(height: 18),
          BtnGold(
            full: true,
            onPressed: _busy ? null : _save,
            child: Text(_busy ? "Saving…" : "Save and continue"),
          ),
          const SizedBox(height: 8),
          BtnGhost(onPressed: widget.onBack, full: true, child: const Text("Cancel")),
        ],
      ),
    );
  }
}
