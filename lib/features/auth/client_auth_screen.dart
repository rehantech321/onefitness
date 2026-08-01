import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../core/theme/app_colors.dart";
import "../../core/widgets/widgets.dart";
import "../../data/providers/client_providers.dart";

const _businessName = "ONE Fitness";

/// Mirrors ClientView.jsx's unauthenticated state — the client sign-in
/// screen, background photo with a bottom-anchored compact form.
/// Sign-up (IntakeForm) is a large multi-step form covered in a later pass;
/// tapping "Create my profile" is a placeholder for now.
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
    setState(() {
      _error = null;
      _busy = true;
    });
    // UI-only phase: any non-empty email/password "signs in" as the demo
    // client. Real Supabase auth is wired up in a later pass.
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() {
        _error = "Incorrect email or password.";
        _busy = false;
      });
      return;
    }
    ref.read(clientSignedInProvider.notifier).signIn();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/login_bg.jpg"),
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
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
            child: Column(
              children: [
                // Reserves ~2/3 of the screen for the photo — mirrors the
                // web version's `flexGrow:2` spacer. The form below is
                // sized to its own content (like the web version's
                // `flexGrow:1, flexBasis:0` sibling, which flexbox never
                // shrinks below min-content), so it never gets clipped on
                // short viewports; this spacer just absorbs the remainder.
                const Expanded(flex: 2, child: SizedBox.shrink()),
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
                                fontSize: 20,
                                letterSpacing: 0.4,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              "Sign in to your account",
                              style: TextStyle(color: AppColors.mute, fontSize: 12),
                            ),
                          ],
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
                          child: AppField(
                            controller: _password,
                            placeholder: "••••••",
                            obscureText: true,
                            onChanged: (_) => setState(() => _error = null),
                          ),
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
                                  children: [
                                    Icon(LucideIcons.user, size: 15),
                                    SizedBox(width: 6),
                                    Text("Sign in"),
                                  ],
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Sign-up form coming in a later pass.")),
                            );
                          },
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
          ),
        ),
      ),
    );
  }
}
