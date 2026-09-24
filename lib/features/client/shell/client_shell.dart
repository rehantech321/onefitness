import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/booking_utils.dart";
import "../../../core/utils/date_utils.dart";
import "../../../core/utils/membership_utils.dart";
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
import "../shop/shop_screen.dart";
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
  _NavItem("memberships", "Access Hub", LucideIcons.creditCard),
];

const _drawerItems = [
  _NavItem("progress", "Log Progress", LucideIcons.barChart2),
  _NavItem("plans", "Workout Plan", LucideIcons.clipboardList),
  _NavItem("nutrition", "Nutrition Plan", LucideIcons.apple),
  _NavItem("habits", "Habit Tracker", LucideIcons.flame),
  _NavItem("history", "History", LucideIcons.history),
  _NavItem("forms", "Assessments", LucideIcons.fileText),
  _NavItem("shop", "Shop", LucideIcons.shoppingBag),
  _NavItem("rewards", "Rewards", LucideIcons.gift),
  _NavItem("badges", "Merit Badges", LucideIcons.award),
  _NavItem("challenges", "Challenges", LucideIcons.trophy),
  _NavItem("squad", "My Squad", LucideIcons.users2),
  _NavItem("signatures", "Signatures", LucideIcons.fileSignature),
  _NavItem("support", "Support", LucideIcons.phone),
  _NavItem("settings", "Profile Settings", LucideIcons.settings2),
];

const _titles = {
  "dashboard": "Dashboard",
  "plans": "Plans",
  "booking": "Booking",
  "day": "Booking",
  "advancedBooking": "Advanced Booking",
  "chat": "Chat",
  "memberships": "Access Hub",
  "nutrition": "Nutrition Plan",
  "progress": "Log Progress",
  "habits": "Habit Tracker",
  "challenges": "Challenges",
  "shop": "Shop",
  "rewards": "Rewards",
  "badges": "Merit Badges",
  "forms": "Assessments",
  "history": "History",
  "signatures": "Signatures",
  "support": "Support",
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
  Offset? _dragStart;

  // The single source of truth for "what does back mean right now" — used
  // by the top-bar back button, the swipe gesture, and system back/OS
  // edge-swipe alike, so all three always agree. Order matters: an open
  // drawer wins, then any open local sub-view (a form, a detail drilled
  // into — see local_back_stack.dart), then — only once neither applies
  // — the shell's own screen history.
  void _handleBack() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState!.closeDrawer();
      return;
    }
    final local = ref.read(localBackStackProvider.notifier).top;
    if (local != null) {
      local();
      return;
    }
    // Then the page history itself — always the page before this one,
    // whether that was a bottom tab, a menu page or Dashboard.
    final nav = ref.read(clientScreenProvider.notifier);
    if (nav.canGoBack) {
      nav.goBack();
      return;
    }
    // Nothing to go back to and not on Dashboard — a page opened cold (a
    // push notification, a deep link, a reset history). Back goes home
    // rather than doing nothing at all.
    if (ref.read(clientScreenProvider) != "dashboard") nav.go("dashboard");
  }

  @override
  void initState() {
    super.initState();
    // Each time the client area opens (a sign-in), start on Dashboard with
    // an empty history — the previous session's trail must not resurface.
    Future.microtask(() {
      if (mounted) ref.read(clientScreenProvider.notifier).reset();
    });
  }

  void _onPointerDown(PointerDownEvent e) {
    // A touch drawing a signature is never a swipe-back.
    if (SignaturePad.drawingPointers.contains(e.pointer)) {
      _dragStart = null;
      return;
    }
    if (e.buttons == kPrimaryButton || e.kind != PointerDeviceKind.mouse) {
      _dragStart = e.position;
    }
  }

  // Screens that own their own horizontal swipe (a SwipeableTabView between
  // sub-tabs) — the shell's swipe-to-go-back gesture below would otherwise
  // fire on the exact same rightward drag a user makes to flip back a tab,
  // navigating the whole screen away instead of just changing tabs.
  static const _swipeOwnedByScreen = {"plans", "progress", "photos", "measurements"};

  void _onPointerUp(PointerUpEvent e) {
    final start = _dragStart;
    _dragStart = null;
    if (start == null) return;
    if (_swipeOwnedByScreen.contains(ref.read(clientScreenProvider))) return;
    final delta = e.position - start;
    // Ignore drags starting inside the Drawer's own left-edge-swipe-to-
    // open hitbox (Scaffold's default drawerEdgeDragWidth) so the two
    // gestures never fight over the same swipe; require a deliberate,
    // mostly-horizontal, rightward motion.
    if (start.dx > 24 &&
        delta.dx > 80 &&
        delta.dx.abs() > delta.dy.abs() * 1.5) {
      _handleBack();
    }
  }

  /// The tour is a full-screen, tap-absorbing overlay. It used to re-arm
  /// every single time the client landed back on Dashboard, so coming back
  /// from a page instantly re-covered the screen and the next tap went to
  /// the tour instead of the button the client aimed at — indistinguishable
  /// from "the buttons stopped working". It now gets one chance per app
  /// session, on top of the stored tourSeen flag.
  bool _dashboardTourArmed = true;

  void _syncDashboardTour(String screen, bool tourSeenDashboard) {
    final shouldShow =
        screen == "dashboard" && !tourSeenDashboard && _dashboardTourArmed;
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
      // Navigated away mid-tour — it's had its turn, so it won't jump back
      // in front of the client when they return.
      _dashboardTourArmed = false;
      _dashboardTourEntry!.remove();
      _dashboardTourEntry = null;
    }
  }

  void _finishDashboardTour() {
    _dashboardTourArmed = false;
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

    // Watched, not read: opening or closing a sub-view has to re-evaluate
    // whether back exits the app, and whether the top bar shows an arrow.
    final hasLocalBack = ref.watch(localBackStackProvider).isNotEmpty;
    final canGoBack = ref.watch(clientScreenProvider.notifier).canGoBack;
    final showBack = screen != "dashboard" || canGoBack || hasLocalBack;

    return PopScope(
      // Exit the app only from Dashboard, with nothing open and nothing
      // behind it. Everywhere else back stays inside the app.
      canPop: screen == "dashboard" && !canGoBack && !hasLocalBack,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColors.bg,
        drawer: _ClientDrawer(info: info, screen: screen, onGo: go),
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          child: Stack(
            children: [
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // Top bar
                    Container(
                      decoration: const BoxDecoration(
                        color: AppColors.bg,
                        border: Border(
                          bottom: BorderSide(color: AppColors.line),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            // Both of these used to be 22x22 hit areas sitting
                            // 6px apart — roughly 3.5mm on a real phone, with
                            // a 1mm gap between two different actions. Taps
                            // landed on nothing, or opened the drawer when
                            // back was meant, which read as "back is broken".
                            // A widget test never catches it (it taps the
                            // exact centre), so they're now full 44px targets
                            // with real space between them.
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
                                visualDensity: VisualDensity.standard,
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                              ),
                            ),
                            if (showBack) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: _handleBack,
                                tooltip: "Back",
                                icon: const Icon(
                                  LucideIcons.chevronLeft,
                                  size: 24,
                                  color: AppColors.txt,
                                ),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.standard,
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                              ),
                            ],
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
                            if (screen == "chat") ...[
                              IconButton(
                                onPressed: () => showChatInfoSheet(context),
                                icon: const Icon(
                                  LucideIcons.info,
                                  size: 20,
                                  color: AppColors.mute,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 12),
                            ],
                            InkWell(
                              onTap: () => go("settings"),
                              borderRadius: BorderRadius.circular(20),
                              child: (info.photo != null && info.photo!.isNotEmpty)
                                  ? Avatar(
                                      src: info.photo,
                                      name: info.name,
                                      size: 40,
                                      active: true,
                                    )
                                  : Container(
                                      width: 40,
                                      height: 40,
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: AppColors.gold, width: 1.5),
                                        color: AppColors.gold.withValues(alpha: 0.15),
                                      ),
                                      child: Image.asset("assets/images/logo.png", fit: BoxFit.contain),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Content
                    Expanded(
                      child: AnimatedScreenSwitcher(
                        screenKey: screen,
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
                          onGoMemberships: () => go("memberships"),
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
                          onGoSignatures: () => go("signatures"),
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
                          onGoSignatures: () => go("signatures"),
                        ),
                        "nutrition" => const NutritionTab(),
                        "habits" => const HabitTrackerScreen(),
                        "history" => const HistoryScreen(),
                        "signatures" => SignaturesScreen(onGoBooking: goBooking),
                        "support" => const SupportScreen(),
                        "memberships" => const MembershipHubScreen(),
                        "shop" => const ShopScreen(),
                        "challenges" => const ChallengesScreen(),
                        "rewards" => RewardsScreen(
                          clientId: info.id,
                          onOpenBadges: () => go("badges"),
                        ),
                        "badges" => BadgeGalleryScreen(clientId: info.id),
                        "settings" => ProfileSettingsScreen(onReschedule: startReschedule),
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
                        _ => PlaceholderScreen(
                          title: _titles[screen] ?? screen,
                        ),
                      },
                      ),
                    ),
                  ],
                ),
              ),
              // Advanced Booking — pinned above the bottom bar, Booking tab only.
              // Scaffold already sizes `body` to exclude bottomNavigationBar, so
              // bottom: 8 here lands just above it, no extra offset needed.
              // Hidden without a plan for the same reason the booking steps
              // are: the Booking tab shows a "get a plan" panel instead, and
              // a button that leads to its own "you need a membership"
              // refusal would undercut that.
              // Also hidden whenever something is open on top of the booking
              // list — signing a waiver, confirming a pick, cancelling —
              // where it belongs to a screen the client has stepped past.
              if (screen == "booking" &&
                  ref.watch(localBackStackProvider).isEmpty &&
                  (heldAccessPlans(info, ref.watch(membershipPlansProvider)).isNotEmpty || info.isStaff))
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
                        Icon(
                          LucideIcons.calendar,
                          size: 15,
                          color: Colors.white,
                        ),
                        SizedBox(width: 8),
                        Text("Advanced Booking"),
                      ],
                    ),
                  ),
                ),
            ],
          ),
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
                        child: AnimatedTabIcon(
                          icon: item.icon,
                          label: item.label,
                          selected: on,
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
                    tooltip: "Close menu",
                    icon: const Icon(
                      LucideIcons.x,
                      size: 20,
                      color: AppColors.mute,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.standard,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
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
