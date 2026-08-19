import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../core/supabase/supabase_service.dart";
import "../../core/theme/app_colors.dart";
import "../../core/utils/auth_error.dart";
import "../../core/widgets/widgets.dart";
import "../../data/providers/client_providers.dart";
import "../../data/providers/supabase_bootstrap_provider.dart";
import "client_signup_screen.dart";

const _businessName = "ONE Fitness";

/// Mirrors ClientView.jsx's unauthenticated state — the client sign-in
/// screen, background photo with a bottom-anchored compact form. Tapping
/// "Create my profile" opens ClientSignupScreen (real self-signup).
class ClientAuthScreen extends ConsumerStatefulWidget {
  const ClientAuthScreen({super.key});

  @override
  ConsumerState<ClientAuthScreen> createState() => _ClientAuthScreenState();
}

class _ClientAuthScreenState extends ConsumerState<ClientAuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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
      if (profile == null || profile["role"] != "client") {
        await SupabaseService.signOut();
        throw Exception("This account isn't set up as a client.");
      }
      // Re-fetches roster/trainers/bookings/plans as this now-authenticated
      // user (RLS returns more/different rows than the anonymous startup
      // bootstrap saw) and sets clientInfo/clientRecord/clientBookings/
      // clientSignedIn from the freshly-restored session in one pass.
      await loadAndSeedCoreData(ref);
    } catch (e, st) {
      // ignore: avoid_print
      print("[client sign-in] failed: $e\n$st");
      if (!mounted) return;
      setState(() {
        _error = authErrorMessage(e);
        _busy = false;
      });
      return;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(clientSigningUpProvider)) {
      return ClientSignupScreen(onBack: () => ref.read(clientSigningUpProvider.notifier).set(false));
    }
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/login_bg.jpg"),
            fit: BoxFit.cover,
            // Centers the photo's own logo within whatever height the top
            // half ends up being, nudged up slightly per request.
            alignment: Alignment(0, -0.25),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.bg.withValues(alpha: 0),
                AppColors.bg.withValues(alpha: 0.5),
                AppColors.bg.withValues(alpha: 0.97),
              ],
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
                        // Exactly half the screen reserved for the photo
                        // (rather than a flex spacer that shrinks to fit the
                        // form) so the logo lands centered in the top half
                        // and the form — tightened up so it fits in the
                        // bottom half without needing a scroll on a typical
                        // phone — starts right at the midpoint.
                        SizedBox(height: constraints.maxHeight * 0.5),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Column(
                                children: [
                                  Text(
                                    "Welcome to ${_businessName.toUpperCase()}",
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w300,
                                      fontSize: 19,
                                      letterSpacing: 0.4,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    "Sign in to your account",
                                    style: TextStyle(color: AppColors.mute, fontSize: 12),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
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
                                child: AppField(
                                  controller: _password,
                                  placeholder: "••••••",
                                  obscureText: true,
                                  onChanged: (_) => setState(() => _error = null),
                                ),
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
                                        children: [
                                          Icon(LucideIcons.user, size: 15),
                                          SizedBox(width: 6),
                                          Text("Sign in"),
                                        ],
                                      ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: const [
                                    Expanded(child: Divider(color: AppColors.line, height: 1)),
                                    Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 10),
                                      child: Text(
                                        "NEW HERE?",
                                        style: TextStyle(color: AppColors.mute, fontSize: 11, letterSpacing: 1.5),
                                      ),
                                    ),
                                    Expanded(child: Divider(color: AppColors.line, height: 1)),
                                  ],
                                ),
                              ),
                              BtnGhost(
                                onPressed: () => ref.read(clientSigningUpProvider.notifier).set(true),
                                full: true,
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.plus, size: 15),
                                    SizedBox(width: 6),
                                    Text("Create my profile"),
                                  ],
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
      ),
    );
  }
}
