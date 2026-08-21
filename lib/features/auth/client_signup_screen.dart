import "dart:convert";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../core/supabase/supabase_service.dart";
import "../../core/theme/app_colors.dart";
import "../../core/utils/photo_picker_utils.dart";
import "../../core/widgets/widgets.dart";
import "../../data/providers/client_providers.dart";
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
  final _password2 = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _birthday = TextEditingController();
  String? _photoDataUrl;
  String? _error;
  bool _busy = false;
  bool _pickingPhoto = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    _phone.dispose();
    _city.dispose();
    _birthday.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() => _pickingPhoto = true);
    final dataUrl = await pickProfilePhotoDataUrl(context);
    if (!mounted) return;
    setState(() {
      _pickingPhoto = false;
      if (dataUrl != null) _photoDataUrl = dataUrl;
    });
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_birthday.text) ?? DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 100),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthday.text = "${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}");
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final phone = _phone.text.trim();
    final city = _city.text.trim();
    if (name.isEmpty || email.isEmpty || password.isEmpty || phone.isEmpty || city.isEmpty) {
      setState(() => _error = "Name, email, password, phone number, and city are all required.");
      return;
    }
    if (password.length < 6) {
      setState(() => _error = "Password must be at least 6 characters.");
      return;
    }
    if (password != _password2.text) {
      setState(() => _error = "Passwords don't match.");
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final userId = await SupabaseService.signUpClient(
        email: email,
        password: password,
        name: name,
        phone: phone,
        city: city,
        birthday: _birthday.text.trim().isEmpty ? null : _birthday.text.trim(),
      );
      if (_photoDataUrl != null) {
        await SupabaseService.updateClientRow(userId, photo: _photoDataUrl);
      }
      ref.read(clientSigningUpProvider.notifier).set(false);
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.onBack();
      },
      child: Scaffold(
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
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickingPhoto ? null : _pickPhoto,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.line, width: 2),
                          image: _photoDataUrl != null
                              ? DecorationImage(image: MemoryImage(base64Decode(_photoDataUrl!.substring(_photoDataUrl!.indexOf(",") + 1))), fit: BoxFit.cover)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: _photoDataUrl == null ? const Icon(LucideIcons.user, size: 30, color: AppColors.mute) : null,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _pickingPhoto ? null : _pickPhoto,
                      style: TextButton.styleFrom(foregroundColor: AppColors.gold),
                      icon: const Icon(LucideIcons.image, size: 14),
                      label: Text(_pickingPhoto ? "Opening…" : (_photoDataUrl != null ? "Change photo" : "Add photo"), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
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
              FieldLabeled(
                label: "Confirm password",
                child: AppField(controller: _password2, placeholder: "••••••", obscureText: true, onChanged: (_) => setState(() => _error = null)),
              ),
              const SizedBox(height: 10),
              FieldLabeled(label: "Phone number", child: AppField(controller: _phone, keyboardType: TextInputType.phone, onChanged: (_) => setState(() => _error = null))),
              const SizedBox(height: 10),
              FieldLabeled(
                label: "City",
                child: AppField(controller: _city, onChanged: (_) => setState(() => _error = null)),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text("Personalized training near you", style: TextStyle(fontSize: 11, color: AppColors.mute, fontStyle: FontStyle.italic)),
              ),
              const SizedBox(height: 10),
              FieldLabeled(
                label: "Birthday (optional)",
                child: InkWell(
                  onTap: _pickBirthday,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.bg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
                    ),
                    child: Text(
                      _birthday.text.isEmpty ? "Select date" : _birthday.text,
                      style: TextStyle(fontSize: 14, color: _birthday.text.isEmpty ? AppColors.mute : AppColors.txt),
                    ),
                  ),
                ),
              ),
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
      ),
    );
  }
}
