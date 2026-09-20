import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/waiver_doc.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";
import "manage_coupons_screen.dart";

/// Dropdown option key/label pairs — mirrors SubTabs.jsx's mobile `<select>`
/// (this app is mobile-only, so that's the correct web analog to port, not
/// the desktop horizontal tab row). Labels here are the short dropdown
/// text; each tab's own in-page [_sectionTitle] can be longer.
const _tabs = [
  ("scheduling", "Scheduling"),
  ("services", "Services"),
  ("access", "Coaches & Security"),
  ("clients", "Clients"),
  ("payments", "Payments"),
  ("workouts", "Workouts & General"),
  ("coupons", "Coupons"),
  ("location", "Location"),
];

const _sessionTypeOptions = [
  ("semi-private", "Semi-Private"),
  ("one-on-one", "One-on-One"),
  ("large-group", "Large Group"),
];
const _disciplineOptions = [
  ("personal-training", "Personal Training"),
  ("boxing", "Boxing"),
  ("hike", "Hike"),
  ("outdoor-hiit", "Outdoor HIIT"),
  ("stretch", "Stretch"),
  ("stick-mobility", "Stick Mobility"),
  ("yoga", "Yoga"),
];

String _sectionTitle(String tab) => switch (tab) {
  "scheduling" => "Scheduling",
  "services" => "Services",
  "location" => "Location",
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
  "services" =>
    "What the gym offers. Anything switched off here stops appearing in the session type and discipline pickers — for staff creating or booking sessions and for clients booking. Existing bookings aren't affected.",
  "location" =>
    "Where the gym is. Shown to clients on any session whose coach hasn't set a location of their own, and used in the calendar feed.",
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

  /// Sections visited before this one — back steps through them in reverse
  /// before leaving Customize Platform.
  final List<String> _tabHistory = [];

  Future<void> _switchTab(String next, {bool fromBack = false}) async {
    if (next == _tab) return;
    final previous = _tab;
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
      if (fromBack) {
        _tabHistory.removeLast();
      } else {
        _tabHistory.add(previous);
      }
      _tab = next;
    });
  }

  void _backTab() {
    if (_tabHistory.isNotEmpty) _switchTab(_tabHistory.last, fromBack: true);
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
    return LocalBackScope(
      isOpen: _tabHistory.isNotEmpty,
      onBack: _backTab,
      child: _buildSections(context),
    );
  }

  Widget _buildSections(BuildContext context) {
    ref.listen<PlatformSettings>(platformSettingsProvider, (prev, next) {
      if (!_dirty) setState(() => _draft = next);
    });
    final s = _draft;
    final anyFeeEnabled = s.cardFee.enabled || (s.achOffered && s.achFee.enabled);

    final tabSelector = Padding(
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
    );

    // Coupons manage their own catalog with immediate per-row saves — it
    // doesn't fit this screen's single-draft/one-Save-button flow for the
    // other 5 tabs, so it gets its own independent scroll area instead of
    // nesting inside the shared SingleChildScrollView below.
    if (_tab == "coupons") {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [tabSelector, const Expanded(child: ManageCouponsScreen())],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tabSelector,
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
                if (_tab == "services") ...[
                  _CatalogEditor(
                    label: "Session types offered",
                    noun: "session type",
                    value: s.offeredSessionTypes,
                    options: _sessionTypeOptions,
                    labelFor: sessionTypeLabel,
                    onChange: (v) => _set((d) => d.copyWith(offeredSessionTypes: v)),
                  ),
                  const SizedBox(height: 10),
                  // Class size per type — what the booking screen counts down
                  // ("3 of 4 open") and what the database refuses to exceed.
                  _ClassSizeEditor(
                    types: s.offeredSessionTypes,
                    caps: s.sessionTypeCaps,
                    semiPrivateCap: s.semiPrivateCap,
                    onChange: (v) => _set((d) => d.copyWith(sessionTypeCaps: v)),
                  ),
                  const SizedBox(height: 10),
                  _CatalogEditor(
                    label: "Disciplines offered",
                    noun: "discipline",
                    value: s.offeredDisciplines,
                    options: _disciplineOptions,
                    labelFor: disciplineLabel,
                    onChange: (v) => _set((d) => d.copyWith(offeredDisciplines: v)),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Anything added here shows up for coaches (on their profile and availability), on the schedule when creating a session, "
                    "and for clients when booking. Assessments are always available to staff regardless of these settings.",
                    style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
                  ),
                ],
                if (_tab == "location") ...[
                  FieldLabeled(
                    label: "Location name",
                    child: _StableTextField(value: s.locationName, placeholder: "e.g. ONE Fitness Studio", onChanged: (v) => _set((d) => d.copyWith(locationName: v))),
                  ),
                  const SizedBox(height: 10),
                  FieldLabeled(
                    label: "Address",
                    child: _StableTextField(value: s.locationAddress, placeholder: "Street, city, state, ZIP", onChanged: (v) => _set((d) => d.copyWith(locationAddress: v))),
                  ),
                  const SizedBox(height: 10),
                  FieldLabeled(
                    label: "Parking / arrival notes",
                    child: _StableTextField(value: s.locationHint, placeholder: "e.g. Park in the rear lot, side entrance", onChanged: (v) => _set((d) => d.copyWith(locationHint: v))),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "A coach can still set their own location on their profile; that wins for their sessions. This is the gym-wide default.",
                    style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  // More than one site: each extra one can be picked when
                  // creating a session (Schedule → Advanced settings).
                  _ExtraLocationsEditor(
                    locations: s.locations,
                    mainName: s.locationName,
                    onChange: (v) => _set((d) => d.copyWith(locations: v)),
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
                  const SizedBox(height: 10),
                  _ToggleRow(
                    label: "Set a default billing date for new memberships",
                    hint: "Off (default): a new membership just bills on whatever day the client checks out on, like today. On: every new subscription bills on the same day-of-month going forward — you can still override this per client later, including already-active memberships, from their profile.",
                    value: s.defaultBillingAnchorDay != null,
                    onChange: (v) => _set((d) => v ? d.copyWith(defaultBillingAnchorDay: d.defaultBillingAnchorDay ?? 1) : d.copyWith(clearDefaultBillingAnchorDay: true)),
                  ),
                  if (s.defaultBillingAnchorDay != null) ...[
                    const SizedBox(height: 10),
                    _NumberRow(
                      label: "Day of the month",
                      hint: "1-28 only, to avoid short-month issues (every month has a 28th). Applies to new memberships from now on — never retroactively shifts an existing client's billing date.",
                      value: s.defaultBillingAnchorDay!,
                      onChange: (v) => _set((d) => d.copyWith(defaultBillingAnchorDay: v.clamp(1, 28))),
                    ),
                  ],
                ],
                if (_tab == "workouts") ...[
                  _ToggleRow(
                    label: "Auto carry-over last logged weight",
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

/// The gym's catalogue of session types or disciplines (Customize Platform →
/// Services). Each one offered is a chip with a delete button; deleting it
/// removes it from the whole app — booking, coach profiles, plan editing,
/// Create Session, the schedule — via the offered lists every one of those
/// reads (see OfferedCatalog / LiveCatalog). Deleted ones are listed below
/// so a mistake can be undone. Changes apply when the owner taps Save.
class _CatalogEditor extends StatelessWidget {
  const _CatalogEditor({
    required this.label,
    required this.noun,
    required this.value,
    required this.options,
    required this.onChange,
    required this.labelFor,
  });
  final String label;
  final String noun;
  final List<String> value;

  /// The built-in catalogue. Anything the owner added themselves is in
  /// [value] only, and is listed alongside these.
  final List<(String, String)> options;
  final ValueChanged<List<String>> onChange;

  /// How a key is displayed — handles both built-ins and owner-added keys.
  final String Function(String) labelFor;

  List<(String, String)> get _all => [
        ...options,
        for (final k in value)
          if (!options.any((o) => o.$1 == k)) (k, labelFor(k)),
      ];

  Future<void> _add(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text("Add a $noun"),
        content: AppField(controller: controller, placeholder: noun == "discipline" ? "e.g. Pilates" : "e.g. Small Group"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text("Add")),
        ],
      ),
    );
    final key = slugifyName(name ?? "");
    if (key.isEmpty || value.contains(key)) return;
    onChange([...value, key]);
  }

  Future<void> _confirmDelete(BuildContext context, (String, String) o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text("Delete ${o.$2}?"),
        content: Text(
          "${o.$2} will be removed from the whole app — clients can't book it, and it disappears from coach profiles, "
          "plans and the schedule. Sessions already booked stay as they are. You can restore it below any time. "
          "Tap Save to apply.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Keep")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) onChange(value.where((k) => k != o.$1).toList());
  }

  @override
  Widget build(BuildContext context) {
    final offered = _all.where((o) => value.contains(o.$1)).toList();
    final deleted = _all.where((o) => !value.contains(o.$1)).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (offered.isEmpty)
            Row(
              children: [
                Text("No ${noun}s offered.", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                const Spacer(),
                TextButton(
                  onPressed: () => _add(context),
                  style: TextButton.styleFrom(foregroundColor: AppColors.gold),
                  child: Text("Add $noun", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final o in offered)
                  Container(
                    padding: const EdgeInsets.only(left: 10, right: 2),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.15),
                      border: Border.all(color: AppColors.gold),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(o.$2, style: const TextStyle(fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w600)),
                        IconButton(
                          tooltip: "Delete",
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                          padding: EdgeInsets.zero,
                          onPressed: () => _confirmDelete(context, o),
                          icon: const Icon(LucideIcons.x, size: 14, color: AppColors.gold),
                        ),
                      ],
                    ),
                  ),
                // Add one of the gym's own — it then behaves exactly like a
                // built-in everywhere in the app.
                InkWell(
                  onTap: () => _add(context),
                  borderRadius: BorderRadius.circular(7),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.goldDim),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.plus, size: 13, color: AppColors.gold),
                        const SizedBox(width: 4),
                        Text("Add $noun", style: const TextStyle(fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          if (deleted.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text("Deleted — tap to restore", style: TextStyle(fontSize: 11, color: AppColors.mute)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final o in deleted)
                  InkWell(
                    onTap: () => onChange([...value, o.$1]),
                    borderRadius: BorderRadius.circular(7),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        border: Border.all(color: AppColors.line),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.plus, size: 12, color: AppColors.mute),
                          const SizedBox(width: 4),
                          Text(o.$2, style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The gym's other locations, beyond the main one above. Each can be picked
/// when creating a session (Schedule → Advanced settings), and clients see
/// the location of the session they book.
class _ExtraLocationsEditor extends StatelessWidget {
  const _ExtraLocationsEditor({required this.locations, required this.mainName, required this.onChange});
  final List<GymLocation> locations;
  final String mainName;
  final ValueChanged<List<GymLocation>> onChange;

  Future<void> _edit(BuildContext context, {GymLocation? existing, int? index}) async {
    final name = TextEditingController(text: existing?.name ?? "");
    final address = TextEditingController(text: existing?.address ?? "");
    final hint = TextEditingController(text: existing?.hint ?? "");
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(existing == null ? "Add a location" : "Edit location"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FieldLabeled(label: "Name", child: AppField(controller: name, placeholder: "e.g. ONE Fitness Burbank")),
              const SizedBox(height: 8),
              FieldLabeled(label: "Address", child: AppField(controller: address, placeholder: "Street, city, state, ZIP")),
              const SizedBox(height: 8),
              FieldLabeled(label: "Parking / arrival notes", child: AppField(controller: hint, placeholder: "e.g. Park in the rear lot")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
        ],
      ),
    );
    if (saved != true || name.text.trim().isEmpty) return;
    final next = [...locations];
    final entry = GymLocation(name: name.text.trim(), address: address.text.trim(), hint: hint.text.trim());
    if (index == null) {
      next.add(entry);
    } else {
      next[index] = entry;
    }
    onChange(next);
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Other locations", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            mainName.trim().isEmpty
                ? "Set the main location above first."
                : "$mainName is the main one. Add any other site you run sessions at — you pick the location when creating a session.",
            style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < locations.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(LucideIcons.mapPin, size: 15, color: AppColors.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(locations[i].name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        if (locations[i].address.isNotEmpty)
                          Text(locations[i].address, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: "Edit",
                    onPressed: () => _edit(context, existing: locations[i], index: i),
                    icon: const Icon(LucideIcons.pencil, size: 15, color: AppColors.mute),
                  ),
                  IconButton(
                    tooltip: "Remove",
                    onPressed: () => onChange([...locations]..removeAt(i)),
                    icon: const Icon(LucideIcons.trash2, size: 15, color: AppColors.mute),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _edit(context),
              style: TextButton.styleFrom(foregroundColor: AppColors.gold, padding: EdgeInsets.zero),
              icon: const Icon(LucideIcons.plus, size: 14),
              label: const Text("Add location", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

/// How many clients fit in each session type — the number the booking screen
/// counts down ("3 of 4 open") and the database enforces on every booking.
/// One-on-one and the assessments are fixed at one by definition.
class _ClassSizeEditor extends StatelessWidget {
  const _ClassSizeEditor({
    required this.types,
    required this.caps,
    required this.semiPrivateCap,
    required this.onChange,
  });
  final List<String> types;
  final Map<String, int> caps;
  final int semiPrivateCap;
  final ValueChanged<Map<String, int>> onChange;

  static const _fixedAtOne = {"one-on-one", "assessment-call", "assessment-in-person"};

  int _current(String type) =>
      caps[type] ?? (type == "large-group" ? 15 : (type == "semi-private" ? semiPrivateCap : semiPrivateCap));

  @override
  Widget build(BuildContext context) {
    final editable = types.where((t) => !_fixedAtOne.contains(t)).toList();
    if (editable.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Class size limit", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          const Text(
            "The most clients one session of each type takes. Booking stops at this number.",
            style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
          ),
          const SizedBox(height: 8),
          for (final t in editable)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text(sessionTypeLabel(t), style: const TextStyle(fontSize: 13))),
                  SizedBox(
                    width: 70,
                    child: _StableTextField(
                      value: "${_current(t)}",
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final n = int.tryParse(v.trim());
                        if (n == null || n < 1) return;
                        onChange({...caps, t: n});
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text("clients", style: TextStyle(fontSize: 12, color: AppColors.mute)),
                ],
              ),
            ),
          const Text(
            "One-on-One and assessments are always one client.",
            style: TextStyle(fontSize: 11, color: AppColors.mute),
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
