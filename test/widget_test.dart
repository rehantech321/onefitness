import "package:flutter_test/flutter_test.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "package:onefitness/main.dart";

void main() {
  testWidgets("Client sign-in screen renders by default", (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: OneFitnessApp()));
    await tester.pumpAndSettle();

    expect(find.text("Welcome to ONE FITNESS"), findsOneWidget);
    expect(find.text("Sign in"), findsOneWidget);
    expect(find.text("Coach"), findsOneWidget);
    expect(find.text("Client"), findsOneWidget);
  });
}
