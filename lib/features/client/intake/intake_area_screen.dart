import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/intake_forms.dart";
import "../../../data/models/intake_schema.dart";
import "../../../data/providers/client_providers.dart";
import "form_filler_screen.dart";

const _groupIcons = {"training": LucideIcons.clipboardCheck, "nutrition": LucideIcons.apple};
const _assessmentIcons = {"personalTraining": LucideIcons.clipboardList, "physical": LucideIcons.dumbbell, "nutritional": LucideIcons.apple};

/// Mirrors IntakeArea.jsx (client side) — lists every client-fillable
/// assessment grouped by form, showing OPEN/COMPLETE status, drilling into
/// FormFillerScreen. The Physical Assessment is coach-conducted (a full
/// movement-screening tool, out of scope here) so it's shown as
/// informational only, not opened as an editable form.
class IntakeAreaScreen extends ConsumerStatefulWidget {
  const IntakeAreaScreen({super.key, this.initialOpenKey});

  final String? initialOpenKey;

  @override
  ConsumerState<IntakeAreaScreen> createState() => _IntakeAreaScreenState();
}

class _IntakeAreaScreenState extends ConsumerState<IntakeAreaScreen> {
  AssessmentDef? _open;

  @override
  void initState() {
    super.initState();
    if (widget.initialOpenKey != null) {
      for (final group in kIntakeForms) {
        for (final a in group.assessments) {
          if (a.key == widget.initialOpenKey) _open = a;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(clientRecordProvider);

    if (_open != null) {
      final a = _open!;
      if (a.physical) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BackBar(onBack: () => setState(() => _open = null)),
              const SizedBox(height: 10),
              const SectionLabel("Free Physical Assessment Session"),
              const HintBox(
                text: "This is a hands-on movement assessment conducted by your coach during your first training "
                    "session — there's nothing to fill out here yourself. Book it from the Dashboard or Booking tab.",
              ),
            ],
          ),
        );
      }
      return FormFillerScreen(assessmentKey: a.key, schema: a.schema!, onBack: () => setState(() => _open = null));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: kIntakeForms.map((group) {
          final visible = group.assessments.where((a) => a.clientCanFill || a.physical).toList();
          if (visible.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_groupIcons[group.key] ?? LucideIcons.clipboardList, size: 17, color: AppColors.gold),
                    const SizedBox(width: 8),
                    Text(group.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 10),
                ...visible.map((a) {
                  final rec = client.intake[a.key];
                  final done = rec?.completed ?? false;
                  return AppCard(
                    padding: EdgeInsets.zero,
                    onTap: () => setState(() => _open = a),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(_assessmentIcons[a.key] ?? LucideIcons.clipboardList, size: 16, color: AppColors.mute),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text("Conducted by: ${a.by}", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                                ),
                                if (done && rec?.at != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                      "Completed by ${rec!.by} · ${rec.at}",
                                      style: const TextStyle(fontSize: 11, color: AppColors.gold),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: done ? AppColors.gold.withValues(alpha: 0.12) : Colors.transparent,
                              border: Border.all(color: done ? AppColors.goldDim : AppColors.line),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              done ? "COMPLETE" : "OPEN",
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: done ? AppColors.gold : AppColors.mute),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mute),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
