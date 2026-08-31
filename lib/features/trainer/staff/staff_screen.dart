import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/domain_labels.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/availability_block.dart";
import "../../../data/models/trainer.dart";
import "../../../data/providers/client_providers.dart";
import "trainer_edit_form.dart";

/// Mirrors StaffManager.jsx (owner-only) — trainer roster with add/edit
/// in place of a modal.
class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  Trainer? _editing;
  bool _creating = false;

  @override
  Widget build(BuildContext context) {
    final trainers = ref.watch(trainersProvider);

    if (_editing != null || _creating) {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() {
          _editing = null;
          _creating = false;
        }),
        child: TrainerEditForm(
          initial: _editing,
          isOwnerEditing: true,
          onCancel: () => setState(() {
            _editing = null;
            _creating = false;
          }),
          onSave: (t, password) async {
            String realId = t.id;
            try {
              if (_editing != null) {
                await SupabaseService.updateTrainerRow(
                  t.id,
                  name: t.name,
                  email: t.email,
                  phone: t.phone,
                  photo: t.photo,
                  disciplines: t.disciplines,
                  sessionTypes: t.sessionTypes,
                  locations: t.locations,
                  bio: t.bio ?? "",
                  beforeAfters: t.beforeAfters,
                  availability: t.availability,
                  commissionRate: t.commissionRate,
                  payoutMode: t.payoutMode,
                  payoutRateCents: t.payoutRateCents,
                  referralCommissionPercent: t.referralCommissionPercent,
                  unavailability: t.unavailability,
                );
              } else {
                // Brand-new trainer — real Supabase Auth account, created on
                // the owner's behalf without disturbing the owner's own
                // session (see signUpCoachOnBehalf's own doc comment).
                realId = await SupabaseService.signUpCoachOnBehalf(
                  email: t.email ?? "",
                  password: password ?? "",
                  name: t.name,
                  phone: t.phone,
                  photo: t.photo,
                  disciplines: t.disciplines,
                  sessionTypes: t.sessionTypes,
                  locations: t.locations,
                  bio: t.bio,
                  beforeAfters: t.beforeAfters,
                  availability: t.availability,
                  commissionRate: t.commissionRate,
                  coachCode: t.coachCode,
                  payoutMode: t.payoutMode,
                  payoutRateCents: t.payoutRateCents,
                  referralCommissionPercent: t.referralCommissionPercent,
                  unavailability: t.unavailability,
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _editing != null
                          ? "Couldn't save — check your connection and try again."
                          : "Couldn't create that trainer — ${e.toString().replaceFirst('Exception: ', '').replaceFirst('AuthException: ', '')}",
                    ),
                  ),
                );
              }
              return;
            }
            ref
                .read(trainersProvider.notifier)
                .upsert(
                  realId == t.id
                      ? t
                      : Trainer(
                          id: realId,
                          name: t.name,
                          email: t.email,
                          phone: t.phone,
                          photo: t.photo,
                          disciplines: t.disciplines,
                          sessionTypes: t.sessionTypes,
                          locations: t.locations,
                          bio: t.bio,
                          beforeAfters: t.beforeAfters,
                          availability: t.availability,
                          commissionRate: t.commissionRate,
                          coachCode: t.coachCode,
                          payoutMode: t.payoutMode,
                          payoutRateCents: t.payoutRateCents,
                          referralCommissionPercent:
                              t.referralCommissionPercent,
                          unavailability: t.unavailability,
                        ),
                );
            setState(() {
              _editing = null;
              _creating = false;
            });
          },
          onDelete: _editing == null
              ? null
              : () async {
                  final id = _editing!.id;
                  try {
                    await SupabaseService.deleteTrainerRow(id);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Couldn't remove that trainer — check your connection and try again.",
                          ),
                        ),
                      );
                    }
                    return;
                  }
                  ref.read(trainersProvider.notifier).remove(id);
                  setState(() => _editing = null);
                },
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SectionLabel("Trainers (${trainers.length})"),
              TextButton.icon(
                onPressed: () => setState(() => _creating = true),
                icon: const Icon(
                  LucideIcons.plus,
                  size: 14,
                  color: AppColors.gold,
                ),
                label: const Text(
                  "Trainer",
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          ...trainers.map((t) {
            final disciplines = t.availability.map((b) => b.discipline).toSet();
            final sessionTypes = t.availability
                .map((b) => b.sessionType)
                .toSet();
            return AppCard(
              onTap: () => setState(() => _editing = t),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Avatar(name: t.name, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          t.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const Icon(
                        LucideIcons.edit3,
                        size: 15,
                        color: AppColors.mute,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      ...sessionTypes.map(
                        (s) => Tag(text: sessionTypeLabel(s), gold: true),
                      ),
                      ...disciplines.map((d) => Tag(text: disciplineLabel(d))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (t.email != null)
                    _IconLine(icon: LucideIcons.mail, text: t.email!),
                  if (t.phone != null)
                    _IconLine(icon: LucideIcons.phone, text: t.phone!),
                  if (t.locationName != null)
                    _IconLine(icon: LucideIcons.mapPin, text: t.locationName!),
                  _IconLine(
                    icon: LucideIcons.dollarSign,
                    text: _payoutSummary(t),
                  ),
                  const SizedBox(height: 8),
                  _AvailSummary(availability: t.availability),
                  if (t.coachCode != null && t.coachCode!.isNotEmpty)
                    _IconLine(
                      icon: LucideIcons.badgePercent,
                      text: "Coach Code: ${t.coachCode}",
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

String _payoutSummary(Trainer t) {
  final rate = "\$${(t.payoutRateCents / 100).toStringAsFixed(2)}";
  final unit = switch (t.payoutMode) {
    "perClient" => "client",
    "perHour" => "hour",
    _ => "session",
  };
  return "$rate/$unit";
}

const _weekdayLabels = {1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat"};

/// Mirrors FormPrimitives.jsx `AvailSummary` — a compact weekly Mon-Sat
/// slot grid per availability block (session type/discipline label, then
/// one line per working day of that block's open slots).
class _AvailSummary extends StatelessWidget {
  const _AvailSummary({required this.availability});
  final List<AvailabilityBlock> availability;

  @override
  Widget build(BuildContext context) {
    if (availability.isEmpty) {
      return const _IconLine(icon: LucideIcons.clock, text: "No availability set");
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: availability.map((b) {
        final working = _weekdayLabels.entries.where((e) => (b.byDay[e.key] ?? const []).isNotEmpty).toList();
        if (working.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(LucideIcons.clock, size: 12, color: AppColors.gold),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${sessionTypeLabel(b.sessionType)} · ${disciplineLabel(b.discipline)}",
                      style: const TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700),
                    ),
                    ...working.map((e) {
                      final slots = [...b.byDay[e.key]!]..sort();
                      return Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 12, color: AppColors.mute),
                            children: [
                              TextSpan(
                                text: "${e.value}  ",
                                style: const TextStyle(color: AppColors.txt, fontWeight: FontWeight.w700),
                              ),
                              TextSpan(text: slots.map(fmtSlotShort).join(" ")),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 12, color: AppColors.mute),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 11, color: AppColors.mute),
          ),
        ],
      ),
    );
  }
}
