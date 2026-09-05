import "package:flutter/widgets.dart";

/// One step of a Coachmark walkthrough — mirrors tourSteps.js's step shape
/// (a target `key` used to look up the GlobalKey of the widget to
/// spotlight, plus the tooltip's title/desc).
class TourStep {
  const TourStep(this.key, this.title, this.desc);
  final String key;
  final String title;
  final String desc;
}

/// Mirrors tourSteps.js `DASHBOARD_TOUR_STEPS` — shown once, the first time
/// a client lands on their dashboard, spotlighting the hamburger menu and
/// each bottom-nav tab.
const kDashboardTourSteps = [
  TourStep("dash-hamburger", "Menu", "Tap here any time to reach your nutrition plan, progress log, habits, challenges, and more."),
  TourStep("dash-nav-dashboard", "Dashboard", "Your home base — today's plan, upcoming sessions, and quick actions."),
  TourStep("dash-nav-plans", "Plans", "Your workout program, laid out day by day."),
  TourStep("dash-nav-booking", "Booking", "Book, reschedule, or cancel your sessions here."),
  TourStep("dash-nav-chat", "Chat", "Message your coach directly, any time."),
  TourStep("dash-nav-memberships", "Membership Hub", "Your plan, sessions remaining, and upgrade options."),
];

/// Mirrors tourSteps.js `DRAWER_TOUR_STEPS` — shown once, the first time a
/// client opens the hamburger drawer, spotlighting each menu item in order.
const kDrawerTourSteps = [
  TourStep("drawer-progress", "Log Progress", "Log your weight, photos, and measurements over time."),
  TourStep("drawer-plans", "Workout Plan", "Your full training program, day by day."),
  TourStep("drawer-nutrition", "Nutrition Plan", "Your meals and daily nutrition targets."),
  TourStep("drawer-habits", "Habit Tracker", "Check off your daily habits and build your streak."),
  TourStep("drawer-history", "History", "Every workout you've logged, all in one place."),
  TourStep("drawer-forms", "Assessments", "Fill out or review your intake and assessment forms."),
  TourStep("drawer-challenges", "Challenges", "Join gym-wide challenges and see the leaderboard."),
  TourStep("drawer-squad", "My Squad", "See your training squad and their progress."),
  TourStep("drawer-signatures", "Signatures", "View your signed agreements and waivers."),
  TourStep("drawer-settings", "Profile Settings", "Update your personal info and photo."),
];

/// GlobalKeys must be stable across rebuilds (not recreated inside build()),
/// so these live as module-level constants, one map per tour, keyed the
/// same as each TourStep.key above.
final Map<String, GlobalKey> kDashboardTourKeys = {for (final s in kDashboardTourSteps) s.key: GlobalKey()};
final Map<String, GlobalKey> kDrawerTourKeys = {for (final s in kDrawerTourSteps) s.key: GlobalKey()};
