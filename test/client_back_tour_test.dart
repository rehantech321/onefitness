import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:lucide_flutter/lucide_flutter.dart";

import "package:onefitness/features/client/shell/client_shell.dart";
import "package:onefitness/features/client/shell/client_shell_state.dart";

/// Same journey as client_back_test.dart, but with the first-run coachmark
/// tours LEFT ON — which is the state every new client is actually in.
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
    await tester.pumpAndSettle();
  }

  String screen() => container.read(clientScreenProvider);

  testWidgets("the dashboard tour does not re-arm on every return home",
      (tester) async {
    await boot(tester);
    // First run: the walkthrough is up, and it is modal by design.
    expect(find.text("Skip"), findsWidgets,
        reason: "a first-run client should get the walkthrough");

    // Leave Dashboard without finishing it, then come back.
    container.read(clientScreenProvider.notifier).go("shop");
    await tester.pumpAndSettle();
    container.read(clientScreenProvider.notifier).goBack();
    await tester.pumpAndSettle();
    expect(screen(), "dashboard");

    // It must NOT jump back in front of the client — that re-covered the
    // screen with a tap-absorbing overlay, so the next tap went to the tour
    // instead of the button aimed at, which reads as "nothing works".
    expect(find.text("Skip"), findsNothing,
        reason: "the tour must not re-cover the screen on every return");

    // And the UI underneath must be live again.
    await tester.tap(find.byIcon(LucideIcons.menu));
    await tester.pumpAndSettle();
    expect(find.text("Sign out"), findsOneWidget,
        reason: "the hamburger must work once the tour has had its turn");
  });

  testWidgets("first-run: open a menu page, then back", (tester) async {
    await boot(tester);
    // Dismiss the dashboard tour the way a client would: Skip.
    if (find.text("Skip").evaluate().isNotEmpty) {
      await tester.tap(find.text("Skip").first);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byIcon(LucideIcons.menu), warnIfMissed: false);
    await tester.pumpAndSettle();
    // The drawer tour is now up; skip it too.
    if (find.text("Skip").evaluate().isNotEmpty) {
      await tester.tap(find.text("Skip").first);
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(find.text("Shop"), 60,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text("Shop"));
    await tester.pumpAndSettle();
    expect(screen(), "shop");

    await tester.tap(find.byIcon(LucideIcons.chevronLeft).first,
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(screen(), "dashboard",
        reason: "back must work on a first-run client too");
  });

  testWidgets("returning to Dashboard re-shows the tour and blocks the UI",
      (tester) async {
    await boot(tester);
    container.read(clientScreenProvider.notifier).go("shop");
    await tester.pumpAndSettle();
    // Off Dashboard the tour should be gone, so back must be tappable.
    await tester.tap(find.byIcon(LucideIcons.chevronLeft).first,
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(screen(), "dashboard");
  });
}
