import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/models/membership_plan.dart";
import "package:onefitness/data/providers/client_providers.dart";
import "package:onefitness/features/client/drawer_screens/add_phone_screen.dart";
import "package:onefitness/features/client/drawer_screens/membership_hub_screen.dart";

/// Apple guideline 5.1.1: a phone number isn't required to open an account.
/// It's asked for at the point it's actually needed — buying a plan, which
/// commits the client to in-person sessions a coach has to coordinate.
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

  const plan = MembershipPlan(
    id: "gold-monthly",
    name: "Gold Monthly",
    kind: PlanKind.membership,
    priceCents: 1250,
    maxSessions: 8,
    category: "Memberships",
  );

  // "" rather than null for "no number on file": copyWith(phone: null)
  // keeps the existing value, and signup stores an empty string anyway when
  // the client skips the field.
  Future<void> boot(WidgetTester tester, {String phone = ""}) async {
    ignoreOverflow();
    container = ProviderContainer();
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    container.read(membershipPlansProvider.notifier).setAll([plan]);
    container
        .read(clientInfoProvider.notifier)
        .update((i) => i.copyWith(phone: phone));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: MembershipHubScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapBuy(WidgetTester tester) async {
    final f = find.text("Subscribe");
    await tester.ensureVisible(f.first);
    await tester.pumpAndSettle();
    await tester.tap(f.first);
    await tester.pumpAndSettle();
    tester.takeException();
  }

  testWidgets("a client with no phone is asked for one before buying",
      (tester) async {
    await boot(tester);
    await tapBuy(tester);

    expect(find.byType(AddPhoneScreen), findsOneWidget,
        reason: "buying should stop to collect a phone number");
    expect(
      find.textContaining("coordinate your sessions"),
      findsWidgets,
      reason: "the prompt must say why the number is needed",
    );
  });

  testWidgets("a client who already gave a phone isn't asked again",
      (tester) async {
    await boot(tester, phone: "(555) 010-0199");
    await tapBuy(tester);

    expect(find.byType(AddPhoneScreen), findsNothing,
        reason: "a number already on file shouldn't be asked for again");
  });

  testWidgets("a blank phone counts as missing", (tester) async {
    await boot(tester, phone: "   ");
    await tapBuy(tester);

    expect(find.byType(AddPhoneScreen), findsOneWidget);
  });

  testWidgets("the prompt can be cancelled without buying", (tester) async {
    await boot(tester);
    await tapBuy(tester);
    expect(find.byType(AddPhoneScreen), findsOneWidget);

    await tester.tap(find.text("Cancel"));
    await tester.pumpAndSettle();

    expect(find.byType(AddPhoneScreen), findsNothing);
    expect(find.text("Subscribe"), findsWidgets,
        reason: "cancelling returns to the plan list");
  });

  testWidgets("a too-short number is refused with a clear message",
      (tester) async {
    await boot(tester);
    await tapBuy(tester);

    await tester.enterText(find.byType(TextField).first, "123");
    await tester.tap(find.text("Save and continue"));
    await tester.pumpAndSettle();

    expect(find.textContaining("Enter a phone number"), findsOneWidget);
    expect(find.byType(AddPhoneScreen), findsOneWidget,
        reason: "still on the prompt until a usable number is given");
  });
}
