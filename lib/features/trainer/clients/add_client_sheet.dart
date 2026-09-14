import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/supabase_bootstrap_provider.dart";
import "../../../data/providers/trainer_providers.dart";

/// Coach/owner adding a client in person — the desk-signup path for someone
/// who isn't going to download the app and register themselves first.
///
/// Two states: the form, then the handover screen showing the temporary
/// password. The second is the point of the whole flow — a created account
/// nobody can sign into is worse than no account, so the credentials are
/// shown once, prominently, with a copy button.
Future<bool?> showAddClientSheet(BuildContext context) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: const _AddClientForm(),
      ),
    );

class _AddClientForm extends ConsumerStatefulWidget {
  const _AddClientForm();

  @override
  ConsumerState<_AddClientForm> createState() => _AddClientFormState();
}

class _AddClientFormState extends ConsumerState<_AddClientForm> {
  // Same fields the client fills in when they sign themselves up
  // (client_signup_screen.dart), minus password — that's generated — and
  // coach code, which is replaced by the owner picking a coach directly.
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _birthday = TextEditingController();

  /// Owner only — which coach takes this client on. A coach adding a client
  /// always takes them on themselves (the server enforces that), so they
  /// never see this picker.
  String? _trainerId;
  bool _busy = false;
  String? _error;

  /// Set once the account exists — swaps the form for the handover screen.
  Map<String, dynamic>? _created;

  String get _fullName =>
      [_firstName.text.trim(), _lastName.text.trim()].where((s) => s.isNotEmpty).join(" ");

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _city.dispose();
    _birthday.dispose();
    super.dispose();
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await SupabaseService.createClientAccount(
        name: _fullName,
        firstName: _firstName.text,
        lastName: _lastName.text,
        email: _email.text.trim(),
        phone: _phone.text,
        city: _city.text,
        birthday: _birthday.text,
        primaryTrainerId: _trainerId,
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: SingleChildScrollView(
          child: created == null ? _buildForm() : _buildHandover(created),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final canSubmit = _firstName.text.trim().isNotEmpty && _email.text.trim().contains("@");
    final isOwner = ref.watch(trainerAuthProvider) == "owner";
    final trainers = ref.watch(trainersProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Add a client", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text(
          "Creates their account so they can sign in on their own device. You'll get a temporary password to give them.",
          style: TextStyle(fontSize: 12, color: AppColors.mute, height: 1.4),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FieldLabeled(
                label: "First name",
                child: AppField(controller: _firstName, onChanged: (_) => setState(() {})),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FieldLabeled(
                label: "Last name",
                child: AppField(controller: _lastName, onChanged: (_) => setState(() {})),
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
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 10),
        FieldLabeled(
          label: "Phone number",
          child: AppField(controller: _phone, keyboardType: TextInputType.phone),
        ),
        const SizedBox(height: 10),
        FieldLabeled(
          label: "City",
          child: AppField(controller: _city),
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
        if (isOwner && trainers.isNotEmpty) ...[
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Coach (optional)",
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.bg,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<String?>(
                value: _trainerId,
                isExpanded: true,
                underline: const SizedBox(),
                dropdownColor: AppColors.card,
                hint: const Text("Unassigned", style: TextStyle(color: AppColors.mute, fontSize: 14)),
                style: const TextStyle(color: AppColors.txt, fontSize: 14),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text("Unassigned")),
                  for (final t in trainers) DropdownMenuItem<String?>(value: t.id, child: Text(t.name)),
                ],
                onChanged: _busy ? null : (v) => setState(() => _trainerId = v),
              ),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text("⚠ $_error", style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: BtnGold(
                onPressed: (!canSubmit || _busy) ? null : _submit,
                child: Text(_busy ? "Creating…" : "Create account"),
              ),
            ),
            const SizedBox(width: 8),
            BtnGhost(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHandover(Map<String, dynamic> created) {
    final email = created["email"] as String? ?? "";
    final password = created["tempPassword"] as String? ?? "";
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(LucideIcons.checkCircle2, size: 18, color: AppColors.success),
            const SizedBox(width: 8),
            Text(
              "$_fullName is set up",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
            color: AppColors.bg,
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
              const Text("TEMPORARY PASSWORD", style: TextStyle(fontSize: 9.5, color: AppColors.mute, letterSpacing: 1)),
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
                  if (context.mounted) {
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
