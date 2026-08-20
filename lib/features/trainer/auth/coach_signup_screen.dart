import "dart:convert";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/utils/photo_picker_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/supabase_bootstrap_provider.dart";

/// Real coach self-signup — mirrors TrainerForm.jsx's account-creation
/// fields (photo, name, email, phone, disciplines, a location, password)
/// rather than its full ~800-line staff-onboarding scope (per-discipline
/// session types, weekly availability blocks, bio, before/afters, etc. —
/// all already editable afterward from My Profile/Staff once signed in).
///
/// Two steps, same as the web source: an approval-code gate shown first
/// (`isSelfSignup && !codeOk` in TrainerForm.jsx) — a wrong/expired code
/// stops here with a clear message rather than after filling out the whole
/// form — then the actual create-profile form once the code checks out.
/// The code itself is still sent again at signup time (mark_coach_code_used
/// is the real, race-safe, server-side enforcement; this step is a fast
/// client-side pre-check, same division of labor as the web app's).
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
  final _password2 = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();

  // Mirrors DEFAULT_LOCATION (constants/domain.js) — every trainer starts
  // pointed at the gym's own location; editable inline, matching
  // updateTrainerRow's "the app only edits a single location" precedent.
  final _locationName = TextEditingController(text: "ONE Fitness");
  final _locationAddress = TextEditingController(text: "11300 Magnolia Blvd., North Hollywood, CA 91601");
  bool _editingLocation = false;

  final Set<String> _disciplines = {};
  String? _photoDataUrl;
  bool _pickingPhoto = false;
  String? _error;
  bool _busy = false;

  bool _codeVerified = false;
  String? _codeError;
  bool _verifyingCode = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    _phone.dispose();
    _code.dispose();
    _locationName.dispose();
    _locationAddress.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _codeError = "Enter the approval code you were given.");
      return;
    }
    setState(() {
      _codeError = null;
      _verifyingCode = true;
    });
    try {
      final approval = await SupabaseService.loadCoachApprovalCode();
      final realCode = approval?["code"] as String?;
      final expiresAt = approval?["expires_at"] as String?;
      final usedAt = approval?["used_at"] as String?;
      if (realCode == null || code != realCode) {
        throw Exception("That code is invalid or has expired. Contact ONE Fitness for a current code.");
      }
      if (usedAt != null) {
        throw Exception("That approval code has already been used.");
      }
      if (expiresAt != null && isoToday().compareTo(expiresAt) > 0) {
        throw Exception("That approval code has expired — ask the owner for a new one.");
      }
      if (!mounted) return;
      setState(() {
        _verifyingCode = false;
        _codeVerified = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _codeError = e.toString().replaceFirst("Exception: ", "");
        _verifyingCode = false;
      });
    }
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

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final phone = _phone.text.trim();
    if (name.isEmpty || email.isEmpty || password.isEmpty || phone.isEmpty) {
      setState(() => _error = "Name, email, password, and phone are all required.");
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
    if (_disciplines.isEmpty) {
      setState(() => _error = "Choose at least one discipline.");
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await SupabaseService.signUpCoach(
        email: email,
        password: password,
        name: name,
        phone: phone,
        approvalCode: _code.text.trim(),
        photo: _photoDataUrl,
        disciplines: _disciplines.toList(),
        locationName: _locationName.text.trim(),
        locationAddress: _locationAddress.text.trim(),
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
    if (!_codeVerified) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel("Coach Approval Code"),
                const HintBox(text: "Coach profiles require approval. If you've met with ONE Fitness and been approved, enter the code you were given."),
                const SizedBox(height: 12),
                FieldLabeled(
                  label: "Approval code",
                  child: AppField(controller: _code, placeholder: "000000", onChanged: (_) => setState(() => _codeError = null)),
                ),
                if (_codeError != null) ...[
                  const SizedBox(height: 8),
                  Text(_codeError!, style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    BtnGhost(onPressed: widget.onBack, child: const Text("Back")),
                    const SizedBox(width: 8),
                    Expanded(
                      child: BtnGold(
                        onPressed: _verifyingCode ? null : _verifyCode,
                        full: true,
                        child: _verifyingCode
                            ? const Text("Checking…")
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.lock, size: 15),
                                  SizedBox(width: 6),
                                  Text("Continue"),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BackBar(onBack: () => setState(() => _codeVerified = false), title: "Create coach profile"),
              const SizedBox(height: 10),
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickingPhoto ? null : _pickPhoto,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.line, width: 2),
                          image: _photoDataUrl != null
                              ? DecorationImage(image: MemoryImage(base64Decode(_photoDataUrl!.substring(_photoDataUrl!.indexOf(",") + 1))), fit: BoxFit.cover)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: _photoDataUrl == null ? const Icon(LucideIcons.user, size: 28, color: AppColors.mute) : null,
                      ),
                    ),
                    const SizedBox(height: 8),
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
              FieldLabeled(label: "Full name", child: AppField(controller: _name, placeholder: "First Last", onChanged: (_) => setState(() => _error = null))),
              const SizedBox(height: 10),
              FieldLabeled(
                label: "Email",
                child: AppField(controller: _email, placeholder: "name@email.com", keyboardType: TextInputType.emailAddress, onChanged: (_) => setState(() => _error = null)),
              ),
              const SizedBox(height: 10),
              FieldLabeled(label: "Phone", child: AppField(controller: _phone, keyboardType: TextInputType.phone, onChanged: (_) => setState(() => _error = null))),
              const SizedBox(height: 10),
              FieldLabeled(
                label: "Disciplines (choose one or more)",
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: kDisciplineLabels.entries.map((e) {
                    final on = _disciplines.contains(e.key);
                    return InkWell(
                      onTap: () => setState(() {
                        if (on) {
                          _disciplines.remove(e.key);
                        } else {
                          _disciplines.add(e.key);
                        }
                        _error = null;
                      }),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: on ? AppColors.gold : AppColors.line),
                          color: on ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg,
                        ),
                        child: Text(e.value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? AppColors.gold : AppColors.mute)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              const Text("Where you train", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.txt)),
              const SizedBox(height: 6),
              AppCard(
                child: _editingLocation
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FieldLabeled(label: "Location name", child: AppField(controller: _locationName)),
                          const SizedBox(height: 8),
                          FieldLabeled(label: "Address", child: AppField(controller: _locationAddress)),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => setState(() => _editingLocation = false),
                              style: TextButton.styleFrom(foregroundColor: AppColors.gold),
                              child: const Text("Done"),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_locationName.text.isEmpty ? "Untitled location" : _locationName.text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                if (_locationAddress.text.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(_locationAddress.text, style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _editingLocation = true),
                            icon: const Icon(LucideIcons.pencil, size: 16, color: AppColors.mute),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 10),
              FieldLabeled(
                label: "Create password",
                child: AppField(controller: _password, placeholder: "At least 6 characters", obscureText: true, onChanged: (_) => setState(() => _error = null)),
              ),
              const SizedBox(height: 10),
              FieldLabeled(
                label: "Confirm password",
                child: AppField(controller: _password2, placeholder: "••••••", obscureText: true, onChanged: (_) => setState(() => _error = null)),
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
