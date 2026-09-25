import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/providers/client_providers.dart";
import "package:onefitness/features/client/drawer_screens/add_phone_screen.dart";

/// Picking In App / SMS needs a number to text. Signup doesn't collect one
/// any more, so it's asked for at that moment and saved to the profile.
void main() {
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester, {String phone = ""}) async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(clientInfoProvider.notifier).update((i) => i.copyWith(phone: phone));
  }

  testWidgets("a client with no number on file is flagged as needing one",
      (tester) async {
    await pump(tester);
    late bool needs;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(builder: (ctx, ref, _) {
            needs = clientNeedsPhone(ref);
            return const SizedBox.shrink();
          }),
        ),
      ),
    );
    expect(needs, isTrue);
  });

  testWidgets("a client who already gave one is not asked again",
      (tester) async {
    await pump(tester, phone: "(555) 010-0199");
    late bool needs;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(builder: (ctx, ref, _) {
            needs = clientNeedsPhone(ref);
            return const SizedBox.shrink();
          }),
        ),
      ),
    );
    expect(needs, isFalse);
  });

  testWidgets("whitespace doesn't count as a number", (tester) async {
    await pump(tester, phone: "   ");
    late bool needs;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(builder: (ctx, ref, _) {
            needs = clientNeedsPhone(ref);
            return const SizedBox.shrink();
          }),
        ),
      ),
    );
    expect(needs, isTrue);
  });

  test("phone validation accepts real formats and rejects junk", () {
    // Formats people actually type.
    expect(isUsablePhone("5550100"), isTrue);
    expect(isUsablePhone("(555) 010-0199"), isTrue);
    expect(isUsablePhone("+1 555 010 0199"), isTrue);
    expect(isUsablePhone("+92 324 3074616"), isTrue);
    // Not enough to be a phone number.
    expect(isUsablePhone(""), isFalse);
    expect(isUsablePhone("   "), isFalse);
    expect(isUsablePhone("123"), isFalse);
    expect(isUsablePhone("call me"), isFalse);
  });

  testWidgets("the dialog saves the number onto the profile", (tester) async {
    await pump(tester);
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(builder: (ctx, ref, _) {
            capturedRef = ref;
            return Scaffold(
              body: Builder(
                builder: (btnCtx) => ElevatedButton(
                  onPressed: () => promptForPhoneDialog(btnCtx, ref, reason: "Why we ask."),
                  child: const Text("open"),
                ),
              ),
            );
          }),
        ),
      ),
    );

    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();

    expect(find.text("Add your phone number"), findsOneWidget);
    expect(find.text("Why we ask."), findsOneWidget,
        reason: "the prompt must say why the number is needed");

    // Too short is refused without closing the dialog.
    await tester.enterText(find.byType(TextField), "123");
    await tester.tap(find.text("Save"));
    await tester.pumpAndSettle();
    expect(find.textContaining("Enter a number"), findsOneWidget);
    expect(find.text("Add your phone number"), findsOneWidget);

    // "Not now" backs out without saving.
    await tester.tap(find.text("Not now"));
    await tester.pumpAndSettle();
    expect(find.text("Add your phone number"), findsNothing);
    expect(clientNeedsPhone(capturedRef), isTrue,
        reason: "backing out must not store anything");
  });
}
