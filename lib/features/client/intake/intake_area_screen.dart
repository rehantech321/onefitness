import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/intake_entitlements.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/intake_forms.dart";
import "../../../data/providers/client_providers.dart";
import "../../../data/providers/trainer_providers.dart";
import "../../../data/models/client_record.dart";
import "../../../data/models/intake_schema.dart";
import "../shell/client_shell_state.dart";
import "form_filler_screen.dart";

const _groupIcons = {
  "training": LucideIcons.clipboardCheck,
  "nutrition": LucideIcons.apple,
};
/// Why a given form is locked, in terms of what would unlock it — more use to
/// a client than a bare "locked", since the answer differs per form.
String _unlockHint(String assessmentKey) => switch (assessmentKey) {
  "personalTraining" => "Unlocks with a membership, package, or personalized program.",
  "nutritional" => "Unlocks with a membership, package, personalized program, or nutrition program.",
  "physical" => "Included with a membership or package.",
  _ => "Unlocks with a purchase.",
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

    // Computed before the open-form branch so a deep link (the dashboard's
    // onboarding prompt sets pendingIntakeFormKeyProvider, which initState
    // turns straight into an open form) can't route around the lock the list
    // below applies.
    final isClientView = widget.who == "client";
    final info = isClientView
        ? ref.watch(clientInfoProvider)
        : ref.watch(trainerRosterProvider).where((c) => c.id == widget.profileId).firstOrNull;
    final entitlements = info == null
        ? IntakeEntitlements.none
        : computeIntakeEntitlements(info: info, allPlans: ref.watch(membershipPlansProvider));

    if (_open != null && isClientView && !entitlements.allows(_open!.key)) {
      // Shouldn't be reachable through the UI, but a stale deep link (or a
      // purchase that lapsed between tap and build) would otherwise drop them
      // into a form they're not entitled to fill in.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _open = null);
      });
      return const SizedBox.shrink();
    }

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
        children: [
          // Nothing bought yet — the forms below are all locked, so say why
          // once at the top and hand them the way out, rather than leaving
          // them to tap a locked row to find out.
          if (isClientView && !entitlements.hasAnyPurchase)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: AppCard(
                borderColor: AppColors.goldDim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Choose a plan to get started",
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Your intake forms unlock once you have a membership, package or program. What you buy decides which "
                      "forms you fill in — a membership or package opens all of them, a personalized program opens training "
                      "and nutrition, and a nutrition program opens nutrition.",
                      style: TextStyle(fontSize: 11.5, color: AppColors.mute, height: 1.45),
                    ),
                    const SizedBox(height: 12),
                    BtnGold(
                      full: true,
                      onPressed: () => ref.read(clientScreenProvider.notifier).go("memberships"),
                      child: const Text("Go to Membership Hub"),
                    ),
                  ],
                ),
              ),
            ),
          ...kIntakeForms.map((group) {
          final visible = group.assessments
              .where((a) => a.clientCanFill || a.physical)
              // The coach-run physical assessment comes with a membership or
              // package; with only a program (or nothing) there's no session
              // to conduct, so it isn't part of this client's intake at all.
              .where((a) => !a.physical || entitlements.physical)
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
                  // Locked forms stay listed — seeing what's on offer is the
                  // point — but a client can't open one until a purchase
                  // entitles them. A coach is never blocked: they may need to
                  // record answers for a client mid-signup, so on their side
                  // the lock is shown as information only.
                  final locked = !entitlements.allows(a.key);
                  final blocked = locked && isClientView;
                  return AppCard(
                    padding: EdgeInsets.zero,
                    // A locked row sends them where the lock is actually
                    // lifted, rather than being inert — tapping something
                    // and getting nothing back reads as a broken screen,
                    // and the answer ("buy a plan") is one tap away.
                    onTap: blocked
                        ? () => ref.read(clientScreenProvider.notifier).go("memberships")
                        : () => setState(() => _open = a),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(
                            locked
                                ? LucideIcons.lock
                                : (_assessmentIcons[a.key] ?? LucideIcons.clipboardList),
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
                                if (locked)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                      isClientView
                                          // Tapping goes to the Membership
                                          // Hub, so say so — otherwise the
                                          // row looks like a dead end.
                                          ? "${_unlockHint(a.key)} Tap to choose a plan."
                                          : "Not unlocked by this client's purchases yet.",
                                      style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.35),
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
                              locked ? "LOCKED" : (done ? "COMPLETE" : "OPEN"),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: done && !locked ? AppColors.gold : AppColors.mute,
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
        }),
        ],
      ),
    );
  }
}
