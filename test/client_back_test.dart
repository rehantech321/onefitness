import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:lucide_flutter/lucide_flutter.dart";

import "package:onefitness/core/navigation/local_back_stack.dart";
import "package:onefitness/data/providers/client_providers.dart";
import "package:onefitness/features/client/shell/client_shell.dart";
import "package:onefitness/features/client/shell/client_shell_state.dart";

/// Drives the real ClientShell the way a client does: open a page from the
/// hamburger menu or the bottom bar, then go back — with the top-bar arrow
/// AND with the Android system back button, which are separate code paths.
void main() {
  late ProviderContainer container;

  /// The fixed-width drawer and a few rows overflow by a handful of pixels on
  /// the test surface. That's cosmetic and not what these tests are about, so
  /// it's filtered out — the binding installs its own handler when the test
  /// starts, so this has to be re-applied inside each test body.
  void ignoreOverflow() {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains("overflowed by")) return;
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  }

  Future<void> boot(WidgetTester tester) async {
    ignoreOverflow();
    container = ProviderContainer();
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ClientShell()),
      ),
    );
    // Kill the coachmark tours — they overlay the whole screen and eat taps.
    container
        .read(clientRecordProvider.notifier)
        .update((r) => r.copyWith(tourSeenDashboard: true, tourSeenDrawer: true));
    await tester.pumpAndSettle();
  }

  String screen() => container.read(clientScreenProvider);
  int localDepth() => container.read(localBackStackProvider).length;

  Future<void> openMenuItem(WidgetTester tester, String label) async {
    await tester.tap(find.byIcon(LucideIcons.menu));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(label), 60,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
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

  // Every entry in ClientShell's hamburger menu, label → screen key.
  const menuPages = {
    "Log Progress": "progress",
    "Workout Plan": "plans",
    "Nutrition Plan": "nutrition",
    "Habit Tracker": "habits",
    "History": "history",
    "Assessments": "forms",
    "Shop": "shop",
    "Rewards": "rewards",
    "Merit Badges": "badges",
    "Challenges": "challenges",
    "My Squad": "squad",
    "Signatures": "signatures",
    "Support": "support",
    "Profile Settings": "settings",
  };

  // Every bottom-bar tab except Dashboard itself.
  const bottomTabs = {
    "Plans": "plans",
    "Booking": "booking",
    "Chat": "chat",
    "Access Hub": "memberships",
  };

  group("hamburger menu pages", () {
    for (final entry in menuPages.entries) {
      testWidgets("${entry.key}: opens, then back returns to Dashboard",
          (tester) async {
        await boot(tester);
        await openMenuItem(tester, entry.key);
        expect(screen(), entry.value, reason: "${entry.key} should open");
        expect(localDepth(), 0,
            reason: "${entry.key} opened a sub-view on arrival — back would "
                "be swallowed closing something the client never opened");
        expect(find.byIcon(LucideIcons.chevronLeft), findsWidgets,
            reason: "${entry.key} must show a back arrow");

        await tapBack(tester);
        expect(screen(), "dashboard",
            reason: "top-bar back from ${entry.key} must reach Dashboard");
      });

      testWidgets("${entry.key}: system back returns to Dashboard",
          (tester) async {
        await boot(tester);
        await openMenuItem(tester, entry.key);
        await systemBack(tester);
        expect(screen(), "dashboard",
            reason: "system back from ${entry.key} must reach Dashboard");
      });
    }
  });

  group("bottom tabs", () {
    for (final entry in bottomTabs.entries) {
      testWidgets("${entry.key}: opens, then back returns to Dashboard",
          (tester) async {
        await boot(tester);
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(screen(), entry.value);
        expect(localDepth(), 0,
            reason: "${entry.key} opened a sub-view on arrival");

        await tapBack(tester);
        expect(screen(), "dashboard",
            reason: "back from ${entry.key} must reach Dashboard");
      });
    }
  });

  testWidgets("multi-step trail unwinds one page at a time", (tester) async {
    await boot(tester);
    await tester.tap(find.text("Plans"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Booking"));
    await tester.pumpAndSettle();
    await openMenuItem(tester, "Rewards");
    expect(screen(), "rewards");

    await tapBack(tester);
    expect(screen(), "booking");
    await tapBack(tester);
    expect(screen(), "plans");
    await tapBack(tester);
    expect(screen(), "dashboard");
  });

  testWidgets("back and menu are thumb-sized and not crowded together",
      (tester) async {
    await boot(tester);
    await openMenuItem(tester, "Shop");

    final back = tester.getRect(find.ancestor(
      of: find.byIcon(LucideIcons.chevronLeft),
      matching: find.byType(IconButton),
    ).first);
    final menu = tester.getRect(find.ancestor(
      of: find.byIcon(LucideIcons.menu),
      matching: find.byType(IconButton),
    ).first);

    // A 22x22 hit area is ~3.5mm on a real phone — taps miss it constantly,
    // which is invisible to a test that taps the exact centre.
    expect(back.width, greaterThanOrEqualTo(44),
        reason: "back button is too narrow to hit reliably");
    expect(back.height, greaterThanOrEqualTo(44),
        reason: "back button is too short to hit reliably");
    expect(menu.width, greaterThanOrEqualTo(44));
    expect(menu.height, greaterThanOrEqualTo(44));
    // And they must not be so close that aiming for one hits the other.
    expect(back.left - menu.right, greaterThanOrEqualTo(8),
        reason: "back sits too close to the hamburger");
  });

  testWidgets("back still works after tapping near the edge of the button",
      (tester) async {
    await boot(tester);
    await openMenuItem(tester, "Shop");
    final back = tester.getRect(find.ancestor(
      of: find.byIcon(LucideIcons.chevronLeft),
      matching: find.byType(IconButton),
    ).first);
    // A sloppy thumb landing 16px left-of-centre and 14px low.
    await tester.tapAt(Offset(back.center.dx - 16, back.center.dy + 14));
    await tester.pumpAndSettle();
    expect(screen(), "dashboard",
        reason: "an off-centre tap on the back button must still register");
  });

  testWidgets("cold page with no history falls back to Dashboard",
      (tester) async {
    await boot(tester);
    container.read(clientScreenProvider.notifier).go("shop");
    container.read(clientScreenProvider.notifier).reset();
    container.read(clientScreenProvider.notifier).go("rewards");
    await tester.pumpAndSettle();

    await tapBack(tester);
    expect(screen(), "dashboard");
  });
}
