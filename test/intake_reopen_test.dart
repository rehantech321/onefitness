import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/navigation/local_back_stack.dart";
import "package:onefitness/data/models/client_record.dart";
import "package:onefitness/data/providers/client_providers.dart";
import "package:onefitness/features/client/intake/intake_area_screen.dart";
import "package:onefitness/features/client/shell/client_shell_state.dart";

/// Opening an intake form, backing out, and opening it again.
///
/// The screen has no Navigator — an open form is private `setState` state,
/// and shell-level back reaches it through the local back stack. That makes
/// "close" and "the shell knows it closed" two separate things, and a tap
/// that lands while they disagree is a tap that appears to do nothing.
void main() {
  final editorOpen = find.textContaining("Fill what you can");
  final trainingRow = find.text("Personalized Training Intake");

  /// [owning] false strips the demo plans, which is what puts the client in
  /// the state the report came from: nothing bought, so the "Choose a plan"
  /// card is on screen above the forms.
  Future<ProviderContainer> pump(WidgetTester tester, {bool owning = true}) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    if (!owning) container.read(membershipPlansProvider.notifier).setAll([]);
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: IntakeAreaScreen(
              profileId: "p1",
              client: const ClientRecord(id: "c1"),
              who: "client",
              onSaved: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  /// Back as the shell does it: whatever is on top of the local stack.
  void shellBack(ProviderContainer container) {
    final top = container.read(localBackStackProvider.notifier).top;
    expect(top, isNotNull, reason: "the shell had no back handler to call");
    top!();
  }

  testWidgets("a form opens, closes, and opens again", (tester) async {
    final container = await pump(tester);

    await tester.tap(trainingRow);
    await tester.pump();
    expect(editorOpen, findsOneWidget, reason: "first open");

    shellBack(container);
    await tester.pump();
    expect(editorOpen, findsNothing, reason: "back should close it");
    expect(trainingRow, findsOneWidget);

    // The tap the client says does nothing.
    await tester.tap(trainingRow);
    await tester.pump();
    expect(editorOpen, findsOneWidget, reason: "second open");
  });

  testWidgets("the shell is told the form closed", (tester) async {
    // A handler left behind means the shell still thinks a sub-view is open:
    // the next back closes nothing, and the top bar keeps an arrow that
    // leads nowhere.
    final container = await pump(tester);

    await tester.tap(trainingRow);
    await tester.pump();
    expect(container.read(localBackStackProvider), hasLength(1));

    shellBack(container);
    await tester.pump();
    expect(container.read(localBackStackProvider), isEmpty);
  });

  testWidgets("the sequence as it was reported", (tester) async {
    // Open the training intake, back out, tap it again, then tap the
    // Membership Hub button. What was reported: the second tap did nothing,
    // and the Hub button opened the intake instead of going to the Hub —
    // one interaction behind, because the shell's back stack was left
    // holding a handler for a screen that had already closed.
    final container = await pump(tester, owning: false);

    await tester.tap(trainingRow);
    await tester.pump();
    shellBack(container);
    await tester.pump();

    await tester.tap(trainingRow);
    await tester.pump();
    expect(editorOpen, findsOneWidget, reason: "the tap that did nothing");

    shellBack(container);
    await tester.pump();
    expect(editorOpen, findsNothing);

    await tester.tap(find.text("Go to Membership Hub"));
    await tester.pump();
    expect(container.read(clientScreenProvider), "memberships");
    expect(editorOpen, findsNothing, reason: "the Hub button opened a form");
  });

  testWidgets("opening a form registers back before the next tap can land", (tester) async {
    // The push is what makes back close the form rather than leave the
    // screen. If it lands a frame late, the gap is a frame in which back
    // walks straight past an open form.
    final container = await pump(tester);

    await tester.tap(trainingRow);
    await tester.pump();
    expect(
      container.read(localBackStackProvider),
      hasLength(1),
      reason: "back handler not registered in the frame the form opened",
    );
  });
}
