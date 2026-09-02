import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/waiver_doc.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";

/// Dropdown option key/label pairs — mirrors SubTabs.jsx's mobile `<select>`
/// (this app is mobile-only, so that's the correct web analog to port, not
/// the desktop horizontal tab row). Labels here are the short dropdown
/// text; each tab's own in-page [_sectionTitle] can be longer.
const _tabs = [
  ("scheduling", "Scheduling"),
  ("access", "Coaches & Security"),
  ("clients", "Clients"),
  ("payments", "Payments"),
  ("workouts", "Workouts & General"),
];

String _sectionTitle(String tab) => switch (tab) {
  "scheduling" => "Scheduling",
  "access" => "Coaches, Access & Security",
  "clients" => "Clients",
  "payments" => "Payments",
  "workouts" => "Workouts & General",
  _ => "",
};

String _sectionHint(String tab) => switch (tab) {
  "scheduling" =>
    "These policies apply gym-wide the moment you save — a client already mid-booking sees the change without reloading.",
  "access" =>
    "These policies apply gym-wide the moment you save. Two-factor changes take effect on each person's next sign-in — nobody already signed in gets kicked out.",
  "clients" => "These policies apply gym-wide the moment you save.",
  "payments" =>
    "Applies to real Stripe Checkout payments (paid membership plans). Free plans are never affected. Card and bank transfer have their own fee below since they can charge different amounts — whenever both are offered, the client picks how to pay before checkout so the right one applies.",
  "workouts" => "These apply gym-wide the moment you save.",
  _ => "",
};

const _timeZones = [
  ("America/Los_Angeles", "Pacific Time (US)"),
  ("America/Denver", "Mountain Time (US)"),
  ("America/Chicago", "Central Time (US)"),
  ("America/New_York", "Eastern Time (US)"),
  ("America/Anchorage", "Alaska Time (US)"),
  ("Pacific/Honolulu", "Hawaii Time (US)"),
  ("UTC", "UTC"),
];

const _requiredFieldOptions = [("phone", "Phone"), ("birthday", "Birthday"), ("city", "City")];
const _customFieldTypes = [("text", "Text"), ("number", "Number"), ("date", "Date")];

/// Mirrors CustomizePlatform.jsx (owner-only) — 5 tabs of gym-wide config,
/// covering every field the real `platform_settings` row models. Dropdown
/// tab selector (mirrors web's own mobile layout), section label + hint per
/// tab, and per-field explanatory hint text all match web's exact copy.
/// Explicit dirty-tracking + Save button — matches web's draft/save flow so
/// a partial edit can be discarded.
class CustomizePlatformScreen extends ConsumerStatefulWidget {
  const CustomizePlatformScreen({super.key});

  @override
  ConsumerState<CustomizePlatformScreen> createState() => _CustomizePlatformScreenState();
}

class _CustomizePlatformScreenState extends ConsumerState<CustomizePlatformScreen> {
  String _tab = "scheduling";
  late PlatformSettings _draft = ref.read(platformSettingsProvider);
  bool _dirty = false;
  bool _saving = false;
  bool _savedFlash = false;
  String? _saveError;

  void _set(PlatformSettings Function(PlatformSettings) f) {
    setState(() {
      _draft = f(_draft);
      _dirty = true;
      _saveError = null;
    });
  }

  Future<void> _switchTab(String next) async {
    if (next == _tab) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text("Discard changes?"),
          content: const Text("You have unsaved changes. Discard them and switch tabs?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Keep editing")),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Discard")),
          ],
        ),
      );
      if (discard != true) return;
    }
    setState(() {
      _draft = ref.read(platformSettingsProvider);
      _dirty = false;
      _saveError = null;
      _tab = next;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final prev = ref.read(platformSettingsProvider);
    try {
      await SupabaseService.savePlatformSettings(prev, _draft);
      ref.read(platformSettingsProvider.notifier).update((_) => _draft);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _savedFlash = true;
      });
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _savedFlash = false);
      });
    } catch (e) {
      if (mounted) setState(() => _saveError = "Couldn't save — please try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PlatformSettings>(platformSettingsProvider, (prev, next) {
      if (!_dirty) setState(() => _draft = next);
    });
    final s = _draft;
    final anyFeeEnabled = s.cardFee.enabled || (s.achOffered && s.achFee.enabled);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          child: AppCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: DropdownButton<String>(
              value: _tab,
              isExpanded: true,
              underline: const SizedBox(),
              dropdownColor: AppColors.card,
              style: const TextStyle(color: AppColors.txt, fontSize: 14, fontWeight: FontWeight.w700),
              items: _tabs.map((t) => DropdownMenuItem(value: t.$1, child: Text(t.$2))).toList(),
              onChanged: (v) {
                if (v != null) _switchTab(v);
              },
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel(_sectionTitle(_tab)),
                const SizedBox(height: 8),
                HintBox(text: _sectionHint(_tab)),
                const SizedBox(height: 16),
                if (_tab == "scheduling") ...[
                  _NumberRow(
                    label: "Late cancellation window (hours)",
                    hint: "Cancelling or rescheduling outside this many hours before a session is free. Inside it, the late cancellation fee below applies.",
                    suffix: "hours before session",
                    value: s.lateCancellationHours,
                    onChange: (v) => _set((d) => d.copyWith(lateCancellationHours: v)),
                  ),
                  _MoneyRow(label: "Late cancellation fee", cents: s.lateCancellationFeeCents, onChange: (v) => _set((d) => d.copyWith(lateCancellationFeeCents: v))),
                  _MoneyRow(
                    label: "No-show fee",
                    hint: "Charged when a coach marks a booking No-Show — unlike a late cancellation, a no-show does not give the session back.",
                    cents: s.noShowFeeCents,
                    onChange: (v) => _set((d) => d.copyWith(noShowFeeCents: v)),
                  ),
                  _ChoiceRow(
                    label: "Block rescheduling inside that window?",
                    hint: "\"Block it entirely\" hides the Reschedule option once a client is inside the window — they'd need to cancel (and pay the fee) instead.",
                    value: s.blockRescheduleInWindow ? "block" : "chargeInstead",
                    options: const [("block", "Block it entirely"), ("chargeInstead", "Allow it, but charge the late fee")],
                    onChange: (v) => _set((d) => d.copyWith(blockRescheduleInWindow: v == "block")),
                  ),
                  _NumberRow(
                    label: "How far ahead clients can book",
                    suffix: "days",
                    value: s.maxBookingHorizonDays,
                    onChange: (v) => _set((d) => d.copyWith(maxBookingHorizonDays: v)),
                  ),
                  _NumberRow(
                    label: "Minimum lead time to book",
                    suffix: "hours before the slot",
                    value: s.minBookingLeadHours,
                    onChange: (v) => _set((d) => d.copyWith(minBookingLeadHours: v)),
                  ),
                  _ChoiceRow(
                    label: "Clients book with",
                    hint: "\"Assigned coach only\" restricts the booking screen to a client's assigned coach. If a client has no assigned coach yet, they still see every coach so they're never stuck with nothing bookable.",
                    value: s.bookingCoachScope,
                    options: const [("assigned", "Assigned coach only"), ("any", "Any coach")],
                    onChange: (v) => _set((d) => d.copyWith(bookingCoachScope: v)),
                  ),
                  _NumberRow(
                    label: "Default one-on-one session cap",
                    hint: "Fixed by definition — a one-on-one session is always exactly one client, not configurable here.",
                    suffix: "client per slot",
                    value: 1,
                    disabled: true,
                    onChange: (_) {},
                  ),
                  _NumberRow(
                    label: "Default semi-private session cap",
                    suffix: "clients per slot",
                    value: s.semiPrivateCap,
                    onChange: (v) => _set((d) => d.copyWith(semiPrivateCap: v)),
                  ),
                ],
                if (_tab == "access") ...[
                  _ChoiceRow(
                    label: "Require two-factor authentication",
                    hint: "\"Staff only\" covers Owner and Coach accounts. \"Everyone\" adds clients. Authenticator apps only for now — test with a disposable coach account before requiring it gym-wide.",
                    value: s.twoFactorRequirement,
                    options: const [("off", "Off"), ("staff", "Staff only"), ("everyone", "Everyone")],
                    onChange: (v) => _set((d) => d.copyWith(twoFactorRequirement: v)),
                  ),
                  _ChoiceRow(
                    label: "Coach client list",
                    hint: "Scopes a coach's Clients tab and Chat inbox. Owner always sees everyone.",
                    value: s.coachClientScope,
                    options: const [("own", "Own clients only"), ("all", "All clients")],
                    onChange: (v) => _set((d) => d.copyWith(coachClientScope: v)),
                  ),
                  _ToggleRow(
                    label: "Coach can view revenue / pay data",
                    hint: "Unlocks a coach's own My Pay screen — their sessions and commission only, never gym-wide financials.",
                    value: s.coachCanViewRevenue,
                    onChange: (v) => _set((d) => d.copyWith(coachCanViewRevenue: v)),
                  ),
                  _ToggleRow(
                    label: "Coach can see other coaches' scheduled sessions",
                    hint: "Off keeps a coach's Scheduling tab locked to their own sessions, like today.",
                    value: s.coachCanSeeOtherSchedules,
                    onChange: (v) => _set((d) => d.copyWith(coachCanSeeOtherSchedules: v)),
                  ),
                  _ChoiceRow(
                    label: "Coaches reply in messages as",
                    hint: "\"Themselves\" shows the actual coach's name in a client's message log. \"ONE Fitness\" hides individual coach names — the owner always appears as ONE Fitness either way.",
                    value: s.messageIdentity,
                    options: const [("self", "Themselves"), ("business", "ONE Fitness")],
                    onChange: (v) => _set((d) => d.copyWith(messageIdentity: v)),
                  ),
                  _ToggleRow(
                    label: "Coach can edit workouts assigned to their clients",
                    hint: "Off gives coaches read-only Plans — only the owner can build or edit workout/nutrition programs.",
                    value: s.coachCanEditClientWorkouts,
                    onChange: (v) => _set((d) => d.copyWith(coachCanEditClientWorkouts: v)),
                  ),
                ],
                if (_tab == "clients") ...[
                  _MultiChoiceRow(label: "Required profile fields", value: s.requiredProfileFields, options: _requiredFieldOptions, onChange: (v) => _set((d) => d.copyWith(requiredProfileFields: v))),
                  const SizedBox(height: 4),
                  _CustomFieldsEditor(fields: s.customProfileFields, onChange: (v) => _set((d) => d.copyWith(customProfileFields: v))),
                  const SizedBox(height: 10),
                  _ToggleRow(
                    label: "Require waiver at signup",
                    hint: "Off skips the sign-a-waiver step entirely for new client signups.",
                    value: s.requireWaiverAtSignup,
                    onChange: (v) => _set((d) => d.copyWith(requireWaiverAtSignup: v)),
                  ),
                  const SizedBox(height: 10),
                  const _SignupWaiverEditor(),
                  const SizedBox(height: 10),
                  _ToggleRow(
                    label: "Allow clients to message any coach",
                    hint: "Off scopes a client's coach picker to coaches they've actually booked with or been assigned to.",
                    value: s.clientsCanMessageAnyCoach,
                    onChange: (v) => _set((d) => d.copyWith(clientsCanMessageAnyCoach: v)),
                  ),
                ],
                if (_tab == "payments") ...[
                  _FeeProfileEditor(
                    title: "Card processing fee",
                    hint: "Covers both credit and debit — Stripe Checkout can't tell them apart before the client pays, so they always move together.",
                    profile: s.cardFee,
                    onChange: (v) => _set((d) => d.copyWith(cardFee: v)),
                  ),
                  const SizedBox(height: 10),
                  _ToggleRow(
                    label: "Offer bank transfer (ACH) as a payment option",
                    hint: "Off = ACH isn't offered at all, same as today. On = clients can also pay by bank transfer, with its own fee below — Stripe's cost to you is much lower for ACH, so it's common to waive the fee there to encourage it.",
                    value: s.achOffered,
                    onChange: (v) => _set((d) => d.copyWith(achOffered: v)),
                  ),
                  if (s.achOffered) ...[
                    const SizedBox(height: 10),
                    _FeeProfileEditor(
                      title: "Bank transfer (ACH) fee",
                      hint: "Leave this off, or set percent/flat to 0, to offer ACH with no fee.",
                      profile: s.achFee,
                      onChange: (v) => _set((d) => d.copyWith(achFee: v)),
                    ),
                  ],
                  if (anyFeeEnabled) ...[
                    const SizedBox(height: 10),
                    const Text(
                      "Each fee is calculated on its own pre-fee price only — never compounds on itself.",
                      style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    FieldLabeled(
                      label: "Checkout disclosure text",
                      child: _StableTextField(
                        value: s.checkoutDisclosureText,
                        placeholder: "A processing fee applies to this payment.",
                        onChanged: (v) => _set((d) => d.copyWith(checkoutDisclosureText: v)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Shown next to the pay button on Stripe's checkout page, in addition to the fee's own line item — both are always visible before the client confirms. Not optional; there's no setting to hide either one.",
                      style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    _ToggleRow(
                      label: "Refund fee when refunding a payment",
                      hint: "Off (default): refunding a purchase returns only the original price — the processing fee is kept, like most real payment processors. On: refunds return the fee too.",
                      value: s.refundFeeOnRefund,
                      onChange: (v) => _set((d) => d.copyWith(refundFeeOnRefund: v)),
                    ),
                  ],
                ],
                if (_tab == "workouts") ...[
                  _ToggleRow(
                    label: "Auto carry-over of last logged weight",
                    hint: "On (default): a client's next session starts pre-filled with the weight they logged last time for each set — they can still edit or clear it. Off: sets start blank.",
                    value: s.autoCarryOverLastWeight,
                    onChange: (v) => _set((d) => d.copyWith(autoCarryOverLastWeight: v)),
                  ),
                  _ChoiceRow(
                    label: "Default weight units",
                    hint: "Changes the unit label shown throughout workout logging. Doesn't convert numbers already entered — switching from lb to kg relabels the same figures, it doesn't recalculate them.",
                    value: s.defaultWeightUnit,
                    options: const [("lb", "lb"), ("kg", "kg")],
                    onChange: (v) => _set((d) => d.copyWith(defaultWeightUnit: v)),
                  ),
                  _ToggleRow(
                    label: "Allow clients to swap or edit exercises",
                    hint: "On: a client can rename an exercise or change its prescribed sets/reps for their own copy of the program while logging a session. Off (default): clients can only log performance — the coach controls the program.",
                    value: s.clientsCanSwapExercises,
                    onChange: (v) => _set((d) => d.copyWith(clientsCanSwapExercises: v)),
                  ),
                  const SizedBox(height: 4),
                  FieldLabeled(
                    label: "Business time zone",
                    child: AppCard(
                      child: DropdownButton<String>(
                        value: s.businessTimeZone,
                        isExpanded: true,
                        underline: const SizedBox(),
                        dropdownColor: AppColors.card,
                        style: const TextStyle(color: AppColors.txt, fontSize: 13),
                        items: _timeZones.map((tz) => DropdownMenuItem(value: tz.$1, child: Text(tz.$2))).toList(),
                        onChanged: (v) {
                          if (v != null) _set((d) => d.copyWith(businessTimeZone: v));
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Used to format message/charge timestamps consistently for every viewer, regardless of their own device's time zone. Booking dates themselves still follow each viewer's local device clock.",
                    style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  FieldLabeled(
                    label: "Business / location name",
                    child: _StableTextField(value: s.businessName, placeholder: "ONE Fitness", onChanged: (v) => _set((d) => d.copyWith(businessName: v))),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Updates the main header, login screens, and email sender name. Some deeper copy (legal/waiver boilerplate, etc.) may still say \"ONE Fitness\" — flag any you spot and they're quick to update.",
                    style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  const SectionLabel("Merit Badges"),
                  const SizedBox(height: 8),
                  _NumberRow(
                    label: "Progress Tracker — consecutive weeks required",
                    hint: "A client needs a photo, measurement, or workout log at least once a week for this many weeks in a row to earn the badge.",
                    suffix: "weeks",
                    value: s.meritBadgeProgressWeeks,
                    onChange: (v) => _set((d) => d.copyWith(meritBadgeProgressWeeks: v)),
                  ),
                  _NumberRow(
                    label: "Habit — consistency percent required",
                    hint: "The minimum weekly habit-completion percentage a client must sustain to earn the badge.",
                    suffix: "%",
                    value: s.meritBadgeHabitPercent,
                    onChange: (v) => _set((d) => d.copyWith(meritBadgeHabitPercent: v)),
                  ),
                  _NumberRow(
                    label: "Habit — consecutive weeks required",
                    hint: "How many weeks in a row that percentage must be sustained.",
                    suffix: "weeks",
                    value: s.meritBadgeHabitWeeks,
                    onChange: (v) => _set((d) => d.copyWith(meritBadgeHabitWeeks: v)),
                  ),
                  const SizedBox(height: 10),
                  const SectionLabel("Coach Merit Badges"),
                  const HintBox(text: "Monthly coaching-performance badges — each pays the coach automatically when earned. Changing a value only affects badges earned after the change; already-earned badges keep the amount they were awarded at."),
                  _MoneyRow(label: "Full House", badgeKey: "full_house", cents: s.badgeFullHouseCents, onChange: (v) => _set((d) => d.copyWith(badgeFullHouseCents: v))),
                  _MoneyRow(label: "PR Factory", badgeKey: "pr_factory", cents: s.badgePrFactoryCents, onChange: (v) => _set((d) => d.copyWith(badgePrFactoryCents: v))),
                  _MoneyRow(label: "Check-In", badgeKey: "check_in", cents: s.badgeCheckInCents, onChange: (v) => _set((d) => d.copyWith(badgeCheckInCents: v))),
                  _MoneyRow(label: "Comeback", badgeKey: "comeback", cents: s.badgeComebackCents, onChange: (v) => _set((d) => d.copyWith(badgeComebackCents: v))),
                  _MoneyRow(label: "Habit Coach", badgeKey: "habit_coach", cents: s.badgeHabitCoachCents, onChange: (v) => _set((d) => d.copyWith(badgeHabitCoachCents: v))),
                  _MoneyRow(label: "Challenge Coach", badgeKey: "challenge_coach", cents: s.badgeChallengeCoachCents, onChange: (v) => _set((d) => d.copyWith(badgeChallengeCoachCents: v))),
                  _MoneyRow(label: "Coach of the Month", badgeKey: "coach_of_month", cents: s.badgeCoachOfMonthCents, onChange: (v) => _set((d) => d.copyWith(badgeCoachOfMonthCents: v))),
                ],
                if (_saveError != null) ...[
                  const SizedBox(height: 14),
                  Text("⚠ $_saveError", style: const TextStyle(color: AppColors.errorText, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
                if (_savedFlash) ...[
                  const SizedBox(height: 14),
                  const Text("✓ Saved — live for every client and coach now.", style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 18),
                BtnGold(
                  onPressed: _saving ? null : _save,
                  full: true,
                  child: Text(_saving ? "Saving…" : (_dirty ? "Save Changes" : "Save")),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A text/number entry field that keeps a stable [TextEditingController]
/// across rebuilds — every row here used to build a fresh controller on
/// every keystroke's rebuild, which reset the cursor to the end of the
/// field each time. Only resyncs from [value] when it's genuinely different
/// from what's already displayed (an external reset — tab-switch discard,
/// a realtime update landing while this field isn't dirty — never a normal
/// typed edit, since [onChanged] immediately feeds the same value back in).
class _StableTextField extends StatefulWidget {
  const _StableTextField({required this.value, required this.onChanged, this.keyboardType, this.placeholder});
  final String value;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final String? placeholder;

  @override
  State<_StableTextField> createState() => _StableTextFieldState();
}

class _StableTextFieldState extends State<_StableTextField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _StableTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppField(controller: _controller, keyboardType: widget.keyboardType, placeholder: widget.placeholder, onChanged: widget.onChanged);
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.label, required this.value, required this.onChange, this.hint});
  final String label;
  final bool value;
  final ValueChanged<bool> onChange;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onChange(!value),
            child: Row(
              children: [
                Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                Icon(value ? LucideIcons.toggleRight : LucideIcons.toggleLeft, size: 30, color: value ? AppColors.gold : AppColors.mute),
              ],
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!, style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({required this.label, required this.value, required this.onChange, this.hint, this.suffix, this.disabled = false});
  final String label;
  final int value;
  final ValueChanged<int> onChange;
  final String? hint;
  final String? suffix;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              SizedBox(
                width: 60,
                child: Opacity(
                  opacity: disabled ? 0.6 : 1,
                  child: IgnorePointer(
                    ignoring: disabled,
                    child: _StableTextField(value: "$value", keyboardType: TextInputType.number, onChanged: (v) => onChange(int.tryParse(v) ?? value)),
                  ),
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 6),
                Flexible(child: Text(suffix!, style: const TextStyle(fontSize: 11, color: AppColors.mute))),
              ],
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!, style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

/// Cents-backed dollar field (e.g. "$5.00") — mirrors NumberField's
/// `prefix="$"` + `/100`/`*100` conversion in CustomizePlatform.jsx.
class _MoneyRow extends StatelessWidget {
  const _MoneyRow({required this.label, required this.cents, required this.onChange, this.hint, this.badgeKey});
  final String label;
  final int cents;
  final ValueChanged<int> onChange;
  final String? hint;

  /// When set, shows that Coach Merit Badge's artwork before the label —
  /// see [kCoachBadgeImagePaths]. Null for every non-badge money field
  /// (late-cancellation fee, no-show fee, flat fee amounts, etc.).
  final String? badgeKey;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (badgeKey != null) ...[
                CoachBadgeShield(badgeKey: badgeKey!, size: 26),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              const Text("\$", style: TextStyle(color: AppColors.mute, fontSize: 13)),
              const SizedBox(width: 4),
              SizedBox(
                width: 70,
                child: _StableTextField(
                  value: (cents / 100).toStringAsFixed(2),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) => onChange(((double.tryParse(v) ?? cents / 100) * 100).round()),
                ),
              ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!, style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

/// Percent field with decimals (e.g. "2.9%") — used by fee profile structs.
class _PercentRow extends StatelessWidget {
  const _PercentRow({required this.label, required this.value, required this.onChange});
  final String label;
  final num value;
  final ValueChanged<num> onChange;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          SizedBox(
            width: 70,
            child: _StableTextField(
              value: "$value",
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) => onChange(double.tryParse(v) ?? value),
            ),
          ),
          const SizedBox(width: 4),
          const Text("%", style: TextStyle(color: AppColors.mute, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.label, required this.value, required this.options, required this.onChange, this.hint});
  final String label;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChange;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: options.map((o) {
              final selected = value == o.$1;
              return InkWell(
                onTap: () => onChange(o.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg, border: Border.all(color: selected ? AppColors.gold : AppColors.line), borderRadius: BorderRadius.circular(7)),
                  child: Text(o.$2, style: TextStyle(fontSize: 11, color: selected ? AppColors.gold : AppColors.txt)),
                ),
              );
            }).toList(),
          ),
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(hint!, style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

/// Multi-select variant of [_ChoiceRow] — mirrors Choice's `multi` prop,
/// used for "Required profile fields" (any subset of phone/birthday/city).
class _MultiChoiceRow extends StatelessWidget {
  const _MultiChoiceRow({required this.label, required this.value, required this.options, required this.onChange});
  final String label;
  final List<String> value;
  final List<(String, String)> options;
  final ValueChanged<List<String>> onChange;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: const [
              _LockedPill(label: "Full Name"),
              _LockedPill(label: "Email"),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: options.map((o) {
              final selected = value.contains(o.$1);
              return InkWell(
                onTap: () => onChange(selected ? value.where((k) => k != o.$1).toList() : [...value, o.$1]),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg, border: Border.all(color: selected ? AppColors.gold : AppColors.line), borderRadius: BorderRadius.circular(7)),
                  child: Text(o.$2, style: TextStyle(fontSize: 11, color: selected ? AppColors.gold : AppColors.txt)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          const Text(
            "Full name and email can't be turned off — every client needs both for their account, enforced at signup. Phone / Birthday / City above are optional-or-required, your call.",
            style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _LockedPill extends StatelessWidget {
  const _LockedPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.goldDim), color: AppColors.gold.withValues(alpha: 0.15)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.lock, size: 11, color: AppColors.gold),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.gold)),
        ],
      ),
    );
  }
}

/// Owner-defined extra client-intake fields — add/relabel/retype/reorder/
/// remove, mirrors ClientsTab's custom-field list in CustomizePlatform.jsx.
class _CustomFieldsEditor extends StatefulWidget {
  const _CustomFieldsEditor({required this.fields, required this.onChange});
  final List<CustomProfileField> fields;
  final ValueChanged<List<CustomProfileField>> onChange;

  @override
  State<_CustomFieldsEditor> createState() => _CustomFieldsEditorState();
}

class _CustomFieldsEditorState extends State<_CustomFieldsEditor> {
  final _newLabel = TextEditingController();
  String _newType = "text";

  @override
  void dispose() {
    _newLabel.dispose();
    super.dispose();
  }

  void _add() {
    final label = _newLabel.text.trim();
    if (label.isEmpty) return;
    widget.onChange([...widget.fields, CustomProfileField(id: "field-${DateTime.now().microsecondsSinceEpoch}", label: label, type: _newType)]);
    setState(() {
      _newLabel.clear();
      _newType = "text";
    });
  }

  void _move(int i, int dir) {
    final j = i + dir;
    if (j < 0 || j >= widget.fields.length) return;
    final next = [...widget.fields];
    final tmp = next[i];
    next[i] = next[j];
    next[j] = tmp;
    widget.onChange(next);
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Custom profile fields", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (widget.fields.isEmpty) const Text("None yet — added fields show up on every client intake and edit-profile form.", style: TextStyle(fontSize: 12, color: AppColors.mute, fontStyle: FontStyle.italic)),
          ...widget.fields.asMap().entries.map((entry) {
            final i = entry.key;
            final f = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(onTap: i == 0 ? null : () => _move(i, -1), child: Icon(LucideIcons.chevronUp, size: 14, color: i == 0 ? AppColors.line : AppColors.mute)),
                      InkWell(onTap: i == widget.fields.length - 1 ? null : () => _move(i, 1), child: Icon(LucideIcons.chevronDown, size: 14, color: i == widget.fields.length - 1 ? AppColors.line : AppColors.mute)),
                    ],
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _StableTextField(
                      value: f.label,
                      onChanged: (v) => widget.onChange(widget.fields.map((x) => x.id == f.id ? CustomProfileField(id: x.id, label: v, type: x.type) : x).toList()),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(f.type.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.gold)),
                  IconButton(
                    icon: const Icon(LucideIcons.trash2, size: 14, color: AppColors.errorText),
                    onPressed: () => widget.onChange(widget.fields.where((x) => x.id != f.id).toList()),
                  ),
                ],
              ),
            );
          }),
          Row(
            children: [
              Expanded(child: AppField(controller: _newLabel, placeholder: "New field label…")),
              const SizedBox(width: 6),
              DropdownButton<String>(
                value: _newType,
                dropdownColor: AppColors.card,
                style: const TextStyle(color: AppColors.txt, fontSize: 12),
                items: _customFieldTypes.map((t) => DropdownMenuItem(value: t.$1, child: Text(t.$2))).toList(),
                onChanged: (v) => setState(() => _newType = v ?? "text"),
              ),
              IconButton(icon: const Icon(LucideIcons.plus, size: 16, color: AppColors.gold), onPressed: _add),
            ],
          ),
        ],
      ),
    );
  }
}

/// One fee profile's fields (card's or ACH's) — mirrors FeeProfileFields in
/// CustomizePlatform.jsx.
class _FeeProfileEditor extends StatelessWidget {
  const _FeeProfileEditor({required this.title, required this.profile, required this.onChange, this.hint});
  final String title;
  final FeeProfile profile;
  final ValueChanged<FeeProfile> onChange;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: AppColors.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onChange(FeeProfile(enabled: !profile.enabled, label: profile.label, structure: profile.structure, percent: profile.percent, flatCents: profile.flatCents)),
            child: Row(
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                Icon(profile.enabled ? LucideIcons.toggleRight : LucideIcons.toggleLeft, size: 30, color: profile.enabled ? AppColors.gold : AppColors.mute),
              ],
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!, style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4)),
          ],
          if (profile.enabled) ...[
            const SizedBox(height: 10),
            FieldLabeled(
              label: "Fee label (shown to the client)",
              child: _StableTextField(
                value: profile.label,
                placeholder: title,
                onChanged: (v) => onChange(FeeProfile(enabled: profile.enabled, label: v, structure: profile.structure, percent: profile.percent, flatCents: profile.flatCents)),
              ),
            ),
            const SizedBox(height: 10),
            _ChoiceRow(
              label: "Fee structure",
              value: profile.structure,
              options: const [("percentage", "Percentage"), ("flat", "Flat"), ("percentage_flat", "Percentage + flat")],
              onChange: (v) => onChange(FeeProfile(enabled: profile.enabled, label: profile.label, structure: v, percent: profile.percent, flatCents: profile.flatCents)),
            ),
            if (profile.structure != "flat") ...[
              const SizedBox(height: 10),
              _PercentRow(
                label: "Percentage rate",
                value: profile.percent,
                onChange: (v) => onChange(FeeProfile(enabled: profile.enabled, label: profile.label, structure: profile.structure, percent: v, flatCents: profile.flatCents)),
              ),
            ],
            if (profile.structure != "percentage") ...[
              const SizedBox(height: 10),
              _MoneyRow(
                label: "Flat amount",
                cents: profile.flatCents,
                onChange: (v) => onChange(FeeProfile(enabled: profile.enabled, label: profile.label, structure: profile.structure, percent: profile.percent, flatCents: v)),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The one WAIVER_DOCS entry Clients Tab's waiver editor manages directly
/// (same well-known id web uses) — plain multi-line text, not the rich-text
/// editor web ships (WaiverRichTextEditor.jsx is a real secondary editor
/// component; not worth a second bespoke editor in this port). Its own save
/// action, separate from the rest of the tab — waiver docs live in
/// `waiver_docs`, not the `platform_settings` blob.
const _signupWaiverId = "signup-waiver";

class _SignupWaiverEditor extends ConsumerStatefulWidget {
  const _SignupWaiverEditor();

  @override
  ConsumerState<_SignupWaiverEditor> createState() => _SignupWaiverEditorState();
}

class _SignupWaiverEditorState extends ConsumerState<_SignupWaiverEditor> {
  late final _title = TextEditingController(text: _existing()?.title ?? "Membership Waiver & Release");
  late final _body = TextEditingController(text: _existing()?.body ?? "");
  bool _saving = false;
  bool _flash = false;
  String? _error;

  WaiverDoc? _existing() {
    final list = ref.read(waiversProvider);
    for (final w in list) {
      if (w.id == _signupWaiverId) return w;
    }
    return null;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final existing = _existing();
    final doc = WaiverDoc(
      id: _signupWaiverId,
      title: _title.text.trim().isEmpty ? "Membership Waiver & Release" : _title.text.trim(),
      body: _body.text,
      scope: "general",
      required: true,
      archived: existing?.archived ?? false,
    );
    try {
      await SupabaseService.upsertWaiverDoc(doc);
      ref.read(waiversProvider.notifier).upsert(doc);
      if (!mounted) return;
      setState(() => _flash = true);
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _flash = false);
      });
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't save the waiver — please try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Waiver document", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          FieldLabeled(label: "Title", child: AppField(controller: _title, placeholder: "Membership Waiver & Release")),
          const SizedBox(height: 10),
          FieldLabeled(label: "Body", child: AppField(controller: _body, maxLines: 8, minLines: 4)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text("⚠ $_error", style: const TextStyle(color: AppColors.errorText, fontSize: 12)),
          ],
          if (_flash) ...[
            const SizedBox(height: 8),
            const Text("✓ Waiver saved.", style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 10),
          BtnGhost(onPressed: _saving ? null : _save, child: Text(_saving ? "Saving…" : "Save Waiver Document")),
        ],
      ),
    );
  }
}
