import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/habit_utils.dart";
import "../../../core/utils/onboarding_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/client_record.dart";
import "../../../data/models/earned_badge.dart";
import "../../../data/models/membership_plan.dart";
import "sessions_remaining_badge.dart";
import "workout_calendar.dart";

/// Mirrors ClientDashboard.jsx — the client's home tab.
class ClientDashboardScreen extends StatefulWidget {
  const ClientDashboardScreen({
    super.key,
    required this.client,
    required this.info,
    required this.plan,
    required this.bookings,
    required this.onGoBooking,
    required this.onLogWorkout,
    required this.onPickDate,
    required this.onGoHabits,
    required this.earnedBadges,
    required this.onGoBadges,
    required this.onGoToForm,
  });

  final ClientRecord client;
  final ClientInfo info;
  final MembershipPlan? plan;
  final List<Booking> bookings;
  final VoidCallback onGoBooking;
  final VoidCallback onLogWorkout;
  final ValueChanged<String> onPickDate;
  final VoidCallback onGoHabits;
  final List<EarnedBadge> earnedBadges;
  final VoidCallback onGoBadges;

  /// Opens the Assessments screen straight into one form — takes the
  /// assessment key ("personalTraining" | "nutritional").
  final ValueChanged<String> onGoToForm;

  @override
  State<ClientDashboardScreen> createState() => _ClientDashboardScreenState();
}

class _ClientDashboardScreenState extends State<ClientDashboardScreen> {
  bool _skipOnboarding = false;

  ClientRecord get client => widget.client;
  ClientInfo get info => widget.info;
  List<Booking> get bookings => widget.bookings;

  Booking? get _next {
    final todayStr = isoToday();
    final upcoming = bookings.where((b) => b.clientId == info.id && b.date.compareTo(todayStr) >= 0).toList()
      ..sort((a, b) => (a.date + a.slot.toString().padLeft(4, '0'))
          .compareTo(b.date + b.slot.toString().padLeft(4, '0')));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  bool get _loggedToday => client.loggedOn(isoToday());
  bool get _hasSessionToday => bookings.any((b) => b.clientId == info.id && b.date == isoToday());

  @override
  Widget build(BuildContext context) {
    final firstName = info.name.split(" ").first;
    final habits = getClientHabits(client);
    final todayLog = getHabitLog(client, isoToday());
    final done = habits.where((h) => todayLog.checked[h.id] == true).length;
    final showHabitTile = habits.isNotEmpty && done < habits.length;

    final onboardingAlerts = getOnboardingAlerts(client, bookings, info.id, widget.plan);
    final assessmentBooked = onboardingStepDone(client, bookings, info.id, "physicalAssessmentBooked");
    final showOnboarding = (onboardingAlerts.isNotEmpty || !assessmentBooked) && !_skipOnboarding;

    // Staggers each top-level section's entrance by 45ms, played once when
    // the Dashboard first mounts.
    var stagger = 0;
    Widget stag(Widget child) {
      final delay = Duration(milliseconds: 45 * stagger);
      stagger++;
      return FadeSlideIn(delay: delay, child: child);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          stag(Text(
            "Hey $firstName, it's ${_hasSessionToday ? "lifting day!" : "a rest day"}",
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          )),
          const SizedBox(height: 2),
          stag(Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(dayLabel(isoToday()), style: const TextStyle(fontSize: 13, color: AppColors.mute)),
          )),

          if (widget.earnedBadges.any((b) => b.clientId == info.id && b.isActive)) ...[
            stag(MeritBadgeRow(clientId: info.id, earnedBadges: widget.earnedBadges)),
            const SizedBox(height: 2),
          ],
          stag(TextButton(
            onPressed: widget.onGoBadges,
            style: TextButton.styleFrom(foregroundColor: AppColors.gold, padding: EdgeInsets.zero, minimumSize: Size.zero, alignment: Alignment.centerLeft),
            child: const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text("See all Merit Badges →", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          )),

          if (showOnboarding)
            stag(_OnboardingSection(
              alerts: onboardingAlerts,
              showIntakeButtons: !assessmentBooked,
              onBookIntake: widget.onGoBooking,
              onGoToForm: widget.onGoToForm,
              onGoBookAssessment: widget.onGoBooking,
              onSkip: () => setState(() => _skipOnboarding = true),
            )),

          stag(SessionsRemainingBadge(info: info, bookings: bookings)),

          if (showHabitTile)
            stag(AppCard(
              borderColor: AppColors.goldDim,
              onTap: widget.onGoHabits,
              child: Row(
                children: [
                  const Text("\u{1F525}", style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Habits — $done/${habits.length} done today",
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(height: 1),
                        Text(
                          "${habitStreak(client)} day streak · ${((done / habits.length) * 100).round()}% today",
                          style: const TextStyle(fontSize: 11, color: AppColors.mute),
                        ),
                      ],
                    ),
                  ),
                  const Icon(LucideIcons.chevronRight, size: 15, color: AppColors.mute),
                ],
              ),
            )),

          stag(WorkoutCalendar(client: client, info: info, bookings: bookings, onPickDate: widget.onPickDate)),

          const SizedBox(height: 4),
          stag(AppCard(
            borderColor: AppColors.goldDim,
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            child: SizedBox(
              width: double.infinity,
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "NEXT SESSION",
                  style: TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700, letterSpacing: 1),
                ),
                const SizedBox(height: 8),
                if (_next != null) ...[
                  Text(
                    "${dayLabel(_next!.date)} · ${fmtSlot(_next!.slot)}",
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  if (_next!.locationName != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(LucideIcons.mapPin, size: 12, color: AppColors.gold),
                        const SizedBox(width: 4),
                        Text(_next!.locationName!, style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: widget.onGoBooking,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.gold,
                      side: const BorderSide(color: AppColors.line),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text("Manage sessions", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ] else ...[
                  const Text("No upcoming sessions booked.", style: TextStyle(fontSize: 13, color: AppColors.mute)),
                  const SizedBox(height: 10),
                  BtnGold(onPressed: widget.onGoBooking, child: const Text("Book a session", style: TextStyle(fontSize: 13))),
                ],
              ],
              ),
            ),
          )),

          stag(AppCard(
            onTap: widget.onLogWorkout,
            child: Row(
              children: [
                Icon(LucideIcons.check, size: 20, color: _loggedToday ? AppColors.gold : AppColors.mute),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Today's workout", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      Text(
                        _loggedToday ? "Logged — tap to review or edit" : "Tap to log your session",
                        style: const TextStyle(fontSize: 12, color: AppColors.mute),
                      ),
                    ],
                  ),
                ),
                const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mute),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

/// Mirrors the "Complete your onboarding" block in ClientDashboard.jsx: the
/// two free-intake booking buttons (shown until the client's booked one),
/// any still-incomplete intake-form alert cards, and — only for clients on a
/// session-based plan — the Free Physical Assessment reminder card.
class _OnboardingSection extends StatelessWidget {
  const _OnboardingSection({
    required this.alerts,
    required this.showIntakeButtons,
    required this.onBookIntake,
    required this.onGoToForm,
    required this.onGoBookAssessment,
    required this.onSkip,
  });

  final List<OnboardingStep> alerts;
  final bool showIntakeButtons;
  final VoidCallback onBookIntake;
  final ValueChanged<String> onGoToForm;
  final VoidCallback onGoBookAssessment;
  final VoidCallback onSkip;

  static const _formKeys = {"personalizedIntake": "personalTraining", "nutritionIntake": "nutritional"};

  @override
  Widget build(BuildContext context) {
    final intakeSteps = alerts.where((s) => s.key == "personalizedIntake" || s.key == "nutritionIntake").toList();
    final assessmentStep = alerts.where((s) => s.key == "physicalAssessmentBooked").toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "COMPLETE YOUR ONBOARDING",
            style: TextStyle(fontSize: 12, color: AppColors.mute, fontWeight: FontWeight.w600, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          if (showIntakeButtons) ...[
            Row(
              children: [
                Expanded(child: _IntakeButton(icon: LucideIcons.phone, label: "Book Intake Call", onTap: onBookIntake)),
                const SizedBox(width: 8),
                Expanded(child: _IntakeButton(icon: LucideIcons.mapPin, label: "Book Intake In-Person", onTap: onBookIntake)),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 8),
              child: Text(
                "Or fill out your intake forms below to complete on your own.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.mute, height: 1.5, fontStyle: FontStyle.italic),
              ),
            ),
          ],
          for (final step in intakeSteps)
            _OnboardingStepCard(step: step, onTap: () => onGoToForm(_formKeys[step.key]!)),
          for (final step in assessmentStep)
            _OnboardingStepCard(step: step, onTap: onGoBookAssessment),
          TextButton(
            onPressed: onSkip,
            style: TextButton.styleFrom(foregroundColor: AppColors.mute, padding: EdgeInsets.zero, minimumSize: Size.zero, alignment: Alignment.centerLeft),
            child: const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text("Skip for now", style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntakeButton extends StatelessWidget {
  const _IntakeButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.gold.withValues(alpha: 0.12),
        foregroundColor: AppColors.gold,
        side: const BorderSide(color: AppColors.goldDim),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingStepCard extends StatelessWidget {
  const _OnboardingStepCard({required this.step, required this.onTap});
  final OnboardingStep step;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      onTap: onTap,
      child: Row(
        children: [
          Icon(step.icon, size: 17, color: AppColors.mute),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.txt)),
                const SizedBox(height: 1),
                Text(step.sub, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
              ],
            ),
          ),
          const SizedBox(
            width: 7,
            height: 7,
            child: DecoratedBox(decoration: BoxDecoration(color: AppColors.danger, shape: BoxShape.circle)),
          ),
        ],
      ),
    );
  }
}
