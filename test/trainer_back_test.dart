import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:lucide_flutter/lucide_flutter.dart";

import "package:onefitness/core/widgets/animated_tab_icon.dart";
import "package:onefitness/core/navigation/local_back_stack.dart";
import "package:onefitness/data/providers/client_providers.dart";
import "package:onefitness/data/providers/trainer_providers.dart";
import "package:onefitness/features/trainer/shell/trainer_shell.dart";
import "package:onefitness/features/trainer/shell/trainer_shell_state.dart";

/// Drives the real TrainerShell as both a coach and the owner (admin):
/// open every page from the hamburger and the bottom bar, then go back with
/// the top-bar arrow and with the Android system back button.
void main() {
  late ProviderContainer container;

  void ignoreOverflow() {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains("overflowed by")) return;
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  }

  /// [as] is "owner" for the admin view, or null to sign in as the first
  /// coach on the roster.
  Future<void> boot(WidgetTester tester, {String? as}) async {
    ignoreOverflow();
    container = ProviderContainer();
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final who = as ?? container.read(trainersProvider).first.id;
    container.read(trainerAuthProvider.notifier).signIn(who);
    container.read(trainerModeProvider.notifier).reset();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TrainerShell()),
      ),
    );
    await tester.pumpAndSettle();
  }

  String mode() => container.read(trainerModeProvider);
  int localDepth() => container.read(localBackStackProvider).length;

  Future<void> openMenuItem(WidgetTester tester, String label) async {
    await tester.tap(find.byIcon(LucideIcons.menu));
    await tester.pumpAndSettle();
    // Scope to the drawer — "Chat"/"Clients" also label bottom-bar tabs.
    final item = find.descendant(
      of: find.byType(Drawer),
      matching: find.text(label),
    );
    await tester.scrollUntilVisible(item, 60,
        scrollable: find.descendant(
          of: find.byType(Drawer),
          matching: find.byType(Scrollable),
        ).first);
    await tester.pumpAndSettle();
    await tester.tap(item.first);
    await tester.pumpAndSettle();
  }

  /// Scoped to the bottom bar — several of these labels ("Clients", "Chat")
  /// also appear in the page content behind it.
  Future<void> tapBottomTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
      of: find.byType(AnimatedTabIcon),
      matching: find.text(label),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapBack(WidgetTester tester) async {
    await tester.tap(find.byIcon(LucideIcons.chevronLeft).first);
    await tester.pumpAndSettle();
  }

  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  void runMenuPages(String who, String? auth, Map<String, String> pages) {
    group("$who hamburger pages", () {
      for (final entry in pages.entries) {
        testWidgets("$who — ${entry.key}: back returns to Dashboard",
            (tester) async {
          await boot(tester, as: auth);
          await openMenuItem(tester, entry.key);
          expect(mode(), entry.value, reason: "${entry.key} should open");
          expect(localDepth(), 0,
              reason: "${entry.key} opened a sub-view on arrival — back would "
                  "be swallowed closing something never opened");
          expect(find.byIcon(LucideIcons.chevronLeft), findsWidgets,
              reason: "${entry.key} must show a back arrow");

          await tapBack(tester);
          expect(mode(), "dashboard",
              reason: "top-bar back from ${entry.key} must reach Dashboard");
        });

        testWidgets("$who — ${entry.key}: system back returns to Dashboard",
            (tester) async {
          await boot(tester, as: auth);
          await openMenuItem(tester, entry.key);
          await systemBack(tester);
          expect(mode(), "dashboard",
              reason: "system back from ${entry.key} must reach Dashboard");
        });
      }
    });
  }

  // Coach (non-owner) hamburger, minus Dashboard (already there).
  runMenuPages("coach", null, const {
    "Clients": "clients",
    "Scheduling": "schedule",
    "Waitlist": "waitlist",
    "Exercises": "exercises",
    "Equipment Library": "equipment",
    "Challenges": "challenges",
    "Chat": "chat",
    "My Profile": "myprofile",
    "Calendar Sync": "calendarsync",
    "Merit Badges": "coachbadges",
    "My Pay": "mypay",
    "Support": "support",
  });

  // Admin (owner) hamburger. "Reports" is a group whose label navigates.
  runMenuPages("admin", "owner", const {
    "Chat": "chat",
    "Build Workout Program": "builderWorkout",
    "Build Nutrition Program": "builderNutrition",
    "Exercises": "exercises",
    "Equipment Library": "equipment",
    "Challenges": "challenges",
    "Waitlist": "waitlist",
    "Access Hub": "memberships",
    "Products": "products",
    "Reports": "reports",
    "Support": "support",
  });

  group("admin Reports sub-pages", () {
    for (final entry in const {
      "Coaches": "coaches",
      "Customize Platform": "platformSettings",
      "Waivers & Contracts": "waivers",
    }.entries) {
      testWidgets("admin — ${entry.key}: back returns to Dashboard",
          (tester) async {
        await boot(tester, as: "owner");
        await tester.tap(find.byIcon(LucideIcons.menu));
        await tester.pumpAndSettle();
        final reports = find.descendant(
            of: find.byType(Drawer), matching: find.text("Reports"));
        await tester.scrollUntilVisible(
          reports,
          60,
          scrollable: find
              .descendant(
                  of: find.byType(Drawer), matching: find.byType(Scrollable))
              .first,
        );
        await tester.pumpAndSettle();
        // Expand the group via the chevron in Reports' own row — index 1 is
        // the outer Row holding the label and the chevron together.
        await tester.tap(find.descendant(
          of: find.ancestor(of: reports, matching: find.byType(Row)).at(1),
          matching: find.byIcon(LucideIcons.chevronDown),
        ));
        await tester.pumpAndSettle();

        final item = find.descendant(
            of: find.byType(Drawer), matching: find.text(entry.key));
        await tester.scrollUntilVisible(item, 60,
            scrollable: find
                .descendant(
                    of: find.byType(Drawer), matching: find.byType(Scrollable))
                .first);
        await tester.pumpAndSettle();
        await tester.tap(item.first);
        await tester.pumpAndSettle();
        expect(mode(), entry.value);

        await tapBack(tester);
        expect(mode(), "dashboard",
            reason: "back from ${entry.key} must reach Dashboard");
      });
    }
  });

  group("bottom tabs", () {
    for (final entry in const {
      "Clients": "clients",
      "Chat": "chat",
      "Schedule": "schedule",
    }.entries) {
      testWidgets("coach — ${entry.key} tab: back returns to Dashboard",
          (tester) async {
        await boot(tester);
        await tapBottomTab(tester, entry.key);
        expect(mode(), entry.value);
        await tapBack(tester);
        expect(mode(), "dashboard");
      });
    }

    testWidgets("admin — Staff settings tab: back returns to Dashboard",
        (tester) async {
      await boot(tester, as: "owner");
      await tapBottomTab(tester, "Staff settings");
      expect(mode(), "staff");
      await tapBack(tester);
      expect(mode(), "dashboard");
    });
  });

  testWidgets("admin — multi-step trail unwinds one page at a time",
      (tester) async {
    await boot(tester, as: "owner");
    await tapBottomTab(tester, "Clients");
    await openMenuItem(tester, "Products");
    await openMenuItem(tester, "Challenges");
    expect(mode(), "challenges");

    await tapBack(tester);
    expect(mode(), "products");
    await tapBack(tester);
    expect(mode(), "clients");
    await tapBack(tester);
    expect(mode(), "dashboard");
  });

  testWidgets("coach — cold page with no history falls back to Dashboard",
      (tester) async {
    await boot(tester);
    container.read(trainerModeProvider.notifier).go("exercises");
    container.read(trainerModeProvider.notifier).reset();
    container.read(trainerModeProvider.notifier).go("waitlist");
    await tester.pumpAndSettle();

    await tapBack(tester);
    expect(mode(), "dashboard");
  });

  testWidgets("back and menu are thumb-sized and not crowded together",
      (tester) async {
    await boot(tester, as: "owner");
    await openMenuItem(tester, "Products");

    final back = tester.getRect(find
        .ancestor(
          of: find.byIcon(LucideIcons.chevronLeft),
          matching: find.byType(IconButton),
        )
        .first);
    final menu = tester.getRect(find
        .ancestor(
          of: find.byIcon(LucideIcons.menu),
          matching: find.byType(IconButton),
        )
        .first);

    expect(back.width, greaterThanOrEqualTo(44),
        reason: "back button is too narrow to hit reliably");
    expect(back.height, greaterThanOrEqualTo(44));
    expect(menu.width, greaterThanOrEqualTo(44));
    expect(menu.height, greaterThanOrEqualTo(44));
    expect(back.left - menu.right, greaterThanOrEqualTo(8),
        reason: "back sits too close to the hamburger");
  });

  testWidgets("back still works after an off-centre tap", (tester) async {
    await boot(tester, as: "owner");
    await openMenuItem(tester, "Products");
    final back = tester.getRect(find
        .ancestor(
          of: find.byIcon(LucideIcons.chevronLeft),
          matching: find.byType(IconButton),
        )
        .first);
    await tester.tapAt(Offset(back.center.dx - 16, back.center.dy + 14));
    await tester.pumpAndSettle();
    expect(mode(), "dashboard",
        reason: "an off-centre tap on the back button must still register");
  });
}
