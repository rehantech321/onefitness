import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/client_providers.dart";

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
    // Deliberately loose: numbers arrive with spaces, dashes, brackets and
    // country codes. Enough digits to be a real number is the whole test.
    final digits = phone.replaceAll(RegExp(r"[^0-9]"), "");
    if (digits.length < 7) {
      setState(() => _error = "Enter a phone number your coach can reach you on.");
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final id = ref.read(clientInfoProvider).id;
      await SupabaseService.updateClientRow(id, phone: phone);
      ref.read(clientInfoProvider.notifier).update((i) => i.copyWith(phone: phone));
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
