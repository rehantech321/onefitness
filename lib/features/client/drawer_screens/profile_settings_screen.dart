import "dart:convert";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/membership_utils.dart";
import "../../../core/utils/photo_picker_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/providers/client_providers.dart";
import "client_visits_section.dart";
import "membership_hub_screen.dart";

/// Mirrors ProfileSettingsScreen.jsx, trimmed to the rows that don't need
/// Stripe/2FA/the full intake questionnaire: Edit Profile (name/email/
/// phone/city), Membership (reuses MembershipHubScreen), a disabled Payment
/// Details row, and a "coming soon" notification-preferences row. The
/// Two-Factor row is skipped entirely since it's gated behind a platform
/// setting that defaults to "off".
class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key, required this.onReschedule});

  /// Reuses client_shell.dart's own `startReschedule` — moves the app to the
  /// Booking tab with the given booking pre-loaded for rescheduling, same as
  /// every other Reschedule entry point in the app.
  final ValueChanged<Booking> onReschedule;

  @override
  ConsumerState<ProfileSettingsScreen> createState() =>
      _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  String? _section;

  @override
  Widget build(BuildContext context) {
    if (_section == "profile") {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _section = null),
        child: _EditProfileSection(
          onBack: () => setState(() => _section = null),
        ),
      );
    }
    if (_section == "visits") {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _section = null),
        child: ClientVisitsSection(
          onBack: () => setState(() => _section = null),
          onReschedule: widget.onReschedule,
        ),
      );
    }
    if (_section == "membership") {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _section = null),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: BackBar(
                onBack: () => setState(() => _section = null),
                title: "Profile Settings",
              ),
            ),
            const Expanded(child: MembershipHubScreen()),
          ],
        ),
      );
    }

    final info = ref.watch(clientInfoProvider);
    final bookings = ref.watch(clientBookingsProvider);
    final plan = ref
        .watch(membershipPlansProvider.notifier)
        .byId(info.membershipPlanId);
    final mStatus = plan != null
        ? membershipStatusLabel(info, plan, bookings)
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel("Profile Settings"),
          _SettingRow(
            icon: LucideIcons.user,
            label: "Edit Profile",
            detail: "${info.name} · ${info.email ?? ''}",
            onTap: () => setState(() => _section = "profile"),
          ),
          _SettingRow(
            icon: LucideIcons.creditCard,
            label: "Membership",
            detail: plan != null
                ? "${plan.name} · ${mStatus ?? '—'} sessions remaining"
                : "No membership",
            badge: plan == null ? "None" : null,
            onTap: () => setState(() => _section = "membership"),
          ),
          const _SettingRow(
            icon: LucideIcons.creditCard,
            label: "Payment Details",
            detail: "Managed by your coach",
            disabled: true,
          ),
          _SettingRow(
            icon: LucideIcons.calendarClock,
            label: "Visits",
            detail: "Past & upcoming sessions",
            onTap: () => setState(() => _section = "visits"),
          ),
          _SettingRow(
            icon: LucideIcons.mapPin,
            label: "Your City",
            detail: info.city ?? "Not set",
            onTap: () => setState(() => _section = "profile"),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Container(
              padding: const EdgeInsets.only(top: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: const _SettingRow(
                icon: LucideIcons.bell,
                label: "Notification Preferences",
                detail: "Coming soon",
                disabled: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String membershipStatusLabel(
  ClientInfo info,
  MembershipPlan plan,
  List<Booking> bookings,
) {
  final used = sessionsUsedThisPeriod(info, plan, bookings);
  final max = effectiveMaxSessions(info, plan);
  return "${(max - used).clamp(0, max)}";
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.detail,
    this.badge,
    this.disabled = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final String? badge;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.6 : 1,
      child: AppCard(
        onTap: disabled ? null : onTap,
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.gold),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.mute,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFD68A4F).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  "None",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFD68A4F),
                  ),
                ),
              ),
            if (!disabled)
              const Icon(
                LucideIcons.chevronRight,
                size: 15,
                color: AppColors.mute,
              ),
          ],
        ),
      ),
    );
  }
}

class _EditProfileSection extends ConsumerStatefulWidget {
  const _EditProfileSection({required this.onBack});
  final VoidCallback onBack;

  @override
  ConsumerState<_EditProfileSection> createState() =>
      _EditProfileSectionState();
}

class _EditProfileSectionState extends ConsumerState<_EditProfileSection> {
  late final _name = TextEditingController(
    text: ref.read(clientInfoProvider).name,
  );
  late final _email = TextEditingController(
    text: ref.read(clientInfoProvider).email ?? "",
  );
  late final _phone = TextEditingController(
    text: ref.read(clientInfoProvider).phone ?? "",
  );
  late final _city = TextEditingController(
    text: ref.read(clientInfoProvider).city ?? "",
  );
  late final _birthday = TextEditingController(
    text: ref.read(clientInfoProvider).birthday ?? "",
  );
  String? _photoDataUrl;
  bool _pickingPhoto = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _city.dispose();
    _birthday.dispose();
    super.dispose();
  }

  bool _saving = false;
  String? _error;
  bool _resetBusy = false;
  bool _resetSent = false;

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
    final initial =
        DateTime.tryParse(_birthday.text) ??
        DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 100),
      lastDate: now,
    );
    if (picked != null)
      setState(
        () => _birthday.text =
            "${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}",
      );
  }

  Future<void> _sendPasswordReset() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(
        () => _error = "An email is required before sending a reset link.",
      );
      return;
    }
    setState(() {
      _resetBusy = true;
      _error = null;
    });
    try {
      await SupabaseService.sendPasswordReset(email);
      if (mounted) setState(() => _resetSent = true);
    } catch (e) {
      if (mounted)
        setState(
          () => _error =
              "Couldn't send the reset email — check your connection and try again.",
        );
    } finally {
      if (mounted) setState(() => _resetBusy = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    final city = _city.text.trim();
    final birthday = _birthday.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await SupabaseService.updateClientRow(
        ref.read(clientInfoProvider).id,
        name: name,
        email: email,
        phone: phone,
        city: city,
        birthday: birthday.isEmpty ? null : birthday,
        photo: _photoDataUrl,
      );
      ref
          .read(clientInfoProvider.notifier)
          .update(
            (info) => info.copyWith(
              name: name,
              email: email,
              phone: phone,
              city: city,
              birthday: birthday.isEmpty ? null : birthday,
              photo: _photoDataUrl,
            ),
          );
      widget.onBack();
    } catch (e) {
      setState(() {
        _saving = false;
        _error =
            "Couldn't save your profile — check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(clientInfoProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onBack, title: "Profile Settings"),
          const SizedBox(height: 10),
          const SectionLabel("Edit Profile"),
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
                    child: _photoDataUrl == null
                        ? Avatar(src: info.photo, name: info.name, size: 80)
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _pickingPhoto ? null : _pickPhoto,
                  style: TextButton.styleFrom(foregroundColor: AppColors.gold),
                  icon: const Icon(LucideIcons.image, size: 14),
                  label: Text(
                    _pickingPhoto
                        ? "Opening…"
                        : ((_photoDataUrl ?? info.photo) != null
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
          const SizedBox(height: 6),
          FieldLabeled(
            label: "Name",
            child: AppField(controller: _name),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Email",
            child: AppField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
            ),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Phone",
            child: AppField(
              controller: _phone,
              keyboardType: TextInputType.phone,
            ),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "City",
            child: AppField(controller: _city),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              "Personalized training near you",
              style: TextStyle(
                fontSize: 11,
                color: AppColors.mute,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Birthday",
            child: InkWell(
              onTap: _pickBirthday,
              child: InputDecorator(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.bg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                ),
                child: Text(
                  _birthday.text.isEmpty ? "Select date" : _birthday.text,
                  style: TextStyle(
                    fontSize: 14,
                    color: _birthday.text.isEmpty
                        ? AppColors.mute
                        : AppColors.txt,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            height: 1,
            color: AppColors.line,
            margin: const EdgeInsets.symmetric(vertical: 2),
          ),
          const SizedBox(height: 14),
          Text(
            "Password changes go through email now — send a reset link to ${_email.text.trim().isEmpty ? "this account's email" : _email.text.trim()}.",
            style: const TextStyle(fontSize: 12, color: AppColors.mute),
          ),
          const SizedBox(height: 8),
          if (_resetSent)
            const Text(
              "✓ Reset email sent.",
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            BtnGhost(
              onPressed: _resetBusy ? null : _sendPasswordReset,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.lock, size: 14),
                  const SizedBox(width: 6),
                  Text(_resetBusy ? "Sending…" : "Send password reset email"),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12),
              ),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: BtnGold(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? "Saving…" : "Save"),
                ),
              ),
              const SizedBox(width: 8),
              BtnGhost(onPressed: widget.onBack, child: const Text("Cancel")),
            ],
          ),
        ],
      ),
    );
  }
}
