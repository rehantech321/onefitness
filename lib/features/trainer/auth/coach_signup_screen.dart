import "dart:convert";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/legal/terms_screen.dart";
import "../../../core/legal/terms_text.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/utils/photo_picker_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/availability_block.dart";
import "../staff/availability_block_editor.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/supabase_bootstrap_provider.dart";

/// Real coach self-signup — mirrors TrainerForm.jsx's account-creation
/// fields (photo, name, email, phone, disciplines, a location, bio,
/// before/after portfolio photos, password) rather than its full ~800-line
/// staff-onboarding scope (per-discipline session types, weekly
/// availability blocks, etc. — still only editable afterward from My
/// Profile/Staff once signed in). Bio and before/afters are both visible to
/// every client immediately via CoachProfileCard (booking flow's "Meet the
/// Coach" card) as soon as the coach account exists.
///
/// Two steps, same as the web source: an approval-code gate shown first
/// (`isSelfSignup && !codeOk` in TrainerForm.jsx) — a wrong/expired code
/// stops here with a clear message rather than after filling out the whole
/// form — then the actual create-profile form once the code checks out.
/// The code itself is still sent again at signup time (mark_coach_code_used
/// is the real, race-safe, server-side enforcement; this step is a fast
/// client-side pre-check, same division of labor as the web app's).
class CoachSignupScreen extends ConsumerStatefulWidget {
  const CoachSignupScreen({
    super.key,
    required this.onBack,
    this.debugSkipCodeGate = false,
  });

  final VoidCallback onBack;

  /// Tests only — starts past the approval-code step so the profile form
  /// itself can be driven without a live Supabase approval code.
  @visibleForTesting
  final bool debugSkipCodeGate;

  @override
  ConsumerState<CoachSignupScreen> createState() => _CoachSignupScreenState();
}

class _CoachSignupScreenState extends ConsumerState<CoachSignupScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  // Defaulted rather than left blank: nearly every coach is a
  // "Coach", and a blank title would show clients a bare first name.
  final _title = TextEditingController(text: "Coach");
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();

  // Mirrors DEFAULT_LOCATION (constants/domain.js) — every trainer starts
  // pointed at the gym's own location; editable inline, matching
  // updateTrainerRow's "the app only edits a single location" precedent.
  final _locationName = TextEditingController(text: "ONE Fitness");
  final _locationAddress = TextEditingController(
    text: "11300 Magnolia Blvd., North Hollywood, CA 91601",
  );
  bool _editingLocation = false;

  final Set<String> _disciplines = {};

  /// Which session types this coach runs — the gym's own list, exactly as
  /// the owner set it up in Customize Platform → Services. Collected here
  /// (rather than left for My Profile later) because the booking flow only
  /// offers a coach for the types they actually hold.
  final Set<String> _sessionTypes = {};

  /// Apple guideline 5.1.1 — an age confirmation instead of a date of birth.
  bool _over18 = false;

  /// Apple guideline 1.2 — signup is blocked until the Terms are accepted.
  bool _agreedToTerms = false;

  /// Shows the full Terms over the form without losing anything typed.
  bool _readingTerms = false;

  /// Optional at signup — a coach can leave it empty and set it later from
  /// their profile. Collected here because a coach with no availability is
  /// invisible in the booking flow, which is a confusing first experience
  /// for someone who just finished signing up.
  final List<AvailabilityBlock> _availability = [];

  /// Non-null while the block editor is open, holding the session type it
  /// is editing for.
  String? _addingForType;
  String? _photoDataUrl;
  bool _pickingPhoto = false;
  String? _error;
  bool _busy = false;

  final _coachCode = TextEditingController();
  final _bio = TextEditingController();
  List<TrainerBeforeAfter> _beforeAfters = [];

  late bool _codeVerified = widget.debugSkipCodeGate;
  String? _codeError;
  bool _verifyingCode = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _title.dispose();
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    _phone.dispose();
    _code.dispose();
    _locationName.dispose();
    _locationAddress.dispose();
    _coachCode.dispose();
    _bio.dispose();
    super.dispose();
  }

  /// The selectable pill used by both the Disciplines and Session types
  /// pickers below, so the two always look and behave the same.
  Widget _pickChip({
    required String label,
    required bool on,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? AppColors.gold : AppColors.line),
          color: on ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: on ? AppColors.gold : AppColors.mute,
          ),
        ),
      ),
    );
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
        throw Exception(
          "That code is invalid or has expired. Contact ONE Fitness for a current code.",
        );
      }
      if (usedAt != null) {
        throw Exception("That approval code has already been used.");
      }
      if (expiresAt != null && isoToday().compareTo(expiresAt) > 0) {
        throw Exception(
          "That approval code has expired — ask the owner for a new one.",
        );
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
    final firstName = _firstName.text.trim();
    final lastName = _lastName.text.trim();
    final name = [firstName, lastName].where((p) => p.isNotEmpty).join(" ");
    final email = _email.text.trim();
    final password = _password.text;
    final phone = _phone.text.trim();
    // Name, email and password are all it takes to open an account. A phone
    // number is useful for coordinating sessions but isn't essential to
    // creating one (Apple guideline 5.1.1), so it's optional here and can be
    // filled in later from My Profile.
    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty) {
      setState(
        () => _error = "First name, last name, email, and password are all required.",
      );
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
    if (!_over18) {
      setState(() => _error = "You must confirm you are 18 or older to use ONE Fitness.");
      return;
    }
    if (!_agreedToTerms) {
      setState(() => _error = "Please agree to the Terms of Use to continue.");
      return;
    }
    // Only gate on this when the gym actually offers any — otherwise it'd be
    // an impossible requirement on a brand-new, unconfigured platform.
    if (_sessionTypes.isEmpty &&
        ref.read(platformSettingsProvider).offeredSessionTypes.isNotEmpty) {
      setState(() => _error = "Choose at least one session type.");
      return;
    }
    // A coach with no availability never appears in the booking screen, so
    // the account would be created and then be invisible. Required, not a
    // "you can do this later".
    if (_availability.isEmpty) {
      setState(() => _error =
          "Add at least one availability block so clients can book you.");
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final newCoachId = await SupabaseService.signUpCoach(
        email: email,
        password: password,
        name: name,
        firstName: firstName,
        lastName: lastName,
        title: _title.text.trim(),
        phone: phone,
        approvalCode: _code.text.trim(),
        photo: _photoDataUrl,
        disciplines: _disciplines.toList(),
        sessionTypes: _sessionTypes.toList(),
        availability: _availability,
        locationName: _locationName.text.trim(),
        locationAddress: _locationAddress.text.trim(),
        bio: _bio.text.trim(),
        beforeAfters: _beforeAfters,
        coachCode: _coachCode.text.trim().isEmpty ? null : _coachCode.text.trim(),
      );
      // Evidence of acceptance, with the version agreed to — a later
      // revision of the Terms re-prompts rather than counting this one.
      await SupabaseService.recordTermsAcceptance(
        newCoachId,
        version: kTermsVersion,
        confirmedOver18: true,
      );
      await loadAndSeedCoreData(ref);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e
            .toString()
            .replaceFirst("Exception: ", "")
            .replaceFirst("AuthException: ", "");
        _busy = false;
      });
      return;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    // The block editor takes over the screen while open — same pattern the
    // staff profile editor uses, so a coach sees one consistent way of
    // setting availability whether they are signing up or editing later.
    final addingType = _addingForType;
    if (addingType != null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: AvailabilityBlockEditor(
            sessionType: addingType,
            disciplineOptions: _disciplines.toList(),
            onCancel: () => setState(() => _addingForType = null),
            onSave: (block) => setState(() {
              _availability.add(block);
              _addingForType = null;
            }),
          ),
        ),
      );
    }

    if (_readingTerms) {
      return TermsScreen(onBack: () => setState(() => _readingTerms = false));
    }
    if (!_codeVerified) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) widget.onBack();
        },
        child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel("Coach Approval Code"),
                const HintBox(
                  text:
                      "Coach profiles require approval. If you've met with ONE Fitness and been approved, enter the code you were given.",
                ),
                const SizedBox(height: 12),
                FieldLabeled(
                  label: "Approval code",
                  child: AppField(
                    controller: _code,
                    placeholder: "000000",
                    onChanged: (_) => setState(() => _codeError = null),
                  ),
                ),
                if (_codeError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _codeError!,
                    style: const TextStyle(
                      color: AppColors.errorText,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    BtnGhost(
                      onPressed: widget.onBack,
                      child: const Text("Back"),
                    ),
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
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _codeVerified = false);
      },
      child: Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BackBar(
                onBack: () => setState(() => _codeVerified = false),
                title: "Create coach profile",
              ),
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
                              ? DecorationImage(
                                  image: MemoryImage(
                                    base64Decode(
                                      _photoDataUrl!.substring(
                                        _photoDataUrl!.indexOf(",") + 1,
                                      ),
                                    ),
                                  ),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: _photoDataUrl == null
                            ? const Icon(
                                LucideIcons.user,
                                size: 28,
                                color: AppColors.mute,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _pickingPhoto ? null : _pickPhoto,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.gold,
                      ),
                      icon: const Icon(LucideIcons.image, size: 14),
                      label: Text(
                        _pickingPhoto
                            ? "Opening…"
                            : (_photoDataUrl != null
                                  ? "Change photo"
                                  : "Add photo"),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
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
                      child: AppField(
                        controller: _firstName,
                        onChanged: (_) => setState(() => _error = null),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FieldLabeled(
                      label: "Last name",
                      child: AppField(
                        controller: _lastName,
                        onChanged: (_) => setState(() => _error = null),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FieldLabeled(
                label: "Title",
                child: AppField(
                  controller: _title,
                  placeholder: "Coach",
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  "How clients see you — e.g. \"Coach Sooraj\".",
                  style: TextStyle(fontSize: 11, color: AppColors.mute),
                ),
              ),
              const SizedBox(height: 10),
              FieldLabeled(
                label: "Email",
                child: AppField(
                  controller: _email,
                  placeholder: "name@email.com",
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              const SizedBox(height: 10),
              FieldLabeled(
                label: "Phone (optional)",
                child: AppField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              const SizedBox(height: 10),
              FieldLabeled(
                label: "Disciplines (choose one or more)",
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  // The gym's own list (Customize Platform → Services),
                  // including disciplines the owner added themselves.
                  children: ref
                      .watch(platformSettingsProvider)
                      .offeredDisciplines
                      .map(
                        (k) => _pickChip(
                          label: disciplineLabel(k),
                          on: _disciplines.contains(k),
                          onTap: () => setState(() {
                            _disciplines.contains(k)
                                ? _disciplines.remove(k)
                                : _disciplines.add(k);
                            _error = null;
                          }),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 10),
              // Same source as the Disciplines list above: whatever the owner
              // set up in Customize Platform → Services, including any type
              // they added themselves. A type the owner deletes stops being
              // offered here too.
              FieldLabeled(
                label: "Session types (choose one or more)",
                child: Builder(builder: (context) {
                  final offered =
                      ref.watch(platformSettingsProvider).offeredSessionTypes;
                  if (offered.isEmpty) {
                    return const Text(
                      "ONE Fitness hasn't set up any session types yet — you "
                      "can add yours later from My Profile.",
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.mute,
                        height: 1.4,
                      ),
                    );
                  }
                  return Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: offered
                        .map(
                          (k) => _pickChip(
                            label: sessionTypeLabel(k),
                            on: _sessionTypes.contains(k),
                            onTap: () => setState(() {
                              if (_sessionTypes.contains(k)) {
                                _sessionTypes.remove(k);
                                // Availability is set per session type — drop
                                // any blocks for a type just unticked.
                                _availability
                                    .removeWhere((b) => b.sessionType == k);
                              } else {
                                _sessionTypes.add(k);
                              }
                              _error = null;
                            }),
                          ),
                        )
                        .toList(),
                  );
                }),
              ),
              const SizedBox(height: 14),
              // Always shown, never hidden: a coach with no availability is
              // invisible in the booking screen, so this is required, not
              // optional. When the prerequisites aren't picked yet the
              // section says so rather than silently disappearing — hiding
              // it made it look like the feature had been removed.
              FieldLabeled(
                label: "Availability * (required)",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        "When can clients book you? Add at least one block — "
                        "without it you won't appear in the booking screen at all.",
                        style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
                      ),
                    ),
                    if (_disciplines.isEmpty || _sessionTypes.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.08),
                          border: Border.all(color: AppColors.goldDim),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _disciplines.isEmpty && _sessionTypes.isEmpty
                              ? "Choose your disciplines and session types above, then add your available times here."
                              : _disciplines.isEmpty
                                  ? "Choose your disciplines above, then add your available times here."
                                  : "Choose your session types above, then add your available times here.",
                          style: const TextStyle(fontSize: 11.5, color: AppColors.gold, height: 1.4),
                        ),
                      ),
                    if (_disciplines.isNotEmpty && _sessionTypes.isNotEmpty) ...[
                      ..._availability.asMap().entries.map((entry) {
                        final i = entry.key;
                        final b = entry.value;
                        final dayCount = b.byDay.values.where((slots) => slots.isNotEmpty).length;
                        final slotCount = b.byDay.values.fold<int>(0, (sum, slots) => sum + slots.length);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                            decoration: BoxDecoration(
                              color: AppColors.bg,
                              border: Border.all(color: AppColors.line),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "${sessionTypeLabel(b.sessionType)} · ${disciplineLabel(b.discipline)}",
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        "$slotCount slot${slotCount == 1 ? "" : "s"} across $dayCount day${dayCount == 1 ? "" : "s"}",
                                        style: const TextStyle(fontSize: 11, color: AppColors.mute),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => setState(() => _availability.removeAt(i)),
                                  icon: const Icon(LucideIcons.trash2, size: 15, color: AppColors.errorText),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      // Wraps onto as many lines as the screen needs — as a
                      // single Row the third button ran off narrow phones.
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        // Only the types this coach ticked above — a "+" for
                        // a type they don't run would save a block the
                        // booking flow never looks at.
                        children: _sessionTypes
                            .map((k) => MapEntry(k, sessionTypeLabel(k)))
                            .map((e) {
                          return Padding(
                            padding: EdgeInsets.zero,
                            child: OutlinedButton(
                              onPressed: () => setState(() => _addingForType = e.key),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.goldDim),
                                foregroundColor: AppColors.gold,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                              ),
                              child: Text(
                                "+ ${e.value}",
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Where you train",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.txt,
                ),
              ),
              const SizedBox(height: 6),
              AppCard(
                child: _editingLocation
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FieldLabeled(
                            label: "Location name",
                            child: AppField(controller: _locationName),
                          ),
                          const SizedBox(height: 8),
                          FieldLabeled(
                            label: "Address",
                            child: AppField(controller: _locationAddress),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () =>
                                  setState(() => _editingLocation = false),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.gold,
                              ),
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
                                Text(
                                  _locationName.text.isEmpty
                                      ? "Untitled location"
                                      : _locationName.text,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                if (_locationAddress.text.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                      _locationAddress.text,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.mute,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () =>
                                setState(() => _editingLocation = true),
                            icon: const Icon(
                              LucideIcons.pencil,
                              size: 16,
                              color: AppColors.mute,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Coach Code",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.txt,
                ),
              ),
              const SizedBox(height: 6),
              AppField(controller: _coachCode, placeholder: "e.g. JESS10"),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  "A unique code you give clients at signup to link their account to you — set once here, can't be changed later.",
                  style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Bio (optional, but recommended)",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.txt,
                ),
              ),
              const SizedBox(height: 6),
              AppField(
                controller: _bio,
                placeholder:
                    "Tell clients about your background, training style, certifications, and what makes you a great coach…",
                minLines: 4,
                maxLines: 8,
                maxLength: 750,
                onChanged: (_) => setState(() {}),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "A strong bio helps clients choose you.",
                      style: TextStyle(fontSize: 11, color: AppColors.mute),
                    ),
                    Text(
                      "${_bio.text.length}/750",
                      style: TextStyle(
                        fontSize: 11,
                        color: _bio.text.length > 700
                            ? const Color(0xFFD68A4F)
                            : AppColors.mute,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Before & After (optional)",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.txt,
                ),
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  "Show off past client transformations as a portfolio — every client can see these on your coach profile. Add a Before and After photo for each frame. Up to 6 sets.",
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.mute,
                    height: 1.5,
                  ),
                ),
              ),
              BeforeAfterEditor(
                value: _beforeAfters,
                onChange: (v) => setState(() => _beforeAfters = v),
              ),
              const SizedBox(height: 10),
              FieldLabeled(
                label: "Create password",
                child: AppField(
                  controller: _password,
                  placeholder: "At least 6 characters",
                  obscureText: true,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              const SizedBox(height: 10),
              FieldLabeled(
                label: "Confirm password",
                child: AppField(
                  controller: _password2,
                  placeholder: "••••••",
                  obscureText: true,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              const SizedBox(height: 14),
              const Divider(color: AppColors.line, height: 1),
              const SizedBox(height: 6),
              ConsentCheckbox(
                value: _over18,
                onChanged: (v) => setState(() {
                  _over18 = v;
                  _error = null;
                }),
                child: const Text(
                  "I confirm I am 18 or older",
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
              ConsentCheckbox(
                value: _agreedToTerms,
                onChanged: (v) => setState(() {
                  _agreedToTerms = v;
                  _error = null;
                }),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text("I agree to the ", style: TextStyle(fontSize: 13, height: 1.4)),
                    GestureDetector(
                      onTap: () => setState(() => _readingTerms = true),
                      child: const Text(
                        "Terms of Use",
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppColors.gold,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.gold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 36, top: 2),
                child: Text(
                  "ONE Fitness has zero tolerance for objectionable content or abusive users.",
                  style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.errorText,
                    fontSize: 12,
                  ),
                ),
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
              BtnGhost(
                onPressed: widget.onBack,
                full: true,
                child: const Text("Back to sign in"),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
