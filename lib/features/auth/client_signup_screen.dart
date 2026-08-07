import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../core/supabase/supabase_service.dart";
import "../../core/theme/app_colors.dart";
import "../../core/widgets/widgets.dart";
import "../../data/providers/supabase_bootstrap_provider.dart";

/// Real self-signup — creates an actual Supabase Auth account + `clients`
/// row + blank `client_records` row (mirrors signUpClient in
/// supabaseData.js), then signs the new client straight in, same as the
/// web app's own self-signup UX. Trimmed relative to the source's
/// IntakeForm.jsx: this covers account creation itself (name/email/
/// password/phone/city/birthday) — the physical assessment, nutrition
/// intake, and waiver-signing steps IntakeForm also bundles in are each
/// their own separate, already-built screens reachable after signing in,
/// not part of creating the account.
class ClientSignupScreen extends ConsumerStatefulWidget {
  const ClientSignupScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<ClientSignupScreen> createState() => _ClientSignupScreenState();
}

class _ClientSignupScreenState extends ConsumerState<ClientSignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _birthday = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _city.dispose();
    _birthday.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _error = "Name, email, and password are required.");
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
      await SupabaseService.signUpClient(
        email: email,
        password: password,
        name: name,
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        city: _city.text.trim().isEmpty ? null : _city.text.trim(),
        birthday: _birthday.text.trim().isEmpty ? null : _birthday.text.trim(),
      );
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
              BackBar(onBack: widget.onBack, title: "Create my profile"),
              const SizedBox(height: 10),
              const Text(
                "Set up your account to start booking sessions and tracking your progress.",
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
              FieldLabeled(label: "City (optional)", child: AppField(controller: _city)),
              const SizedBox(height: 10),
              FieldLabeled(label: "Birthday (optional, YYYY-MM-DD)", child: AppField(controller: _birthday)),
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
                          Text("Create my profile"),
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
