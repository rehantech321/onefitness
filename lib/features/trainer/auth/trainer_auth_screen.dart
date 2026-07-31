import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors TrainerLogin.jsx, trimmed to the two sign-in paths that don't
/// need a second real backend account: coach sign-in (any non-empty
/// email/password, same UI-only convention as the client auth screen) and
/// Owner/Admin sign-in — both just set `trainerAuth`. "Create coach
/// profile" isn't built yet (TrainerForm is an 800+ line staff-onboarding
/// form, its own sizeable feature).
class TrainerAuthScreen extends ConsumerStatefulWidget {
  const TrainerAuthScreen({super.key});

  @override
  ConsumerState<TrainerAuthScreen> createState() => _TrainerAuthScreenState();
}

class _TrainerAuthScreenState extends ConsumerState<TrainerAuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  bool _ownerOpen = false;
  final _ownerEmail = TextEditingController();
  final _ownerPassword = TextEditingController();
  String? _ownerError;
  bool _ownerBusy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _ownerEmail.dispose();
    _ownerPassword.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() {
        _error = "Incorrect email or password.";
        _busy = false;
      });
      return;
    }
    ref.read(trainerAuthProvider.notifier).signIn("demo-marcus");
  }

  Future<void> _ownerSignIn() async {
    setState(() {
      _ownerError = null;
      _ownerBusy = true;
    });
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    if (_ownerEmail.text.trim().isEmpty || _ownerPassword.text.isEmpty) {
      setState(() {
        _ownerError = "Incorrect email or password.";
        _ownerBusy = false;
      });
      return;
    }
    ref.read(trainerAuthProvider.notifier).signIn("owner");
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(image: AssetImage("assets/images/login_bg.jpg"), fit: BoxFit.cover, alignment: Alignment.topCenter),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bg.withValues(alpha: 0), AppColors.bg.withValues(alpha: 0.5), AppColors.bg.withValues(alpha: 0.97)],
            stops: const [0.0, 0.62, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 120),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(
                        child: Text(
                          "Staff",
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w300, letterSpacing: 1),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FieldLabeled(
                        label: "Email",
                        child: AppField(
                          controller: _email,
                          placeholder: "name@email.com",
                          keyboardType: TextInputType.emailAddress,
                          onChanged: (_) => setState(() => _error = null),
                        ),
                      ),
                      const SizedBox(height: 7),
                      FieldLabeled(
                        label: "Password",
                        child: AppField(controller: _password, placeholder: "••••••", obscureText: true, onChanged: (_) => setState(() => _error = null)),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 6),
                        Text(_error!, style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
                      ],
                      const SizedBox(height: 10),
                      BtnGold(
                        onPressed: _busy ? null : _signIn,
                        full: true,
                        child: _busy
                            ? const Text("Signing in…")
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [Icon(LucideIcons.user, size: 15), SizedBox(width: 6), Text("Sign in")],
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: const [
                            Expanded(child: Divider(color: AppColors.line, height: 1)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text("NEW COACH?", style: TextStyle(color: AppColors.mute, fontSize: 11, letterSpacing: 1.5)),
                            ),
                            Expanded(child: Divider(color: AppColors.line, height: 1)),
                          ],
                        ),
                      ),
                      BtnGhost(
                        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Coach sign-up form coming in a later pass.")),
                        ),
                        full: true,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [Icon(LucideIcons.plus, size: 15), SizedBox(width: 6), Text("Create coach profile")],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: const [
                            Expanded(child: Divider(color: AppColors.line, height: 1)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text("OWNER", style: TextStyle(color: AppColors.mute, fontSize: 11, letterSpacing: 1.5)),
                            ),
                            Expanded(child: Divider(color: AppColors.line, height: 1)),
                          ],
                        ),
                      ),
                      if (_ownerOpen)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            border: Border.all(color: AppColors.line),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text("Owner / Admin access", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              FieldLabeled(
                                label: "Email",
                                child: AppField(
                                  controller: _ownerEmail,
                                  placeholder: "name@email.com",
                                  keyboardType: TextInputType.emailAddress,
                                  onChanged: (_) => setState(() => _ownerError = null),
                                ),
                              ),
                              const SizedBox(height: 7),
                              FieldLabeled(
                                label: "Password",
                                child: AppField(
                                  controller: _ownerPassword,
                                  placeholder: "••••••",
                                  obscureText: true,
                                  onChanged: (_) => setState(() => _ownerError = null),
                                ),
                              ),
                              if (_ownerError != null) ...[
                                const SizedBox(height: 8),
                                Text(_ownerError!, style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: BtnGold(
                                      onPressed: _ownerBusy ? null : _ownerSignIn,
                                      full: true,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(LucideIcons.lock, size: 14),
                                          const SizedBox(width: 6),
                                          Text(_ownerBusy ? "Signing in…" : "Enter"),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  BtnGhost(onPressed: () => setState(() => _ownerOpen = false), child: const Text("Cancel")),
                                ],
                              ),
                            ],
                          ),
                        )
                      else
                        BtnGhost(
                          onPressed: () => setState(() => _ownerOpen = true),
                          full: true,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [Icon(LucideIcons.lock, size: 14), SizedBox(width: 6), Text("Owner / Admin login")],
                          ),
                        ),
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          "Owner access manages all clients, staff, and the schedule.",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
