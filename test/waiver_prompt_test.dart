import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/providers/client_providers.dart";
import "package:onefitness/features/client/shell/client_shell.dart";
import "package:onefitness/features/client/shell/client_shell_state.dart";

/// A new client lands on Dashboard with an unsigned required waiver (the
/// built-in default) and is asked to sign it — and can skip.
void main() {
  late ProviderContainer container;

  // The Dashboard has its own "Skip for now" elsewhere; aim at the pop-up's.
  Finder inDialog(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  Future<void> boot(WidgetTester tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains("overflowed by")) return;
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
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

  testWidgets("the pop-up shows first, and Skip leads into the tour", (tester) async {
    await boot(tester);
    expect(find.text("Sign your waiver"), findsOneWidget);
    // The tour waits until the waiver question is answered.
    expect(find.text("Skip"), findsNothing);

    await tester.tap(inDialog("Skip for now"));
    await tester.pumpAndSettle();
    expect(find.text("Sign your waiver"), findsNothing);
    expect(find.text("Skip"), findsWidgets, reason: "the tour runs after the pop-up");
  });

  testWidgets("Sign now opens Signatures", (tester) async {
    await boot(tester);
    await tester.tap(inDialog("Sign now"));
    await tester.pumpAndSettle();
    expect(container.read(clientScreenProvider), "signatures");
  });

  testWidgets("asked once per session, not on every return to Dashboard", (tester) async {
    await boot(tester);
    await tester.tap(inDialog("Skip for now"));
    await tester.pumpAndSettle();
    container
        .read(clientRecordProvider.notifier)
        .update((r) => r.copyWith(tourSeenDashboard: true, tourSeenDrawer: true));
    container.read(clientScreenProvider.notifier).go("shop");
    await tester.pumpAndSettle();
    container.read(clientScreenProvider.notifier).go("dashboard");
    await tester.pumpAndSettle();
    expect(find.text("Sign your waiver"), findsNothing);
  });
}
