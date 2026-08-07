import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/supabase_bootstrap_provider.dart";

/// Real coach self-signup — mirrors TrainerForm.jsx's account-creation
/// step, trimmed to what makes an account (name/email/password/phone +
/// the staff approval code) rather than its full ~800-line staff-onboarding
/// scope (availability setup, bio, before/afters, etc. — all already
/// editable afterward from My Profile/Staff once signed in).
class CoachSignupScreen extends ConsumerStatefulWidget {
  const CoachSignupScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<CoachSignupScreen> createState() => _CoachSignupScreenState();
}

class _CoachSignupScreenState extends ConsumerState<CoachSignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final code = _code.text.trim();
    if (name.isEmpty || email.isEmpty || password.isEmpty || code.isEmpty) {
      setState(() => _error = "Name, email, password, and the staff approval code are all required.");
      return;
    }
    if (password.length < 6) {
      setState(() => _error = "Password must be at least 6 characters.");
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      // Client-side check for a fast, clear error — the server-side
      // mark_coach_code_used RPC is the real enforcement (see
      // SupabaseService.signUpCoach), so a wrong/expired code caught here
      // is a UX nicety, not the actual security boundary.
      final approval = await SupabaseService.loadCoachApprovalCode();
      final realCode = approval?["code"] as String?;
      final expiresAt = approval?["expires_at"] as String?;
      final usedAt = approval?["used_at"] as String?;
      if (realCode == null || code != realCode) {
        throw Exception("That approval code isn't valid — check with the gym owner.");
      }
      if (usedAt != null) {
        throw Exception("That approval code has already been used.");
      }
      if (expiresAt != null && isoToday().compareTo(expiresAt) > 0) {
        throw Exception("That approval code has expired — ask the owner for a new one.");
      }
      await SupabaseService.signUpCoach(email: email, password: password, name: name, phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(), approvalCode: code);
      await loadAndSeedCoreData(ref);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst("Exception: ", "").replaceFirst("AuthException: ", "");
        _busy = false;
      });
      return;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BackBar(onBack: widget.onBack, title: "Create coach profile"),
              const SizedBox(height: 10),
              const Text(
                "You'll need the staff approval code from the gym owner to create a coach account.",
                style: TextStyle(color: AppColors.mute, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 14),
              FieldLabeled(label: "Full name", child: AppField(controller: _name, onChanged: (_) => setState(() => _error = null))),
              const SizedBox(height: 10),
              FieldLabeled(
                label: "Email",
                child: AppField(controller: _email, placeholder: "name@email.com", keyboardType: TextInputType.emailAddress, onChanged: (_) => setState(() => _error = null)),
              ),
              const SizedBox(height: 10),
              FieldLabeled(
                label: "Password",
                child: AppField(controller: _password, placeholder: "At least 6 characters", obscureText: true, onChanged: (_) => setState(() => _error = null)),
              ),
              const SizedBox(height: 10),
              FieldLabeled(label: "Phone (optional)", child: AppField(controller: _phone, keyboardType: TextInputType.phone)),
              const SizedBox(height: 10),
              FieldLabeled(label: "Staff approval code", child: AppField(controller: _code, onChanged: (_) => setState(() => _error = null))),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              BtnGold(
                onPressed: _busy ? null : _submit,
                full: true,
                child: _busy
                    ? const Text("Creating your profile…")
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.userPlus, size: 15),
                          SizedBox(width: 6),
                          Text("Create coach profile"),
                        ],
                      ),
              ),
              const SizedBox(height: 10),
              BtnGhost(onPressed: widget.onBack, full: true, child: const Text("Back to sign in")),
            ],
          ),
        ),
      ),
    );
  }
}
