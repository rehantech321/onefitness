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
import "intake_answers_screen.dart";

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

/// The same lock, said to the person it doesn't stop. Staff can open any
/// assessment regardless of what the client has bought, so their version
/// states what the lock actually means — that this isn't part of the plan the
/// client is paying for — rather than reading as a refusal.
String _staffLockNote(AssessmentDef a) => a.physical
    ? "Not included in this client's plan — there's no session to conduct until they buy a membership or package."
    : "Not included in this client's plan — you can still open it to read or record their answers.";

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

  /// Whether the open assessment is showing as an editable form rather than
  /// as the client's saved answers. Always true for the client (this is their
  /// own form to fill in) and for staff opening an assessment nobody has
  /// completed yet; staff opening a completed one start on the answers and
  /// opt into editing. Decided when the assessment opens, not re-derived each
  /// build, so that saving — which marks the record complete and rebuilds
  /// this screen — can't swap the editor out from under the coach mid-save.
  bool _editing = true;

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
      if (_open != null) _editing = _opensAsEditor(_open!);
    }
  }

  /// A deep link or a tap lands on the editor only where there is nothing to
  /// read back: see [_editing].
  bool _opensAsEditor(AssessmentDef a) =>
      widget.who == "client" || !(widget.client.intake[a.key]?.completed ?? false);

  void _openAssessment(AssessmentDef a) => setState(() {
        _open = a;
        _editing = _opensAsEditor(a);
      });

  void _closeAssessment() => setState(() {
        _open = null;
        _editing = true;
      });

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
        if (mounted) _closeAssessment();
      });
      return const SizedBox.shrink();
    }

    if (_open != null) {
      final a = _open!;
      if (a.physical) {
        return LocalBackScope(
          isOpen: true,
          onBack: _closeAssessment,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BackBar(onBack: _closeAssessment),
                const SizedBox(height: 10),
                const SectionLabel("Free Physical Assessment Session"),
                HintBox(
                  text: isClientView
                      ? "This is a hands-on movement assessment conducted by your coach during your first training "
                            "session — there's nothing to fill out here yourself. Book it from the Dashboard or Booking tab."
                      : "A hands-on movement assessment you conduct in person during the client's first training "
                            "session. There's no form behind it — record what you find in Notes or Measurements.",
                ),
              ],
            ),
          ),
        );
      }

      final record = client.intake[a.key];
      if (!_editing && record != null) {
        // Staff reading a completed intake. Backing out goes to the list;
        // "Edit answers" swaps in the form below, which backs out to here.
        return LocalBackScope(
          isOpen: true,
          onBack: _closeAssessment,
          child: IntakeAnswersScreen(
            schema: a.schema!,
            record: record,
            profileId: widget.profileId,
            assessmentKey: a.key,
            onBack: _closeAssessment,
            onEdit: () => setState(() => _editing = true),
          ),
        );
      }

      // Back from the editor returns to the answers whenever there are any to
      // return to — which, after a save, there now are: the coach sees what
      // they just recorded rather than being dropped back to the list.
      final hasAnswersBehind = !isClientView && (record?.completed ?? false);
      final leaveEditor =
          hasAnswersBehind ? () => setState(() => _editing = false) : _closeAssessment;
      return LocalBackScope(
        isOpen: true,
        onBack: leaveEditor,
        child: FormFillerScreen(
          assessmentKey: a.key,
          schema: a.schema!,
          onBack: leaveEditor,
          profileId: widget.profileId,
          client: client,
          who: widget.who,
          onSaved: (record) {
            widget.onSaved(a.key, record);
            // A client who has bought nothing has just told the gym what they
            // want out of training. Choosing a plan is the next thing they
            // came to do, so take them there rather than returning them to a
            // list of forms they've now finished.
            if (isClientView && !entitlements.hasAnyPurchase && record.completed) {
              ref.read(clientScreenProvider.notifier).go("memberships");
            }
          },
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
              // Staff still see it listed: hiding a whole assessment from the
              // person who conducts it makes their roster look inconsistent
              // from one client to the next, with nothing on screen to
              // explain why. They get it greyed out with the reason instead.
              .where((a) => !a.physical || entitlements.physical || !isClientView)
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
                        : () => _openAssessment(a),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(
                            // The padlock is for the person it actually stops.
                            // Staff can open any of these, so showing them a
                            // padlock and a LOCKED badge sends them away from
                            // a form they were free to read all along.
                            blocked
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
                                          : _staffLockNote(a),
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
                                  ? AppColors.gold
                                  : Colors.transparent,
                              border: Border.all(
                                color: done
                                    ? AppColors.goldDim
                                    : AppColors.line,
                              ),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              // Staff get the status that tells them whether
                              // there is anything to read; "LOCKED" would
                              // hide that a completed form is sitting there.
                              blocked ? "LOCKED" : (done ? "COMPLETE" : "OPEN"),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: done ? AppColors.onGold : AppColors.mute,
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
