import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_icons/lucide_icons.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/membership_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/mock/mock_data.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/membership_plan.dart";
import "../../../data/providers/client_providers.dart";
import "membership_hub_screen.dart";

/// Mirrors ProfileSettingsScreen.jsx, trimmed to the rows that don't need
/// Stripe/2FA/the full intake questionnaire: Edit Profile (name/email/
/// phone/city), Membership (reuses MembershipHubScreen), a disabled Payment
/// Details row, and a "coming soon" notification-preferences row. The
/// Two-Factor row is skipped entirely since it's gated behind a platform
/// setting that defaults to "off".
class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  String? _section;

  @override
  Widget build(BuildContext context) {
    if (_section == "profile") {
      return _EditProfileSection(onBack: () => setState(() => _section = null));
    }
    if (_section == "membership") {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: BackBar(onBack: () => setState(() => _section = null), title: "Profile Settings"),
          ),
          const Expanded(child: MembershipHubScreen()),
        ],
      );
    }

    final info = ref.watch(clientInfoProvider);
    final bookings = ref.watch(clientBookingsProvider);
    final plan = MockData.planById(info.membershipPlanId);
    final mStatus = plan != null ? membershipStatusLabel(info, plan, bookings) : null;

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
            detail: plan != null ? "${plan.name} · ${mStatus ?? '—'} sessions remaining" : "No membership",
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
            icon: LucideIcons.mapPin,
            label: "Your City",
            detail: info.city ?? "Not set",
            onTap: () => setState(() => _section = "profile"),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Container(
              padding: const EdgeInsets.only(top: 16),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
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

String membershipStatusLabel(ClientInfo info, MembershipPlan plan, List<Booking> bookings) {
  final checkedIn = bookings.where((b) => b.attendanceStatus == "checked-in").toList();
  final used = sessionsUsedThisPeriod(info, plan, checkedIn);
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
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(detail, style: const TextStyle(fontSize: 12, color: AppColors.mute)),
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
                child: const Text("None", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFD68A4F))),
              ),
            if (!disabled) const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
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
  ConsumerState<_EditProfileSection> createState() => _EditProfileSectionState();
}

class _EditProfileSectionState extends ConsumerState<_EditProfileSection> {
  late final _name = TextEditingController(text: ref.read(clientInfoProvider).name);
  late final _email = TextEditingController(text: ref.read(clientInfoProvider).email ?? "");
  late final _phone = TextEditingController(text: ref.read(clientInfoProvider).phone ?? "");
  late final _city = TextEditingController(text: ref.read(clientInfoProvider).city ?? "");

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _city.dispose();
    super.dispose();
  }

  void _save() {
    ref.read(clientInfoProvider.notifier).update((info) => info.copyWith(
          name: _name.text.trim(),
          email: _email.text.trim(),
          phone: _phone.text.trim(),
          city: _city.text.trim(),
        ));
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onBack, title: "Profile Settings"),
          const SizedBox(height: 10),
          const SectionLabel("Edit Profile"),
          FieldLabeled(label: "Name", child: AppField(controller: _name)),
          const SizedBox(height: 10),
          FieldLabeled(label: "Email", child: AppField(controller: _email, keyboardType: TextInputType.emailAddress)),
          const SizedBox(height: 10),
          FieldLabeled(label: "Phone", child: AppField(controller: _phone, keyboardType: TextInputType.phone)),
          const SizedBox(height: 10),
          FieldLabeled(label: "City", child: AppField(controller: _city)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: BtnGold(onPressed: _save, child: const Text("Save"))),
              const SizedBox(width: 8),
              BtnGhost(onPressed: widget.onBack, child: const Text("Cancel")),
            ],
          ),
        ],
      ),
    );
  }
}
