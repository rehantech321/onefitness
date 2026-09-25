import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../supabase/supabase_service.dart";
import "../theme/app_colors.dart";
import "widgets.dart";

/// Permanent, self-service account deletion — Apple App Review guideline
/// 5.1.1(v). Reachable in two taps (Menu -> Profile Settings -> Delete
/// Account) for clients and coaches alike, with no email or phone call to
/// support involved, and no "deactivate" half-measure.
///
/// The confirmation is deliberately awkward: the exact word DELETE has to be
/// typed. This is irreversible, and a mis-tap shouldn't cost someone their
/// training history.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({
    super.key,
    required this.onBack,
    required this.onDeleted,
    this.isCoach = false,
  });

  final VoidCallback onBack;

  /// Runs after the server confirms deletion — the caller signs out and
  /// returns to the welcome screen.
  final VoidCallback onDeleted;

  final bool isCoach;

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  bool get _typedDelete => _confirm.text.trim().toUpperCase() == "DELETE";

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_typedDelete || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.deleteMyAccount();
      if (!mounted) return;
      widget.onDeleted();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e
            .toString()
            .replaceFirst("Exception: ", "")
            .replaceFirst("AuthException: ", "");
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final goes = widget.isCoach
        ? const [
            "Your coach profile, photo, bio and before/after gallery",
            "Your availability and any upcoming sessions, which are cancelled — your clients are told",
            "Your messages and anything you've posted",
            "Your sign-in — the email becomes free to use again",
          ]
        : const [
            "Your profile, photo and progress photos",
            "Your workout and nutrition programs, habits and logged sessions",
            "Any upcoming sessions, which are cancelled — your coach is told",
            "Your messages and anything you've posted",
            "Your saved cards, and any active membership is cancelled in Stripe",
            "Your sign-in — the email becomes free to use again",
          ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BackBar(onBack: widget.onBack, title: "Delete Account"),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.errorText.withValues(alpha: 0.08),
              border: Border.all(color: AppColors.errorText),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(LucideIcons.triangleAlert, size: 18, color: AppColors.errorText),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "This is permanent. Your account and data are deleted "
                    "straight away and cannot be recovered.",
                    style: TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            "WHAT GETS DELETED",
            style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          for (final line in goes)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(LucideIcons.x, size: 12, color: AppColors.errorText),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(line, style: const TextStyle(fontSize: 12.5, height: 1.5)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          const Text(
            "WHAT WE HAVE TO KEEP",
            style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          const Text(
            "Payment and booking records we're required to keep for tax and "
            "accounting are retained, with your name and personal details "
            "removed so they can't be traced back to you.",
            style: TextStyle(fontSize: 12.5, color: AppColors.mute, height: 1.5),
          ),
          const SizedBox(height: 20),
          FieldLabeled(
            label: "Type DELETE to confirm",
            child: AppField(
              controller: _confirm,
              placeholder: "DELETE",
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_typedDelete && !_busy) ? _delete : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.errorText,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.line,
                disabledForegroundColor: AppColors.mute,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                _busy ? "Deleting your account…" : "Delete my account permanently",
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 8),
          BtnGhost(
            onPressed: _busy ? null : widget.onBack,
            full: true,
            child: const Text("Keep my account"),
          ),
        ],
      ),
    );
  }
}
