import "dart:convert";
import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/utils/photo_picker_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/availability_block.dart";
import "../../../data/models/trainer.dart";
import "availability_block_editor.dart";

const _largeGroupDisciplines = {"hike", "outdoor-hiit"};
const _regularSessionTypes = ["semi-private", "one-on-one"];
const _assessmentSessionTypes = ["assessment-call", "assessment-in-person"];

bool _isRegularDiscipline(String d) =>
    d != "programmer" && !_largeGroupDisciplines.contains(d);
bool _isAssessmentType(String st) =>
    st == "assessment-call" || st == "assessment-in-person";

bool _disciplineAllowedForType(String d, String st) {
  if (d == "stretch") return st == "one-on-one";
  if (_largeGroupDisciplines.contains(d)) return st == "large-group";
  return true;
}

class _BlockEditRequest {
  const _BlockEditRequest({
    required this.sessionType,
    required this.disciplineOptions,
    this.editIndex,
    this.isLargeGroup = false,
  });
  final String sessionType;
  final List<String> disciplineOptions;
  final int? editIndex; // null = adding a new block
  final bool isLargeGroup;
}

/// Mirrors TrainerForm.jsx's self-edit (`isOwnerEdit: false`) and
/// owner-edit (`isOwnerEdit: true`) paths — the same shared form on the web,
/// differing only in commission rate (owner-only) and delete (owner-only).
/// Trimmed per plan: no 6-month availability lock/override, no
/// booking-conflict-on-narrowed-availability prompt, no Programmer
/// assessment-call/in-person availability scheduling UI, no 2FA section,
/// Before & After uses a plain picker (no dedicated crop/rotate step).
class TrainerEditForm extends StatefulWidget {
  const TrainerEditForm({
    super.key,
    required this.initial,
    required this.isOwnerEditing,
    required this.onCancel,
    required this.onSave,
    this.onDelete,
  });

  final Trainer? initial;
  final bool isOwnerEditing; // whether commission rate + delete are shown
  final VoidCallback onCancel;

  /// [password] is only ever non-null on the create-new-trainer path
  /// (`initial == null`) — editing an existing trainer never passes one.
  final void Function(Trainer trainer, String? password) onSave;
  final VoidCallback? onDelete;

  @override
  State<TrainerEditForm> createState() => _TrainerEditFormState();
}

class _TrainerEditFormState extends State<TrainerEditForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? "");
  late final _email = TextEditingController(text: widget.initial?.email ?? "");
  late final _phone = TextEditingController(text: widget.initial?.phone ?? "");
  late final _bio = TextEditingController(text: widget.initial?.bio ?? "");
  late final _coachCode = TextEditingController(text: widget.initial?.coachCode ?? "");
  late String _payoutMode = widget.initial?.payoutMode ?? "perSession";
  late final _payoutRate = TextEditingController(
    text: (((widget.initial?.payoutRateCents ?? 0)) / 100).toStringAsFixed(2),
  );
  late final _referralPercent = TextEditingController(
    text: "${widget.initial?.referralCommissionPercent ?? 0}",
  );
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();

  String? _photoDataUrl; // null = keep widget.initial?.photo as-is
  bool _pickingPhoto = false;
  late final Set<String> _disciplines = {
    ...(widget.initial?.disciplines ?? const []),
  };
  late final Set<String> _sessionTypes = {
    ...(widget.initial?.sessionTypes ?? const []),
  };
  late List<AvailabilityBlock> _availability = [
    ...(widget.initial?.availability ?? const []),
  ];
  late List<TrainerLocation> _locations = [
    ...(widget.initial?.locations ?? const []),
  ];
  late List<TrainerBeforeAfter> _beforeAfters = [
    ...(widget.initial?.beforeAfters ?? const []),
  ];
  late List<TrainerUnavailability> _unavailability = [
    ...(widget.initial?.unavailability ?? const []),
  ];

  String _tab = "profile"; // "profile" | "availability"
  _BlockEditRequest? _editingBlock;
  String? _error;
  bool _resetBusy = false;
  bool _resetSent = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _bio.dispose();
    _coachCode.dispose();
    _payoutRate.dispose();
    _referralPercent.dispose();
    _pw.dispose();
    _pw2.dispose();
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

  void _toggleDiscipline(String d) {
    setState(() {
      if (_disciplines.contains(d)) {
        _disciplines.remove(d);
      } else {
        _disciplines.add(d);
      }
      final hasRegular = _disciplines.any(_isRegularDiscipline);
      final hasProgrammer = _disciplines.contains("programmer");
      _sessionTypes.removeWhere(
        (st) => _isAssessmentType(st) ? !hasProgrammer : !hasRegular,
      );
      _error = null;
    });
  }

  void _toggleSessionType(String st) {
    setState(() {
      _sessionTypes.contains(st)
          ? _sessionTypes.remove(st)
          : _sessionTypes.add(st);
      _error = null;
    });
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
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              "Couldn't send the reset email — check your connection and try again.",
        );
    } finally {
      if (mounted) setState(() => _resetBusy = false);
    }
  }

  void _submit() {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty) return setState(() => _error = "Full name is required.");
    if (email.isEmpty)
      return setState(() => _error = "A valid email is required.");
    if (phone.isEmpty)
      return setState(() => _error = "Phone number is required.");
    if (_disciplines.isEmpty)
      return setState(() => _error = "Choose at least one discipline.");
    final hasRegular = _disciplines.any(_isRegularDiscipline);
    final regularTypesChosen = _sessionTypes
        .where((st) => !_isAssessmentType(st))
        .toList();
    if (hasRegular && regularTypesChosen.isEmpty) {
      return setState(
        () => _error =
            "Choose at least one session type (Semi-Private or One-on-One).",
      );
    }
    if (widget.initial == null) {
      if (_pw.text.length < 6)
        return setState(
          () => _error = "Password must be at least 6 characters.",
        );
      if (_pw.text != _pw2.text)
        return setState(() => _error = "Passwords don't match.");
    }
    setState(() => _error = null);
    widget.onSave(
      Trainer(
        id:
            widget.initial?.id ??
            "trainer-${DateTime.now().microsecondsSinceEpoch}",
        name: name,
        email: email,
        phone: phone,
        photo: _photoDataUrl ?? widget.initial?.photo,
        disciplines: _disciplines.toList(),
        sessionTypes: _sessionTypes.toList(),
        locations: _locations,
        bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        beforeAfters: _beforeAfters,
        availability: _availability,
        commissionRate: widget.initial?.commissionRate ?? 0,
        payoutMode: _payoutMode,
        payoutRateCents: ((double.tryParse(_payoutRate.text.trim()) ?? 0) * 100).round(),
        referralCommissionPercent:
            num.tryParse(_referralPercent.text.trim()) ??
            (widget.initial?.referralCommissionPercent ?? 0),
        // Locked after creation — never taken from the (disabled-when-
        // editing) text field once a trainer already exists.
        coachCode: widget.initial != null
            ? widget.initial!.coachCode
            : (_coachCode.text.trim().isEmpty ? null : _coachCode.text.trim()),
        unavailability: _unavailability,
      ),
      widget.initial == null ? _pw.text : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_editingBlock != null) {
      final req = _editingBlock!;
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _editingBlock = null),
        child: AvailabilityBlockEditor(
          sessionType: req.sessionType,
          disciplineOptions: req.disciplineOptions,
          initial: req.editIndex != null ? _availability[req.editIndex!] : null,
          isLargeGroup: req.isLargeGroup,
          onCancel: () => setState(() => _editingBlock = null),
          onSave: (block) => setState(() {
            if (req.editIndex != null) {
              _availability = [..._availability];
              _availability[req.editIndex!] = block;
            } else {
              _availability = [..._availability, block];
            }
            _editingBlock = null;
          }),
        ),
      );
    }

    final hasRegularDiscipline = _disciplines.any(_isRegularDiscipline);
    final hasProgrammer = _disciplines.contains("programmer");
    final largeGroupDisciplines = _disciplines
        .where(_largeGroupDisciplines.contains)
        .toList();
    final regularSessionTypesChosen = _sessionTypes
        .where((st) => !_isAssessmentType(st))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(
            onBack: widget.onCancel,
            title: widget.initial != null ? "Edit trainer" : "Add trainer",
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _TabChip(label: "Profile", selected: _tab == "profile", onTap: () => setState(() => _tab = "profile")),
              const SizedBox(width: 8),
              _TabChip(label: "Availability", selected: _tab == "availability", onTap: () => setState(() => _tab = "availability")),
            ],
          ),
          const SizedBox(height: 14),
          if (_tab == "profile") ...[
          Row(
            children: [
              GestureDetector(
                onTap: _pickingPhoto ? null : _pickPhoto,
                child: Container(
                  width: 56,
                  height: 56,
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
                      ? Avatar(
                          src: widget.initial?.photo,
                          name: _name.text,
                          size: 56,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextButton.icon(
                  onPressed: _pickingPhoto ? null : _pickPhoto,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    alignment: Alignment.centerLeft,
                  ),
                  icon: const Icon(LucideIcons.image, size: 14),
                  label: Text(
                    _pickingPhoto
                        ? "Opening…"
                        : ((_photoDataUrl ?? widget.initial?.photo) != null
                              ? "Change photo"
                              : "Add photo"),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FieldLabeled(
            label: "Full name *",
            child: AppField(
              controller: _name,
              placeholder: "First Last",
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Email *",
            child: AppField(
              controller: _email,
              placeholder: "name@email.com",
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Phone *",
            child: AppField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Disciplines * (choose one or more)",
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: kDisciplineLabels.entries
                  .map(
                    (e) => _Chip(
                      label: e.value,
                      on: _disciplines.contains(e.key),
                      onTap: () => _toggleDiscipline(e.key),
                    ),
                  )
                  .toList(),
            ),
          ),
          if (hasRegularDiscipline) ...[
            const SizedBox(height: 10),
            FieldLabeled(
              label: "Session types * (choose one or more)",
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _regularSessionTypes
                    .map(
                      (st) => _Chip(
                        label: sessionTypeLabel(st),
                        on: _sessionTypes.contains(st),
                        onTap: () => _toggleSessionType(st),
                      ),
                    )
                    .toList(),
              ),
            ),
            if (largeGroupDisciplines.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  "Hike and Outdoor HIIT are large group sessions — their availability is set separately below and does not use Semi-Private or One-on-One.",
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.mute,
                    height: 1.4,
                  ),
                ),
              ),
          ],
          if (hasProgrammer) ...[
            const SizedBox(height: 10),
            FieldLabeled(
              label: "Assessment types * (choose one or more)",
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _assessmentSessionTypes
                    .map(
                      (st) => _Chip(
                        label: sessionTypeLabel(st),
                        on: _sessionTypes.contains(st),
                        onTap: () => _toggleSessionType(st),
                      ),
                    )
                    .toList(),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                "These are what clients see when booking a programmer. Scheduling assessment availability isn't available from the app yet — contact ONE Fitness to set this up.",
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.mute,
                  height: 1.4,
                ),
              ),
            ),
          ],
          ], // end profile tab (identity/offering fields)
          if (_tab == "availability") ...[
          if (hasRegularDiscipline) ...[
            const SizedBox(height: 16),
            const Text(
              "AVAILABILITY SCHEDULE",
              style: TextStyle(
                fontSize: 11,
                color: AppColors.mute,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            if (regularSessionTypesChosen.isEmpty)
              const Text(
                "Pick session types and disciplines first, then add availability blocks.",
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.mute,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              ...regularSessionTypesChosen.map((st) {
                final disciplineOptions = _disciplines
                    .where(
                      (d) =>
                          _isRegularDiscipline(d) &&
                          _disciplineAllowedForType(d, st),
                    )
                    .toList();
                if (disciplineOptions.isEmpty) return const SizedBox.shrink();
                final entries = <MapEntry<int, AvailabilityBlock>>[];
                for (var i = 0; i < _availability.length; i++) {
                  final b = _availability[i];
                  if (b.sessionType == st &&
                      !_largeGroupDisciplines.contains(b.discipline) &&
                      _disciplineAllowedForType(b.discipline, st))
                    entries.add(MapEntry(i, b));
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (regularSessionTypesChosen.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(
                                LucideIcons.calendar,
                                size: 13,
                                color: AppColors.gold,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "${sessionTypeLabel(st)} schedule",
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.gold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ...entries.map(
                        (entry) => _BlockRow(
                          block: entry.value,
                          showDisciplineTag: disciplineOptions.length > 1,
                          onEdit: () => setState(
                            () => _editingBlock = _BlockEditRequest(
                              sessionType: st,
                              disciplineOptions: disciplineOptions,
                              editIndex: entry.key,
                            ),
                          ),
                          onRemove: () => setState(
                            () =>
                                _availability = [..._availability]
                                  ..removeAt(entry.key),
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(
                          () => _editingBlock = _BlockEditRequest(
                            sessionType: st,
                            disciplineOptions: disciplineOptions,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.gold,
                          side: const BorderSide(color: AppColors.goldDim),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                        ),
                        icon: const Icon(LucideIcons.plus, size: 13),
                        label: Text(
                          "Add ${disciplineOptions.length > 1 ? 'discipline/' : ''}days for ${sessionTypeLabel(st)}",
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _disciplines.length > 1
                    ? "Each block covers one discipline's days/times — add one per discipline if they run on different schedules."
                    : "Tap a day, then tap times for that day. Add more days the same way.",
                style: const TextStyle(fontSize: 11, color: AppColors.mute),
              ),
            ),
          ],
          if (largeGroupDisciplines.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              "LARGE GROUP AVAILABILITY",
              style: TextStyle(
                fontSize: 11,
                color: AppColors.mute,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.03),
                border: Border.all(color: AppColors.goldDim),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                "Hike and Outdoor HIIT are large group sessions — 1 hour, capacity 15, starting on the hour every hour with a 15-minute buffer before and after. Not bookable as Semi-Private or One-on-One.",
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.mute,
                  height: 1.5,
                ),
              ),
            ),
            ...largeGroupDisciplines.map((d) {
              final entries = <MapEntry<int, AvailabilityBlock>>[];
              for (var i = 0; i < _availability.length; i++) {
                final b = _availability[i];
                if (b.sessionType == "large-group" && b.discipline == d)
                  entries.add(MapEntry(i, b));
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.calendar,
                          size: 13,
                          color: AppColors.gold,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "${disciplineLabel(d)} schedule",
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.gold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...entries.map(
                      (entry) => _BlockRow(
                        block: entry.value,
                        showDisciplineTag: false,
                        onEdit: () => setState(
                          () => _editingBlock = _BlockEditRequest(
                            sessionType: "large-group",
                            disciplineOptions: [d],
                            editIndex: entry.key,
                            isLargeGroup: true,
                          ),
                        ),
                        onRemove: () => setState(
                          () =>
                              _availability = [..._availability]
                                ..removeAt(entry.key),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(
                        () => _editingBlock = _BlockEditRequest(
                          sessionType: "large-group",
                          disciplineOptions: [d],
                          isLargeGroup: true,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.gold,
                        side: const BorderSide(color: AppColors.goldDim),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                      ),
                      icon: const Icon(LucideIcons.plus, size: 13),
                      label: Text(
                        "Add days for ${disciplineLabel(d)}",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 18),
          _UnavailabilitySection(
            entries: _unavailability,
            onChange: (v) => setState(() => _unavailability = v),
          ),
          ], // end availability tab
          if (_tab == "profile") ...[
          const SizedBox(height: 18),
          const Text(
            "WHERE YOU TRAIN — PICK A LOCATION OR CREATE YOUR OWN",
            style: TextStyle(
              fontSize: 11,
              color: AppColors.mute,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          LocationsEditor(
            value: _locations,
            onChange: (v) => setState(() => _locations = v),
          ),
          const SizedBox(height: 14),
          FieldLabeled(
            label: "Coach Code",
            child: widget.initial != null
                ? AppCard(
                    child: Text(
                      widget.initial!.coachCode?.isNotEmpty == true ? widget.initial!.coachCode! : "Not set",
                      style: const TextStyle(fontSize: 14, color: AppColors.mute),
                    ),
                  )
                : AppField(controller: _coachCode, placeholder: "e.g. JESS10"),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              widget.initial != null
                  ? "Set once at signup and can't be changed."
                  : "A unique code this coach gives clients at signup to link referrals to them.",
              style: const TextStyle(fontSize: 11, color: AppColors.mute),
            ),
          ),
          if (widget.isOwnerEditing) ...[
            const SizedBox(height: 14),
            const Text(
              "PAY PER SESSION WORKED",
              style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 0.5),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: const [
                ("perClient", "Per client"),
                ("perHour", "Per hour"),
                ("perSession", "Per session"),
              ].map((opt) {
                final selected = _payoutMode == opt.$1;
                return InkWell(
                  onTap: () => setState(() => _payoutMode = opt.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: selected ? AppColors.gold : AppColors.line),
                      color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg,
                    ),
                    child: Text(opt.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? AppColors.gold : AppColors.txt)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            FieldLabeled(
              label: switch (_payoutMode) {
                "perClient" => "Rate per client (\$)",
                "perHour" => "Rate per hour (\$)",
                _ => "Base rate per session (\$)",
              },
              child: AppField(controller: _payoutRate, keyboardType: TextInputType.number),
            ),
            const SizedBox(height: 10),
            FieldLabeled(
              label: "Referral commission (%)",
              child: AppField(controller: _referralPercent, keyboardType: TextInputType.number),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                "Percent of every membership/package purchase by a client this coach referred (via their Coach Code) — charged to the client as a surcharge and paid to this coach.",
                style: TextStyle(fontSize: 11, color: AppColors.mute),
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            "BIO (OPTIONAL, BUT RECOMMENDED)",
            style: TextStyle(
              fontSize: 11,
              color: AppColors.mute,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
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
            "BEFORE & AFTER (OPTIONAL)",
            style: TextStyle(
              fontSize: 11,
              color: AppColors.mute,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              "Show client transformations. Add a Before and After photo for each frame. Up to 6 sets.",
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
          const SizedBox(height: 18),
          Container(height: 1, color: AppColors.line),
          const SizedBox(height: 14),
          if (widget.initial != null) ...[
            Text(
              "Password changes go through email now, not this form — click below to send a reset link to ${_email.text.trim().isEmpty ? "this account's email" : _email.text.trim()}.",
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
          ] else ...[
            FieldLabeled(
              label: "Create password *",
              child: AppField(controller: _pw, obscureText: true),
            ),
            const SizedBox(height: 10),
            FieldLabeled(
              label: "Confirm password",
              child: AppField(controller: _pw2, obscureText: true),
            ),
          ],
          ], // end profile tab (location/coach-code/payout/bio/before-after/password)
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.errorText, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: BtnGold(
                  onPressed: _submit,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.check, size: 15),
                      const SizedBox(width: 6),
                      Text(
                        widget.initial != null ? "Save changes" : "Add trainer",
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              BtnGhost(onPressed: widget.onCancel, child: const Text("Cancel")),
            ],
          ),
          if (widget.onDelete != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: widget.onDelete,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFC97F7F),
              ),
              child: const Text("Remove trainer"),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.gold : AppColors.line),
          color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg,
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? AppColors.gold : AppColors.mute)),
      ),
    );
  }
}

/// Add/list/delete time-off entries — mirrors the Coach Availability Tab
/// spec's Unavailability feature. Purely local state (like the availability
/// blocks above it); committed together with everything else when the form's
/// main Save button is tapped, not saved independently.
class _UnavailabilitySection extends StatefulWidget {
  const _UnavailabilitySection({required this.entries, required this.onChange});
  final List<TrainerUnavailability> entries;
  final ValueChanged<List<TrainerUnavailability>> onChange;

  @override
  State<_UnavailabilitySection> createState() => _UnavailabilitySectionState();
}

class _UnavailabilitySectionState extends State<_UnavailabilitySection> {
  bool _adding = false;
  String? _start;
  String? _end;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = DateTime.tryParse((isStart ? _start : _end) ?? "") ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    final iso = "${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
    setState(() {
      if (isStart) {
        _start = iso;
        // A single-day entry is the common case — keep end in sync with
        // start until the coach deliberately picks a later end date.
        if (_end == null || _end!.compareTo(iso) < 0) _end = iso;
      } else {
        _end = iso;
      }
    });
  }

  void _add() {
    if (_start == null) return;
    final entry = TrainerUnavailability(
      id: "unavail-${DateTime.now().microsecondsSinceEpoch}",
      startDate: _start!,
      endDate: _end ?? _start!,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    widget.onChange([...widget.entries, entry]);
    setState(() {
      _adding = false;
      _start = null;
      _end = null;
      _note.clear();
    });
  }

  void _remove(String id) => widget.onChange(widget.entries.where((e) => e.id != id).toList());

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.entries]..sort((a, b) => a.startDate.compareTo(b.startDate));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "UNAVAILABILITY",
          style: TextStyle(fontSize: 11, color: AppColors.mute, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
        const SizedBox(height: 6),
        const Text(
          "Block off time you won't be working — clients won't be able to book you during these dates. Sessions already booked in this window aren't affected; reschedule or cancel those yourself if needed.",
          style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
        ),
        const SizedBox(height: 10),
        if (sorted.isEmpty && !_adding)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text("No time off scheduled.", style: TextStyle(fontSize: 12, color: AppColors.mute, fontStyle: FontStyle.italic)),
          ),
        ...sorted.map((e) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.startDate == e.endDate ? niceDate(e.startDate) : "${niceDate(e.startDate)} – ${niceDate(e.endDate)}",
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        if (e.note != null && e.note!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(e.note!, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _remove(e.id),
                    icon: const Icon(LucideIcons.trash2, size: 14, color: Color(0xFF6B3B3B)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            )),
        if (_adding) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FieldLabeled(
                        label: "Start date",
                        child: InkWell(
                          onTap: () => _pickDate(isStart: true),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.card,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
                            ),
                            child: Text(_start ?? "Select date", style: TextStyle(fontSize: 13, color: _start == null ? AppColors.mute : AppColors.txt)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FieldLabeled(
                        label: "End date",
                        child: InkWell(
                          onTap: _start == null ? null : () => _pickDate(isStart: false),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.card,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
                            ),
                            child: Text(_end ?? _start ?? "Same as start", style: TextStyle(fontSize: 13, color: (_end ?? _start) == null ? AppColors.mute : AppColors.txt)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FieldLabeled(label: "Note (optional)", child: AppField(controller: _note, placeholder: "e.g. Vacation, Sick")),
                const SizedBox(height: 10),
                Row(
                  children: [
                    BtnGold(onPressed: _start == null ? null : _add, child: const Text("Add")),
                    const SizedBox(width: 8),
                    BtnGhost(
                      onPressed: () => setState(() {
                        _adding = false;
                        _start = null;
                        _end = null;
                        _note.clear();
                      }),
                      child: const Text("Cancel"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ] else
          TextButton.icon(
            onPressed: () => setState(() => _adding = true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.gold,
              side: const BorderSide(color: AppColors.goldDim),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            ),
            icon: const Icon(LucideIcons.plus, size: 13),
            label: const Text("Add Unavailability", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
}

class _BlockRow extends StatelessWidget {
  const _BlockRow({
    required this.block,
    required this.showDisciplineTag,
    required this.onEdit,
    required this.onRemove,
  });
  final AvailabilityBlock block;
  final bool showDisciplineTag;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  static const _weekdayOrder = [1, 2, 3, 4, 5, 6];
  static const _weekdayShort = {
    1: "Mon",
    2: "Tue",
    3: "Wed",
    4: "Thu",
    5: "Fri",
    6: "Sat",
  };

  @override
  Widget build(BuildContext context) {
    final dayLines = <Widget>[];
    for (final d in _weekdayOrder) {
      final slots = [...(block.byDay[d] ?? const <int>[])]..sort();
      if (slots.isEmpty) continue;
      dayLines.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: "${_weekdayShort[d]} ",
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.txt,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: slots.map(fmtSlotShort).join(" "),
                  style: const TextStyle(fontSize: 11, color: AppColors.mute),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showDisciplineTag)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Tag(
                      text: disciplineLabel(block.discipline),
                      gold: true,
                    ),
                  ),
                if (dayLines.isEmpty)
                  const Text(
                    "No times set",
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.mute,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  ...dayLines,
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                onPressed: onEdit,
                icon: const Icon(
                  LucideIcons.pencil,
                  size: 14,
                  color: AppColors.mute,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(
                  LucideIcons.trash2,
                  size: 14,
                  color: Color(0xFF6B3B3B),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
