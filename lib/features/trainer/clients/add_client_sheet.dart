import "dart:convert";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/photo_picker_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/supabase_bootstrap_provider.dart";

/// Coach/owner adding a client in person — the desk-signup path for someone
/// who isn't going to download the app and register themselves first.
///
/// Deliberately the same page, field for field, as the client's own signup
/// (client_signup_screen.dart): photo, split name, email, password with
/// confirmation, phone, city, birthday, coach code. A coach filling this in
/// on a client's behalf shouldn't have to learn a second form, and the
/// client ends up with an account indistinguishable from one they made
/// themselves. The one difference is what happens after: instead of signing
/// the new account in (that would sign the coach out), a handover screen
/// shows the credentials once so they can be passed on.
///
/// Returns true if an account was created.
Future<bool?> showAddClientSheet(BuildContext context) => Navigator.of(context).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _AddClientPage()),
    );

class _AddClientPage extends ConsumerStatefulWidget {
  const _AddClientPage();

  @override
  ConsumerState<_AddClientPage> createState() => _AddClientPageState();
}

class _AddClientPageState extends ConsumerState<_AddClientPage> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _birthday = TextEditingController();
  final _coachCode = TextEditingController();
  String? _photoDataUrl;
  String? _error;
  bool _busy = false;
  bool _pickingPhoto = false;

  /// Set once the account exists — swaps the form for the handover screen.
  Map<String, dynamic>? _created;

  String get _fullName =>
      [_firstName.text.trim(), _lastName.text.trim()].where((s) => s.isNotEmpty).join(" ");

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    _phone.dispose();
    _city.dispose();
    _birthday.dispose();
    _coachCode.dispose();
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
    if (picked != null) {
      setState(() => _birthday.text =
          "${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}");
    }
  }

  Future<void> _submit() async {
    final firstName = _firstName.text.trim();
    final lastName = _lastName.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final phone = _phone.text.trim();
    final city = _city.text.trim();
    // Same rules as the client's own signup, so an account made here is
    // never one that would have been rejected there.
    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty || phone.isEmpty || city.isEmpty) {
      setState(() => _error = "First name, last name, email, password, phone number, and city are all required.");
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
      final result = await SupabaseService.createClientAccount(
        name: _fullName,
        firstName: firstName,
        lastName: lastName,
        email: email,
        password: password,
        phone: phone,
        city: city,
        birthday: _birthday.text.trim().isEmpty ? null : _birthday.text.trim(),
        coachCode: _coachCode.text.trim().isEmpty ? null : _coachCode.text.trim(),
        photo: _photoDataUrl,
      );
      // Re-seed so the new client shows up in the roster straight away
      // rather than after a restart.
      await loadAndSeedCoreData(ref);
      if (mounted) setState(() => _created = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final created = _created;
    return PopScope(
      // Once the account exists, back means "done" — the caller needs the
      // true so it can refresh, and the handover has already been shown.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, created != null);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: created == null ? _buildForm() : _buildHandover(created),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BackBar(onBack: () => Navigator.pop(context, false), title: "Add a client"),
        const SizedBox(height: 10),
        const Text(
          "Set up their account so they can sign in and start booking sessions. You'll hand them the details at the end.",
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
                        ? DecorationImage(
                            image: MemoryImage(base64Decode(_photoDataUrl!.substring(_photoDataUrl!.indexOf(",") + 1))),
                            fit: BoxFit.cover,
                          )
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
                label: Text(
                  _pickingPhoto ? "Opening…" : (_photoDataUrl != null ? "Change photo" : "Add photo"),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: FieldLabeled(
                label: "First name",
                child: AppField(controller: _firstName, onChanged: (_) => setState(() => _error = null)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FieldLabeled(
                label: "Last name",
                child: AppField(controller: _lastName, onChanged: (_) => setState(() => _error = null)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FieldLabeled(
          label: "Email",
          child: AppField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            placeholder: "name@email.com",
            onChanged: (_) => setState(() => _error = null),
          ),
        ),
        const SizedBox(height: 10),
        FieldLabeled(
          label: "Password",
          child: AppField(
            controller: _password,
            obscureText: true,
            placeholder: "At least 6 characters",
            onChanged: (_) => setState(() => _error = null),
          ),
        ),
        const SizedBox(height: 10),
        FieldLabeled(
          label: "Confirm password",
          child: AppField(
            controller: _password2,
            obscureText: true,
            placeholder: "••••••",
            onChanged: (_) => setState(() => _error = null),
          ),
        ),
        const SizedBox(height: 10),
        FieldLabeled(
          label: "Phone number",
          child: AppField(controller: _phone, keyboardType: TextInputType.phone, onChanged: (_) => setState(() => _error = null)),
        ),
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
        const SizedBox(height: 10),
        FieldLabeled(
          label: "Coach Code (optional)",
          child: AppField(controller: _coachCode, placeholder: "e.g. JESS10"),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            "If a coach gave them a code, enter it here to link their account to that coach.",
            style: TextStyle(fontSize: 11, color: AppColors.mute, fontStyle: FontStyle.italic, height: 1.4),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text("⚠ $_error", style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
        ],
        const SizedBox(height: 18),
        BtnGold(
          full: true,
          onPressed: _busy ? null : _submit,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.userPlus, size: 15),
              const SizedBox(width: 6),
              Text(_busy ? "Creating…" : "Create their profile"),
            ],
          ),
        ),
        const SizedBox(height: 8),
        BtnGhost(
          full: true,
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text("Cancel"),
        ),
      ],
    );
  }

  Widget _buildHandover(Map<String, dynamic> created) {
    final email = created["email"] as String? ?? "";
    final password = created["tempPassword"] as String? ?? "";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BackBar(onBack: () => Navigator.pop(context, true), title: "Client added"),
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(LucideIcons.checkCircle2, size: 18, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "$_fullName is set up",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          "Give them these details to sign in. They can change the password once they're in.",
          style: TextStyle(fontSize: 12, color: AppColors.mute, height: 1.4),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.goldDim),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("EMAIL", style: TextStyle(fontSize: 9.5, color: AppColors.mute, letterSpacing: 1)),
              const SizedBox(height: 2),
              SelectableText(email, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              const Text("PASSWORD", style: TextStyle(fontSize: 9.5, color: AppColors.mute, letterSpacing: 1)),
              const SizedBox(height: 2),
              SelectableText(
                password,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.gold, letterSpacing: 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Shown once and never recoverable — the server doesn't store it in
        // readable form, so if it's lost the only way back is a reset.
        const Text(
          "This password isn't shown again. If it's lost, they'll need to reset it from the sign-in screen.",
          style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: BtnGhost(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: "Email: $email\nPassword: $password"));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Sign-in details copied.")),
                    );
                  }
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [Icon(LucideIcons.copy, size: 14), SizedBox(width: 6), Text("Copy details")],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BtnGold(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Done"),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
