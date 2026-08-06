import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/client_info.dart";
import "../../../data/providers/client_providers.dart";
import "../badges/badge_gallery_screen.dart";
import "../booking/booking_screen.dart";
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
  _NavItem("chat", "Chat", LucideIcons.messageSquare),
  _NavItem("nutrition", "Nutrition Plan", LucideIcons.apple),
  _NavItem("plans", "Workout Plan", LucideIcons.clipboardList),
  _NavItem("progress", "Log Progress", LucideIcons.barChart2),
  _NavItem("habits", "Habit Tracker", LucideIcons.flame),
  _NavItem("challenges", "Challenges", LucideIcons.trophy),
  _NavItem("rewards", "Rewards", LucideIcons.gift),
  _NavItem("badges", "Merit Badges", LucideIcons.award),
  _NavItem("history", "History", LucideIcons.history),
  _NavItem("forms", "Assessments", LucideIcons.fileText),
  _NavItem("squad", "My Squad", LucideIcons.users2),
  _NavItem("signatures", "Signatures", LucideIcons.fileSignature),
  _NavItem("settings", "Profile Settings", LucideIcons.settings2),
  _NavItem("memberships", "Membership Hub", LucideIcons.creditCard),
];

const _titles = {
  "dashboard": "Dashboard",
  "plans": "Plans",
  "booking": "Booking",
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
class ClientShell extends ConsumerWidget {
  const ClientShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screen = ref.watch(clientScreenProvider);
    final info = ref.watch(clientInfoProvider);
    final client = ref.watch(clientRecordProvider);
    final bookings = ref.watch(clientBookingsProvider);
    final earnedBadges = ref.watch(earnedBadgesProvider);

    void go(String key) {
      ref.read(clientScreenProvider.notifier).go(key);
      Navigator.of(context).maybePop(); // closes the drawer if open
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      drawer: _ClientDrawer(info: info, screen: screen, onGo: go),
      body: SafeArea(
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Builder(
                      builder: (context) => IconButton(
                        onPressed: () => Scaffold.of(context).openDrawer(),
                        icon: const Icon(LucideIcons.menu, size: 22, color: AppColors.txt),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _titles[screen] ?? "",
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.3),
                      ),
                    ),
                    Avatar(src: info.photo, name: info.name, size: 30, active: true),
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
                    bookings: bookings,
                    onGoBooking: () => go("booking"),
                    onLogWorkout: () => go("plans"),
                    onPickDate: (_) {},
                    onGoHabits: () => go("habits"),
                    earnedBadges: earnedBadges,
                    onGoBadges: () => go("badges"),
                  ),
                "chat" => const ChatScreen(),
                "plans" => const PlansScreen(),
                "booking" => BookingScreen(onGoMemberships: () => go("memberships")),
                "nutrition" => const NutritionTab(),
                "habits" => const HabitTrackerScreen(),
                "history" => const HistoryScreen(),
                "signatures" => const SignaturesScreen(),
                "memberships" => const MembershipHubScreen(),
                "challenges" => const ChallengesScreen(),
                "rewards" => RewardsScreen(clientId: info.id),
                "badges" => BadgeGalleryScreen(clientId: info.id),
                "settings" => const ProfileSettingsScreen(),
                "squad" => const SquadDashboardScreen(),
                "forms" => const IntakeAreaScreen(),
                "progress" || "photos" || "measurements" => const LogProgressScreen(),
                _ => PlaceholderScreen(title: _titles[screen] ?? screen),
              },
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
                  child: InkWell(
                    onTap: () => go(item.key),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 9, bottom: 11),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(item.icon, size: 21, color: on ? AppColors.gold : AppColors.mute),
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
    );
  }
}

class _ClientDrawer extends ConsumerWidget {
  const _ClientDrawer({required this.info, required this.screen, required this.onGo});

  final ClientInfo info;
  final String screen;
  final void Function(String) onGo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  Avatar(src: info.photo, name: info.name, size: 40, active: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(info.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        Text(info.city ?? "", style: const TextStyle(fontSize: 11, color: AppColors.mute)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(LucideIcons.x, size: 18, color: AppColors.mute),
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
                      onTap: () => onGo(item.key),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
                        decoration: BoxDecoration(
                          color: on ? AppColors.gold.withValues(alpha: 0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(item.icon, size: 18, color: on ? AppColors.gold : AppColors.mute),
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
                      Icon(LucideIcons.lock, size: 16, color: AppColors.errorText),
                      SizedBox(width: 12),
                      Text("Sign out", style: TextStyle(fontSize: 13, color: AppColors.errorText)),
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
