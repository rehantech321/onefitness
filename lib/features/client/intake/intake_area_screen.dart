import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/intake_forms.dart";
import "../../../data/models/client_record.dart";
import "../../../data/models/intake_schema.dart";
import "../shell/client_shell_state.dart";
import "form_filler_screen.dart";

const _groupIcons = {
  "training": LucideIcons.clipboardCheck,
  "nutrition": LucideIcons.apple,
};
const _assessmentIcons = {
  "personalTraining": LucideIcons.clipboardList,
  "physical": LucideIcons.dumbbell,
  "nutritional": LucideIcons.apple,
};

/// Mirrors IntakeArea.jsx — lists every client-fillable assessment grouped
/// by form, showing OPEN/COMPLETE status, drilling into FormFillerScreen.
/// The Physical Assessment is coach-conducted (a full movement-screening
/// tool, out of scope here) so it's shown as informational only, not opened
/// as an editable form. Reused for both the client's own "Assessments" drawer
/// screen (`who: "client"`, via client_shell.dart) and a coach viewing/editing
/// a client's intake from their Profile tab (`who: "trainer"`, via IntakeTab)
/// — see FormFillerScreen's own doc comment for how `who`/[onSaved] route.
class IntakeAreaScreen extends ConsumerStatefulWidget {
  const IntakeAreaScreen({
    super.key,
    this.initialOpenKey,
    required this.profileId,
    required this.client,
    required this.who,
    required this.onSaved,
  });

  final String? initialOpenKey;
  final String profileId;
  final ClientRecord client;
  final String who; // "client" | "trainer"
  final void Function(String assessmentKey, IntakeRecord) onSaved;

  @override
  ConsumerState<IntakeAreaScreen> createState() => _IntakeAreaScreenState();
}

class _IntakeAreaScreenState extends ConsumerState<IntakeAreaScreen> {
  AssessmentDef? _open;

  @override
  void initState() {
    super.initState();
    // Only the client's own self-serve entry point deep-links into a
    // specific form this way (a dashboard onboarding-step tap) — a coach
    // reaching this via IntakeTab always starts on the plain list.
    final pending = widget.who == "client"
        ? ref.read(pendingIntakeFormKeyProvider)
        : null;
    if (pending != null)
      ref.read(pendingIntakeFormKeyProvider.notifier).set(null);
    final key = pending ?? widget.initialOpenKey;
    if (key != null) {
      for (final group in kIntakeForms) {
        for (final a in group.assessments) {
          if (a.key == key) _open = a;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;

    if (_open != null) {
      final a = _open!;
      if (a.physical) {
        return LocalBackScope(
          isOpen: true,
          onBack: () => setState(() => _open = null),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BackBar(onBack: () => setState(() => _open = null)),
                const SizedBox(height: 10),
                const SectionLabel("Free Physical Assessment Session"),
                const HintBox(
                  text:
                      "This is a hands-on movement assessment conducted by your coach during your first training "
                      "session — there's nothing to fill out here yourself. Book it from the Dashboard or Booking tab.",
                ),
              ],
            ),
          ),
        );
      }
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() => _open = null),
        child: FormFillerScreen(
          assessmentKey: a.key,
          schema: a.schema!,
          onBack: () => setState(() => _open = null),
          profileId: widget.profileId,
          client: client,
          who: widget.who,
          onSaved: (record) => widget.onSaved(a.key, record),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: kIntakeForms.map((group) {
          final visible = group.assessments
              .where((a) => a.clientCanFill || a.physical)
              .toList();
          if (visible.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _groupIcons[group.key] ?? LucideIcons.clipboardList,
                      size: 17,
                      color: AppColors.gold,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      group.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
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
                          Icon(
                            _assessmentIcons[a.key] ??
                                LucideIcons.clipboardList,
                            size: 16,
                            color: AppColors.mute,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    "Conducted by: ${a.by}",
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.mute,
                                    ),
                                  ),
                                ),
                                if (done && rec?.at != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                      "Completed by ${rec!.by} · ${rec.at}",
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.gold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: done
                                  ? AppColors.gold.withValues(alpha: 0.12)
                                  : Colors.transparent,
                              border: Border.all(
                                color: done
                                    ? AppColors.goldDim
                                    : AppColors.line,
                              ),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              done ? "COMPLETE" : "OPEN",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: done ? AppColors.gold : AppColors.mute,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            LucideIcons.chevronRight,
                            size: 16,
                            color: AppColors.mute,
                          ),
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
