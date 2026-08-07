import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/supabase_bootstrap_provider.dart";
import "coach_signup_screen.dart";

/// Mirrors TrainerLogin.jsx: coach sign-in, real coach self-signup (gated
/// by the staff approval code — see CoachSignupScreen), and Owner/Admin
/// sign-in.
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
  bool _signingUp = false;

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
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = "Enter your email and password.");
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await SupabaseService.signIn(_email.text.trim(), _password.text);
      final profile = await SupabaseService.getSessionProfile();
      if (profile == null || profile["role"] != "coach") {
        await SupabaseService.signOut();
        throw Exception("This account isn't set up as a coach.");
      }
      // Re-fetches roster/trainers/bookings/plans as this now-authenticated
      // coach (RLS returns more/different rows than the anonymous startup
      // bootstrap saw) and sets trainerAuth from the restored session.
      await loadAndSeedCoreData(ref);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Incorrect email or password.";
        _busy = false;
      });
      return;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _ownerSignIn() async {
    if (_ownerEmail.text.trim().isEmpty || _ownerPassword.text.isEmpty) {
      setState(() => _ownerError = "Enter the owner email and password.");
      return;
    }
    setState(() {
      _ownerError = null;
      _ownerBusy = true;
    });
    try {
      await SupabaseService.signIn(_ownerEmail.text.trim(), _ownerPassword.text);
      final profile = await SupabaseService.getSessionProfile();
      if (profile == null || profile["role"] != "owner") {
        await SupabaseService.signOut();
        throw Exception("This account isn't the owner account.");
      }
      await loadAndSeedCoreData(ref);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ownerError = "Incorrect email or password.";
        _ownerBusy = false;
      });
      return;
    }
    if (mounted) setState(() => _ownerBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_signingUp) {
      return CoachSignupScreen(onBack: () => setState(() => _signingUp = false));
    }
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage("assets/images/login_bg.jpg"),
          fit: BoxFit.cover,
          // Centers the photo's own logo within the top half's box.
          alignment: Alignment(0, -0.25),
        ),
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Exactly half the screen reserved for the photo, so the
                    // logo lands centered in the top half regardless of how
                    // tall the (fairly long) staff sign-in form is below it.
                    SizedBox(height: constraints.maxHeight * 0.5),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Center(
                            child: Text(
                              "Staff",
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w300, letterSpacing: 1),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FieldLabeled(
                            label: "Email",
                            child: AppField(
                              controller: _email,
                              placeholder: "name@email.com",
                              keyboardType: TextInputType.emailAddress,
                              onChanged: (_) => setState(() => _error = null),
                            ),
                          ),
                          const SizedBox(height: 5),
                          FieldLabeled(
                            label: "Password",
                            child: AppField(controller: _password, placeholder: "••••••", obscureText: true, onChanged: (_) => setState(() => _error = null)),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 5),
                            Text(_error!, style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
                          ],
                          const SizedBox(height: 6),
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
                        padding: const EdgeInsets.symmetric(vertical: 8),
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
                        onPressed: () => setState(() => _signingUp = true),
                        full: true,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [Icon(LucideIcons.plus, size: 15), SizedBox(width: 6), Text("Create coach profile")],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
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
                              const SizedBox(height: 5),
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
                              const SizedBox(height: 8),
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
              );
            },
          ),
        ),
      ),
    );
  }
}
