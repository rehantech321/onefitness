import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/providers/trainer_providers.dart";
import "../challenges/coach_challenges_screen.dart";
import "../chat/coach_chat_screen.dart";
import "../clients/clients_screen.dart";
import "../dashboard/self_book_screen.dart";
import "../dashboard/trainer_home_screen.dart";
import "../exercises/exercises_screen.dart";
import "../memberships/manage_memberships_screen.dart";
import "../memberships/manage_products_screen.dart";
import "../memberships/manage_waivers_screen.dart";
import "../programs/nutrition_builder_screen.dart";
import "../programs/program_builder_screen.dart";
import "../reports/reports_hub_screen.dart";
import "../schedule/schedule_screen.dart";
import "../schedule/waitlist_screen.dart";
import "../settings/customize_platform_screen.dart";
import "../staff/coaches_overview_screen.dart";
import "../staff/my_pay_screen.dart";
import "../staff/my_profile_screen.dart";
import "../staff/staff_screen.dart";
import "trainer_shell_state.dart";

class _NavItem {
  const _NavItem(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

const _bottomItemsBase = [
  _NavItem("dashboard", "Home", LucideIcons.dumbbell),
  _NavItem("clients", "Clients", LucideIcons.users),
  _NavItem("chat", "Chat", LucideIcons.messageSquare),
  _NavItem("schedule", "Schedule", LucideIcons.calendar),
];
const _staffBottomItem = _NavItem("staff", "Staff", LucideIcons.user);

const _titles = {
  "dashboard": "Dashboard",
  "clients": "Clients",
  "schedule": "Scheduling",
  "chat": "Chat",
  "staff": "Staff",
  "selfbook": "Book Session",
  "challenges": "Challenges",
  "myprofile": "My Profile",
  "products": "Products",
  "reports": "Reports",
  "waitlist": "Waitlist",
  "memberships": "Memberships",
  "waivers": "Waivers & Contracts",
  "coaches": "Coaches",
  "platformSettings": "Customize Platform",
  "mypay": "My Pay",
  "exercises": "Exercises",
  "builderWorkout": "Build Workout Program",
  "builderNutrition": "Build Nutrition Program",
};

/// Mirrors App.jsx's trainer-side chrome: top bar (hamburger + title),
/// permission-gated hamburger drawer, and a bottom nav (Staff tab only for
/// the owner). Each `trainerMode` destination routes to its own screen.
/// "selfbook" has no drawer/bottom-nav entry of its own — it's reached only
/// via the "Book session · Lead by example" strip below, same as the web.
class TrainerShell extends ConsumerStatefulWidget {
  const TrainerShell({super.key});

  @override
  ConsumerState<TrainerShell> createState() => _TrainerShellState();
}

class _TrainerShellState extends ConsumerState<TrainerShell> {
  // Closes the drawer directly (bypassing Navigator.pop) so it doesn't get
  // swallowed by the PopScope below, which intercepts pop attempts whenever
  // canPop is false to run its own back-history logic instead.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(trainerModeProvider);
    final trainerAuth = ref.watch(trainerAuthProvider);
    final isOwner = trainerAuth == "owner";

    void go(String key) {
      ref.read(trainerModeProvider.notifier).go(key);
      _scaffoldKey.currentState?.closeDrawer();
    }

    final bottomItems = [..._bottomItemsBase, if (isOwner) _staffBottomItem];

    return PopScope(
      canPop: mode == "dashboard",
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ref.read(trainerModeProvider.notifier).goBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColors.bg,
        drawer: _TrainerDrawer(mode: mode, isOwner: isOwner, onGo: go),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.bg,
                  border: Border(bottom: BorderSide(color: AppColors.line)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      Builder(
                        builder: (context) => IconButton(
                          onPressed: () => Scaffold.of(context).openDrawer(),
                          icon: const Icon(
                            LucideIcons.menu,
                            size: 22,
                            color: AppColors.gold,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _titles[mode] ?? "",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: AppColors.txt,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: switch (mode) {
                  "dashboard" => const TrainerHomeScreen(),
                  "clients" => const ClientsScreen(),
                  "chat" => const CoachChatScreen(),
                  "schedule" => const ScheduleScreen(),
                  "waitlist" => const WaitlistScreen(),
                  "exercises" => const ExercisesScreen(),
                  "builderWorkout" => const ProgramBuilderScreen(),
                  "builderNutrition" => const NutritionBuilderScreen(),
                  "staff" => const StaffScreen(),
                  "coaches" => const CoachesOverviewScreen(),
                  "myprofile" => const MyProfileScreen(),
                  "mypay" => const MyPayScreen(),
                  "reports" => const ReportsHubScreen(),
                  "memberships" => const ManageMembershipsScreen(),
                  "products" => const ManageProductsScreen(),
                  "waivers" => const ManageWaiversScreen(),
                  "platformSettings" => const CustomizePlatformScreen(),
                  "challenges" => const CoachChallengesScreen(),
                  "selfbook" => const SelfBookScreen(),
                  _ => PlaceholderScreen(title: _titles[mode] ?? mode),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // "Book session · Lead by example" — coach (non-owner) + dashboard
                // only, mirrors the fixed strip App.jsx renders just above its
                // own bottom toolbar.
                if (!isOwner && mode == "dashboard")
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: InkWell(
                      onTap: () => go("selfbook"),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.bottomBarBg,
                          border: Border.all(color: AppColors.goldDim),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.dumbbell,
                              size: 14,
                              color: AppColors.gold,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Book session",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.txt,
                                      fontWeight: FontWeight.w700,
                                      height: 1,
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.only(top: 3),
                                    child: Text(
                                      "Lead by example",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.mute,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              LucideIcons.chevronRight,
                              size: 13,
                              color: AppColors.mute,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  height: 58,
                  child: Row(
                    children: bottomItems.map((item) {
                      final on = mode == item.key;
                      return Expanded(
                        child: InkWell(
                          onTap: () => go(item.key),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 9, bottom: 11),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  item.icon,
                                  size: 20,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerEntry {
  const _DrawerEntry(this.icon, this.label, this.key, this.visible);
  final IconData icon;
  final String label;
  final String key;
  final bool visible;
}

class _TrainerDrawer extends ConsumerWidget {
  const _TrainerDrawer({
    required this.mode,
    required this.isOwner,
    required this.onGo,
  });

  final String mode;
  final bool isOwner;
  final void Function(String) onGo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = [
      _DrawerEntry(LucideIcons.dumbbell, "Dashboard", "dashboard", true),
      _DrawerEntry(LucideIcons.users, "Clients", "clients", true),
      _DrawerEntry(LucideIcons.calendar, "Scheduling", "schedule", true),
      _DrawerEntry(
        LucideIcons.clipboardList,
        "Build Workout Program",
        "builderWorkout",
        true,
      ),
      _DrawerEntry(
        LucideIcons.apple,
        "Build Nutrition Program",
        "builderNutrition",
        true,
      ),
      _DrawerEntry(LucideIcons.dumbbell, "Exercises", "exercises", true),
      _DrawerEntry(LucideIcons.trophy, "Challenges", "challenges", true),
      _DrawerEntry(LucideIcons.fileText, "Assessments", "clients", true),
      _DrawerEntry(LucideIcons.messageSquare, "Chat", "chat", true),
      _DrawerEntry(LucideIcons.user, "My Profile", "myprofile", !isOwner),
      _DrawerEntry(LucideIcons.clipboardCheck, "Reports", "reports", isOwner),
      _DrawerEntry(LucideIcons.clipboardCheck, "My Pay", "mypay", !isOwner),
      _DrawerEntry(LucideIcons.clock, "Waitlist", "waitlist", isOwner),
      _DrawerEntry(LucideIcons.user, "Settings / Staff", "staff", isOwner),
      _DrawerEntry(
        LucideIcons.slidersHorizontal,
        "Customize Platform",
        "platformSettings",
        isOwner,
      ),
      _DrawerEntry(
        LucideIcons.clipboardList,
        "Memberships",
        "memberships",
        isOwner,
      ),
      _DrawerEntry(LucideIcons.package, "Products", "products", isOwner),
      _DrawerEntry(
        LucideIcons.fileSignature,
        "Waivers & Contracts",
        "waivers",
        isOwner,
      ),
      _DrawerEntry(LucideIcons.users, "Coaches", "coaches", isOwner),
    ].where((e) => e.visible).toList();

    return Drawer(
      backgroundColor: AppColors.card,
      width: 288,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.line)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.dumbbell,
                        size: 18,
                        color: AppColors.gold,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "ONE Fitness",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
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
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: entries
                    .map(
                      (e) => InkWell(
                        onTap: () => onGo(e.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 15,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: AppColors.line),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(e.icon, size: 17, color: AppColors.gold),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  e.label,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.txt,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
