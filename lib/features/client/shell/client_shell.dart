import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/booking_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/booking.dart";
import "../../../data/models/client_info.dart";
import "../../../data/models/tour_step.dart";
import "../../../data/providers/client_providers.dart";
import "../badges/badge_gallery_screen.dart";
import "../booking/advanced_booking_screen.dart";
import "../booking/booking_screen.dart";
import "../booking/day_detail_screen.dart";
import "../challenges/challenges_screen.dart";
import "../chat/chat_screen.dart";
import "../dashboard/client_dashboard_screen.dart";
import "../drawer_screens/habit_tracker_screen.dart";
import "../drawer_screens/history_screen.dart";
import "../drawer_screens/membership_hub_screen.dart";
import "../drawer_screens/profile_settings_screen.dart";
import "../drawer_screens/signatures_screen.dart";
import "../intake/intake_area_screen.dart";
import "../log_progress/log_progress_screen.dart";
import "../plans/nutrition_tab.dart";
import "../plans/plans_screen.dart";
import "../rewards/rewards_screen.dart";
import "../squad/squad_dashboard_screen.dart";
import "client_shell_state.dart";

class _NavItem {
  const _NavItem(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

const _bottomItems = [
  _NavItem("dashboard", "Dashboard", LucideIcons.layoutDashboard),
  _NavItem("plans", "Plans", LucideIcons.clipboardList),
  _NavItem("booking", "Booking", LucideIcons.calendar),
  _NavItem("chat", "Chat", LucideIcons.messageSquare),
];

const _drawerItems = [
  _NavItem("progress", "Log Progress", LucideIcons.barChart2),
  _NavItem("plans", "Workout Plan", LucideIcons.clipboardList),
  _NavItem("nutrition", "Nutrition Plan", LucideIcons.apple),
  _NavItem("habits", "Habit Tracker", LucideIcons.flame),
  _NavItem("history", "History", LucideIcons.history),
  _NavItem("forms", "Assessments", LucideIcons.fileText),
  _NavItem("rewards", "Rewards", LucideIcons.gift),
  _NavItem("badges", "Merit Badges", LucideIcons.award),
  _NavItem("challenges", "Challenges", LucideIcons.trophy),
  _NavItem("squad", "My Squad", LucideIcons.users2),
  _NavItem("memberships", "Membership Hub", LucideIcons.creditCard),
  _NavItem("signatures", "Signatures", LucideIcons.fileSignature),
  _NavItem("settings", "Profile Settings", LucideIcons.settings2),
];

const _titles = {
  "dashboard": "Dashboard",
  "plans": "Plans",
  "booking": "Booking",
  "day": "Booking",
  "advancedBooking": "Advanced Booking",
  "chat": "Chat",
  "memberships": "Membership Hub",
  "nutrition": "Nutrition Plan",
  "progress": "Log Progress",
  "habits": "Habit Tracker",
  "challenges": "Challenges",
  "rewards": "Rewards",
  "badges": "Merit Badges",
  "forms": "Assessments",
  "history": "History",
  "signatures": "Signatures",
  "squad": "My Squad",
  "settings": "Profile Settings",
};

/// Mirrors ClientShell.jsx: fixed top bar + hamburger drawer + fixed bottom
/// nav wrapping a screen-keyed content area. Uses Scaffold's own drawer /
/// bottomNavigationBar slots (rather than a hand-rolled Stack overlay) so
/// sizing/safe-area/z-order are all handled by the framework.
class ClientShell extends ConsumerStatefulWidget {
  const ClientShell({super.key});

  @override
  ConsumerState<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends ConsumerState<ClientShell> {
  OverlayEntry? _dashboardTourEntry;
  // Closes the drawer directly (bypassing Navigator.pop) so it doesn't get
  // swallowed by the PopScope below, which intercepts pop attempts whenever
  // canPop is false to run its own back-history logic instead.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Mirrors ClientShell.jsx's `screen === "dashboard" && !drawer &&
  /// !client.tourSeen?.dashboard` — a plain declarative render tied to
  /// `screen`, so (unlike the drawer tour, which only ever gets one chance
  /// per Drawer open) it reappears every time the client lands back on the
  /// dashboard until they actually Skip/finish it.
  void _syncDashboardTour(String screen, bool tourSeenDashboard) {
    final shouldShow = screen == "dashboard" && !tourSeenDashboard;
    if (shouldShow && _dashboardTourEntry == null) {
      final entry = OverlayEntry(
        builder: (ctx) => CoachmarkOverlay(
          steps: kDashboardTourSteps,
          keys: kDashboardTourKeys,
          onDone: _finishDashboardTour,
        ),
      );
      _dashboardTourEntry = entry;
      Overlay.of(context, rootOverlay: true).insert(entry);
    } else if (!shouldShow && _dashboardTourEntry != null) {
      _dashboardTourEntry!.remove();
      _dashboardTourEntry = null;
    }
  }

  void _finishDashboardTour() {
    _dashboardTourEntry?.remove();
    _dashboardTourEntry = null;
    final id = ref.read(clientInfoProvider).id;
    ref
        .read(clientRecordProvider.notifier)
        .update((r) => r.copyWith(tourSeenDashboard: true));
    SupabaseService.updateClientTourSeen(
      id,
      dashboard: true,
    ).catchError((Object _) {});
  }

  @override
  void dispose() {
    _dashboardTourEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = ref.watch(clientScreenProvider);
    final info = ref.watch(clientInfoProvider);
    final client = ref.watch(clientRecordProvider);
    final bookings = ref.watch(clientBookingsProvider);
    final earnedBadges = ref.watch(earnedBadgesProvider);
    final plan = ref
        .watch(membershipPlansProvider.notifier)
        .byId(info.membershipPlanId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDashboardTour(screen, client.tourSeenDashboard);
    });

    void go(String key) {
      ref.read(clientScreenProvider.notifier).go(key);
      _scaffoldKey.currentState?.closeDrawer();
    }

    // Plain nav into Booking (bottom bar / menu) — no stale target left over
    // from a previous calendar-pick or reschedule.
    void goBooking() {
      ref.read(pendingBookingTargetProvider.notifier).set(null);
      go("booking");
    }

    void startReschedule(Booking b) {
      ref
          .read(pendingBookingTargetProvider.notifier)
          .set(BookingTarget(initialDate: b.date, reschedule: b));
      go("booking");
    }

    // Tapping a calendar date — mirrors the dot shown on WorkoutCalendar
    // (calendarDayStatus is the shared source of truth for both, so the dot
    // and the tap behavior never disagree): a date WITH a dot (checked-in,
    // unmarked past booking, or upcoming booking) opens the day-detail
    // screen. A date with NO dot — including one whose only booking was a
    // no-show/early-cancel/late-cancel — goes to the booking flow if it's
    // today or later, or does nothing at all if it's already in the past.
    void pickCalendarDate(String date) {
      final status = calendarDayStatus(client, info, bookings, date);
      if (status != null) {
        ref.read(pendingDayDetailDateProvider.notifier).set(date);
        go("day");
      } else if (date.compareTo(isoToday()) >= 0) {
        ref
            .read(pendingBookingTargetProvider.notifier)
            .set(BookingTarget(initialDate: date));
        go("booking");
      }
    }

    return PopScope(
      canPop: screen == "dashboard",
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ref.read(clientScreenProvider.notifier).goBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColors.bg,
        drawer: _ClientDrawer(info: info, screen: screen, onGo: go),
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // Top bar
                  Container(
                    decoration: const BoxDecoration(
                      color: AppColors.bg,
                      border: Border(bottom: BorderSide(color: AppColors.line)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Builder(
                            key: kDashboardTourKeys["dash-hamburger"],
                            builder: (context) => IconButton(
                              onPressed: () =>
                                  Scaffold.of(context).openDrawer(),
                              icon: const Icon(
                                LucideIcons.menu,
                                size: 22,
                                color: AppColors.txt,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _titles[screen] ?? "",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          Avatar(
                            src: info.photo,
                            name: info.name,
                            size: 30,
                            active: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Content
                  Expanded(
                    child: switch (screen) {
                      "dashboard" => ClientDashboardScreen(
                        client: client,
                        info: info,
                        plan: plan,
                        bookings: bookings,
                        onGoBooking: goBooking,
                        onLogWorkout: () => go("plans"),
                        onPickDate: pickCalendarDate,
                        onGoHabits: () => go("habits"),
                        earnedBadges: earnedBadges,
                        onGoBadges: () => go("badges"),
                        onGoToForm: (formKey) {
                          ref
                              .read(pendingIntakeFormKeyProvider.notifier)
                              .set(formKey);
                          go("forms");
                        },
                      ),
                      "chat" => const ChatScreen(),
                      "plans" => const PlansScreen(),
                      "booking" => BookingScreen(
                        onGoMemberships: () => go("memberships"),
                        initialDate: ref
                            .watch(pendingBookingTargetProvider)
                            ?.initialDate,
                        initialReschedule: ref
                            .watch(pendingBookingTargetProvider)
                            ?.reschedule,
                      ),
                      "day" => DayDetailScreen(
                        date:
                            ref.watch(pendingDayDetailDateProvider) ??
                            isoToday(),
                        onBack: () => go("dashboard"),
                        onReschedule: startReschedule,
                        onGoPlans: () => go("plans"),
                      ),
                      "advancedBooking" => AdvancedBookingScreen(
                        onDone: () => go("booking"),
                      ),
                      "nutrition" => const NutritionTab(),
                      "habits" => const HabitTrackerScreen(),
                      "history" => const HistoryScreen(),
                      "signatures" => const SignaturesScreen(),
                      "memberships" => const MembershipHubScreen(),
                      "challenges" => const ChallengesScreen(),
                      "rewards" => RewardsScreen(
                        clientId: info.id,
                        onOpenBadges: () => go("badges"),
                      ),
                      "badges" => BadgeGalleryScreen(clientId: info.id),
                      "settings" => const ProfileSettingsScreen(),
                      "squad" => const SquadDashboardScreen(),
                      "forms" => IntakeAreaScreen(
                        profileId: info.id,
                        client: client,
                        who: "client",
                        onSaved: (key, record) => ref
                            .read(clientRecordProvider.notifier)
                            .update(
                              (r) => r.copyWith(
                                intake: {...r.intake, key: record},
                              ),
                            ),
                      ),
                      "progress" ||
                      "photos" ||
                      "measurements" => const LogProgressScreen(),
                      _ => PlaceholderScreen(title: _titles[screen] ?? screen),
                    },
                  ),
                ],
              ),
            ),
            // Advanced Booking — pinned above the bottom bar, Booking tab only.
            // Scaffold already sizes `body` to exclude bottomNavigationBar, so
            // bottom: 8 here lands just above it, no extra offset needed.
            if (screen == "booking")
              Positioned(
                left: 16,
                right: 16,
                bottom: 8,
                child: BtnGold(
                  full: true,
                  onPressed: () {
                    ref.read(pendingBookingTargetProvider.notifier).set(null);
                    go("advancedBooking");
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.calendar, size: 15, color: Colors.white),
                      SizedBox(width: 8),
                      Text("Advanced Booking"),
                    ],
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.bottomBarBg,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 58,
              child: Row(
                children: _bottomItems.map((item) {
                  final on = screen == item.key;
                  return Expanded(
                    key: kDashboardTourKeys["dash-nav-${item.key}"],
                    child: InkWell(
                      onTap: item.key == "booking"
                          ? goBooking
                          : () => go(item.key),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 9, bottom: 11),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              item.icon,
                              size: 21,
                              color: on ? AppColors.gold : AppColors.mute,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: on ? AppColors.gold : AppColors.mute,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientDrawer extends ConsumerStatefulWidget {
  const _ClientDrawer({
    required this.info,
    required this.screen,
    required this.onGo,
  });

  final ClientInfo info;
  final String screen;
  final void Function(String) onGo;

  @override
  ConsumerState<_ClientDrawer> createState() => _ClientDrawerState();
}

class _ClientDrawerState extends ConsumerState<_ClientDrawer> {
  OverlayEntry? _tourEntry;

  @override
  void initState() {
    super.initState();
    // Mirrors ClientShell.jsx's `drawer && !client.tourSeen?.drawer` — the
    // Drawer route only exists while open, so (unlike the dashboard tour)
    // this only ever gets one chance to show per open: inserted here on
    // mount, removed in dispose() whichever way the Drawer closes (Skip/
    // Got it, swipe-to-dismiss, tapping outside, or the back button).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !ref.read(clientRecordProvider).tourSeenDrawer)
        _showTour();
    });
  }

  void _showTour() {
    final entry = OverlayEntry(
      builder: (ctx) => CoachmarkOverlay(
        steps: kDrawerTourSteps,
        keys: kDrawerTourKeys,
        onDone: _finishTour,
      ),
    );
    _tourEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  void _finishTour() {
    _tourEntry?.remove();
    _tourEntry = null;
    ref
        .read(clientRecordProvider.notifier)
        .update((r) => r.copyWith(tourSeenDrawer: true));
    SupabaseService.updateClientTourSeen(
      widget.info.id,
      drawer: true,
    ).catchError((Object _) {});
  }

  @override
  void dispose() {
    _tourEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final screen = widget.screen;
    final onGo = widget.onGo;
    return Drawer(
      backgroundColor: AppColors.drawerBg,
      width: 270,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset("assets/images/logo.png", height: 24),
              const SizedBox(height: 14),
              Row(
                children: [
                  Avatar(
                    src: info.photo,
                    name: info.name,
                    size: 40,
                    active: true,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          info.city ?? "",
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.mute,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Scaffold.of(context).closeDrawer(),
                    icon: const Icon(
                      LucideIcons.x,
                      size: 18,
                      color: AppColors.mute,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 16, bottom: 12),
                child: Divider(color: AppColors.line, height: 1),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: _drawerItems.map((item) {
                    final on = screen == item.key;
                    return InkWell(
                      key: kDrawerTourKeys["drawer-${item.key}"],
                      onTap: () => onGo(item.key),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: on
                              ? AppColors.gold.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item.icon,
                              size: 18,
                              color: on ? AppColors.gold : AppColors.mute,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: on ? AppColors.gold : AppColors.txt,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(color: AppColors.line, height: 1),
              InkWell(
                onTap: () {
                  SupabaseService.signOut();
                  ref.read(clientSignedInProvider.notifier).signOut();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.lock,
                        size: 16,
                        color: AppColors.errorText,
                      ),
                      SizedBox(width: 12),
                      Text(
                        "Sign out",
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.errorText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
