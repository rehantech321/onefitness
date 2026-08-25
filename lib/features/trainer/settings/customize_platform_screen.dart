import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/waiver_doc.dart";
import "../../../data/providers/platform_settings_provider.dart";
import "../../../data/providers/trainer_providers.dart";

const _tabs = [("scheduling", "Scheduling"), ("coaches", "Coaches"), ("clients", "Clients"), ("payments", "Payments"), ("workouts", "Workouts")];

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
/// now covering every field the real `platform_settings` row models
/// (previously ~7 fields; the ~13 added here — bookingCoachScope, required/
/// custom profile fields, full card+ACH fee profiles, checkout disclosure,
/// refund-fee toggle, business time zone, merit-badge tuning — already
/// existed in the real DB row and were silently ignored by this screen).
/// Explicit dirty-tracking + Save button (was: save-on-every-keystroke) —
/// matches web's draft/save flow so a partial edit can be discarded.
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
          child: SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _tabs.map((t) {
                final selected = _tab == t.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () => _switchTab(t.$1),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card, border: Border.all(color: selected ? AppColors.gold : AppColors.line), borderRadius: BorderRadius.circular(16)),
                      child: Text(t.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? AppColors.gold : AppColors.mute)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_tab == "scheduling") ...[
                  _NumberRow(label: "Late cancellation window (hours)", value: s.lateCancellationHours, onChange: (v) => _set((d) => d.copyWith(lateCancellationHours: v))),
                  _MoneyRow(label: "Late cancellation fee", cents: s.lateCancellationFeeCents, onChange: (v) => _set((d) => d.copyWith(lateCancellationFeeCents: v))),
                  _MoneyRow(label: "No-show fee", cents: s.noShowFeeCents, onChange: (v) => _set((d) => d.copyWith(noShowFeeCents: v))),
                  _ChoiceRow(label: "Block rescheduling inside that window?", value: s.blockRescheduleInWindow ? "block" : "chargeInstead", options: const [("block", "Block it entirely"), ("chargeInstead", "Allow it, but charge the late fee")], onChange: (v) => _set((d) => d.copyWith(blockRescheduleInWindow: v == "block"))),
                  _NumberRow(label: "Max booking horizon (days)", value: s.maxBookingHorizonDays, onChange: (v) => _set((d) => d.copyWith(maxBookingHorizonDays: v))),
                  _NumberRow(label: "Min booking lead time (hours)", value: s.minBookingLeadHours, onChange: (v) => _set((d) => d.copyWith(minBookingLeadHours: v))),
                  _ChoiceRow(label: "Clients book with", value: s.bookingCoachScope, options: const [("assigned", "Assigned coach only"), ("any", "Any coach")], onChange: (v) => _set((d) => d.copyWith(bookingCoachScope: v))),
                  _NumberRow(label: "Semi-private capacity", value: s.semiPrivateCap, onChange: (v) => _set((d) => d.copyWith(semiPrivateCap: v))),
                ],
                if (_tab == "coaches") ...[
                  _ChoiceRow(label: "Two-factor requirement", value: s.twoFactorRequirement, options: const [("off", "Off"), ("staff", "Staff"), ("everyone", "Everyone")], onChange: (v) => _set((d) => d.copyWith(twoFactorRequirement: v))),
                  _ChoiceRow(label: "Coach client scope", value: s.coachClientScope, options: const [("own", "Own clients only"), ("all", "All clients")], onChange: (v) => _set((d) => d.copyWith(coachClientScope: v))),
                  _ToggleRow(label: "Coaches can view revenue", value: s.coachCanViewRevenue, onChange: (v) => _set((d) => d.copyWith(coachCanViewRevenue: v))),
                  _ToggleRow(label: "Coaches can see other schedules", value: s.coachCanSeeOtherSchedules, onChange: (v) => _set((d) => d.copyWith(coachCanSeeOtherSchedules: v))),
                  _ChoiceRow(label: "Coaches reply in messages as", value: s.messageIdentity, options: const [("self", "Themselves"), ("business", "ONE Fitness")], onChange: (v) => _set((d) => d.copyWith(messageIdentity: v))),
                  const HintBox(text: "Building, approving, and assigning workout/nutrition programs is always owner-only — there's no coach-access toggle for it."),
                ],
                if (_tab == "clients") ...[
                  _MultiChoiceRow(label: "Required profile fields", value: s.requiredProfileFields, options: _requiredFieldOptions, onChange: (v) => _set((d) => d.copyWith(requiredProfileFields: v))),
                  const SizedBox(height: 4),
                  _CustomFieldsEditor(fields: s.customProfileFields, onChange: (v) => _set((d) => d.copyWith(customProfileFields: v))),
                  const SizedBox(height: 10),
                  _ToggleRow(label: "Require waiver at signup", value: s.requireWaiverAtSignup, onChange: (v) => _set((d) => d.copyWith(requireWaiverAtSignup: v))),
                  const SizedBox(height: 10),
                  const _SignupWaiverEditor(),
                  const SizedBox(height: 10),
                  _ToggleRow(label: "Clients can message any coach", value: s.clientsCanMessageAnyCoach, onChange: (v) => _set((d) => d.copyWith(clientsCanMessageAnyCoach: v))),
                ],
                if (_tab == "payments") ...[
                  _FeeProfileEditor(title: "Card processing fee", profile: s.cardFee, onChange: (v) => _set((d) => d.copyWith(cardFee: v))),
                  const SizedBox(height: 10),
                  _ToggleRow(label: "Offer bank transfer (ACH)", value: s.achOffered, onChange: (v) => _set((d) => d.copyWith(achOffered: v))),
                  if (s.achOffered) ...[
                    const SizedBox(height: 10),
                    _FeeProfileEditor(title: "Bank transfer (ACH) fee", profile: s.achFee, onChange: (v) => _set((d) => d.copyWith(achFee: v))),
                  ],
                  if (anyFeeEnabled) ...[
                    const SizedBox(height: 10),
                    FieldLabeled(label: "Checkout disclosure text", child: AppField(controller: TextEditingController(text: s.checkoutDisclosureText), placeholder: "A processing fee applies to this payment.", onChanged: (v) => _set((d) => d.copyWith(checkoutDisclosureText: v)))),
                    const SizedBox(height: 10),
                    _ToggleRow(label: "Refund fee when refunding a payment", value: s.refundFeeOnRefund, onChange: (v) => _set((d) => d.copyWith(refundFeeOnRefund: v))),
                  ],
                ],
                if (_tab == "workouts") ...[
                  _ToggleRow(label: "Auto carry over last weight", value: s.autoCarryOverLastWeight, onChange: (v) => _set((d) => d.copyWith(autoCarryOverLastWeight: v))),
                  _ChoiceRow(label: "Default weight unit", value: s.defaultWeightUnit, options: const [("lb", "lb"), ("kg", "kg")], onChange: (v) => _set((d) => d.copyWith(defaultWeightUnit: v))),
                  _ToggleRow(label: "Clients can swap exercises", value: s.clientsCanSwapExercises, onChange: (v) => _set((d) => d.copyWith(clientsCanSwapExercises: v))),
                  const SizedBox(height: 4),
                  FieldLabeled(label: "Business name", child: AppField(controller: TextEditingController(text: s.businessName), onChanged: (v) => _set((d) => d.copyWith(businessName: v)))),
                  const SizedBox(height: 10),
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
                  const SizedBox(height: 10),
                  const SectionLabel("Merit Badges"),
                  _NumberRow(label: "Progress Tracker — consecutive weeks", value: s.meritBadgeProgressWeeks, onChange: (v) => _set((d) => d.copyWith(meritBadgeProgressWeeks: v))),
                  _NumberRow(label: "Habit — consistency percent required", value: s.meritBadgeHabitPercent, onChange: (v) => _set((d) => d.copyWith(meritBadgeHabitPercent: v))),
                  _NumberRow(label: "Habit — consecutive weeks required", value: s.meritBadgeHabitWeeks, onChange: (v) => _set((d) => d.copyWith(meritBadgeHabitWeeks: v))),
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

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.label, required this.value, required this.onChange});
  final String label;
  final bool value;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => onChange(!value),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          Icon(value ? LucideIcons.toggleRight : LucideIcons.toggleLeft, size: 30, color: value ? AppColors.gold : AppColors.mute),
        ],
      ),
    );
  }
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({required this.label, required this.value, required this.onChange});
  final String label;
  final int value;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          SizedBox(
            width: 70,
            child: AppField(controller: TextEditingController(text: "$value"), keyboardType: TextInputType.number, onChanged: (v) => onChange(int.tryParse(v) ?? value)),
          ),
        ],
      ),
    );
  }
}

/// Cents-backed dollar field (e.g. "$5.00") — mirrors NumberField's
/// `prefix="$"` + `/100`/`*100` conversion in CustomizePlatform.jsx.
class _MoneyRow extends StatelessWidget {
  const _MoneyRow({required this.label, required this.cents, required this.onChange});
  final String label;
  final int cents;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          const Text("\$", style: TextStyle(color: AppColors.mute, fontSize: 13)),
          const SizedBox(width: 4),
          SizedBox(
            width: 70,
            child: AppField(
              controller: TextEditingController(text: (cents / 100).toStringAsFixed(2)),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) => onChange(((double.tryParse(v) ?? cents / 100) * 100).round()),
            ),
          ),
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
            child: AppField(
              controller: TextEditingController(text: "$value"),
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
  const _ChoiceRow({required this.label, required this.value, required this.options, required this.onChange});
  final String label;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChange;

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
          const Text("Full name and email can't be turned off. Phone / Birthday / City above are optional-or-required, your call.", style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4)),
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
                    child: AppField(
                      controller: TextEditingController(text: f.label),
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
  const _FeeProfileEditor({required this.title, required this.profile, required this.onChange});
  final String title;
  final FeeProfile profile;
  final ValueChanged<FeeProfile> onChange;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: AppColors.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              InkWell(
                onTap: () => onChange(FeeProfile(enabled: !profile.enabled, label: profile.label, structure: profile.structure, percent: profile.percent, flatCents: profile.flatCents)),
                child: Icon(profile.enabled ? LucideIcons.toggleRight : LucideIcons.toggleLeft, size: 30, color: profile.enabled ? AppColors.gold : AppColors.mute),
              ),
            ],
          ),
          if (profile.enabled) ...[
            const SizedBox(height: 10),
            FieldLabeled(
              label: "Fee label (shown to the client)",
              child: AppField(
                controller: TextEditingController(text: profile.label),
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
