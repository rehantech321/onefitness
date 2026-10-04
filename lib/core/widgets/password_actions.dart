import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../supabase/supabase_service.dart";
import "../theme/app_colors.dart";
import "../../data/providers/trainer_providers.dart";
import "widgets.dart";

/// The two ways staff can deal with someone who can't get in, side by side:
///
///   Send reset email  — the normal route. The person follows a link and
///                       chooses their own password; nobody else ever knows
///                       it. Available to any staff member.
///   Set a password    — the desk route, for someone locked out with no
///                       access to their email. Owner only, because being
///                       able to set another account's password is a way to
///                       take over the owner's account.
///
/// Used on both the coach profile form and the client profile, so the two
/// can't drift apart.
class PasswordActions extends ConsumerStatefulWidget {
  const PasswordActions({
    super.key,
    required this.profileId,
    required this.email,
    required this.name,
  });

  /// Null while a brand-new account is still being created — setting a
  /// password needs an account to set it on.
  final String? profileId;
  final String email;
  final String name;

  @override
  ConsumerState<PasswordActions> createState() => _PasswordActionsState();
}

class _PasswordActionsState extends ConsumerState<PasswordActions> {
  bool _busy = false;
  String? _message;
  bool _isError = false;

  void _say(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = msg;
      _isError = error;
      _busy = false;
    });
  }

  Future<void> _sendReset() async {
    final email = widget.email.trim();
    if (email.isEmpty) {
      _say("This account has no email address, so a reset link can't be sent.", error: true);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await SupabaseService.sendPasswordReset(email);
      _say("Reset link sent to $email.");
    } catch (_) {
      _say("Couldn't send the reset email — check your connection and try again.", error: true);
    }
  }

  Future<void> _setPassword() async {
    final id = widget.profileId;
    if (id == null) {
      _say("Save this profile first, then you can set a password.", error: true);
      return;
    }
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => _SetPasswordDialog(name: widget.name),
    );
    if (chosen == null || !mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await SupabaseService.adminSetPassword(profileId: id, password: chosen);
      _say("Password updated. Tell ${widget.name} the new password and ask them to change it after signing in.");
    } catch (e) {
      _say(e.toString().replaceFirst("Exception: ", ""), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = ref.watch(trainerAuthProvider) == "owner";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        const Text(
          "Password",
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.txt),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _sendReset,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.gold,
                  side: const BorderSide(color: AppColors.goldDim),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                ),
                icon: const Icon(LucideIcons.mail, size: 13),
                label: const Text("Send reset email",
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
            ),
            if (isOwner) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _setPassword,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.mute,
                    side: const BorderSide(color: AppColors.line),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                  icon: const Icon(LucideIcons.keyRound, size: 13),
                  label: const Text("Set a password",
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            isOwner
                ? "A reset email lets them choose their own password. Setting one yourself is for someone locked out with no access to their email."
                : "Sends a link so they can choose a new password themselves.",
            style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
          ),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _message!,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: _isError ? AppColors.errorText : AppColors.gold,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _SetPasswordDialog extends StatefulWidget {
  const _SetPasswordDialog({required this.name});
  final String name;

  @override
  State<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<_SetPasswordDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _submit() {
    final a = _a.text, b = _b.text;
    if (a.length < 8) {
      setState(() => _error = "Use at least 8 characters.");
      return;
    }
    if (a != b) {
      setState(() => _error = "The two passwords don't match.");
      return;
    }
    Navigator.of(context).pop(a);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text("Set a password for ${widget.name}",
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "They'll be able to sign in with this straight away. Tell them in "
            "person and ask them to change it once they're in — anyone who "
            "overhears it can use it.",
            style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.mute),
          ),
          const SizedBox(height: 14),
          FieldLabeled(
            label: "New password",
            child: AppField(kind: FieldKind.password,
              controller: _a,
              obscureText: true,
              placeholder: "At least 8 characters",
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
          const SizedBox(height: 8),
          FieldLabeled(
            label: "Confirm password",
            child: AppField(kind: FieldKind.password,
              controller: _b,
              obscureText: true,
              placeholder: "••••••••",
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  style: const TextStyle(fontSize: 12, color: AppColors.errorText)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: AppColors.mute),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: _submit,
          style: TextButton.styleFrom(foregroundColor: AppColors.gold),
          child: const Text("Set password", style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
