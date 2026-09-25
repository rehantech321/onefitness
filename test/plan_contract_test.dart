import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/merge_token_utils.dart";
import "package:onefitness/data/models/membership_plan.dart";
import "package:onefitness/data/models/signature.dart";
import "package:onefitness/data/models/waiver_doc.dart";
import "package:onefitness/data/providers/client_providers.dart";
import "package:onefitness/data/providers/trainer_providers.dart";
import "package:onefitness/features/client/drawer_screens/membership_hub_screen.dart";
import "package:onefitness/features/client/drawer_screens/waiver_signing_screen.dart";

/// A plan the admin attached a contract to must be unbuyable until the
/// client has signed that contract — and signing an out-of-date version
/// doesn't count.
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

  const contractBody = "I agree to the 12-month term and its cancellation terms.";

  const plan = MembershipPlan(
    id: "gold-monthly",
    name: "Gold Monthly",
    kind: PlanKind.membership,
    priceCents: 1250,
    maxSessions: 8,
    category: "Memberships",
  );

  const contract = WaiverDoc(
    id: "contract-gold-monthly",
    title: "Gold Monthly Agreement",
    body: contractBody,
    scope: "plan",
    planId: "gold-monthly",
    required: true,
  );

  Future<void> boot(
    WidgetTester tester, {
    required List<WaiverDoc> docs,
    List<SignedDocument> signatures = const [],
  }) async {
    ignoreOverflow();
    container = ProviderContainer();
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    container.read(membershipPlansProvider.notifier).setAll([plan]);
    container.read(waiversProvider.notifier).setAll(docs);
    if (signatures.isNotEmpty) {
      container
          .read(clientRecordProvider.notifier)
          .update((r) => r.copyWith(signatures: signatures));
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: MembershipHubScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> visibleText() => find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .toList();

  /// Taps the plan card's actual purchase button. Exact label matches only —
  /// a "contains" match hits the "Choose a plan below…" blurb instead, which
  /// silently does nothing and makes every assertion below vacuous.
  Future<void> tapBuy(WidgetTester tester) async {
    for (final label in const ["Subscribe", "Buy", "Buy now", "Get started"]) {
      final f = find.text(label);
      if (f.evaluate().isEmpty) continue;
      await tester.ensureVisible(f.first);
      await tester.pumpAndSettle();
      await tester.tap(f.first);
      await tester.pumpAndSettle();
      // A purchase that gets past the contract gate calls Supabase, which
      // isn't wired up here — drain it so it can't mask the real assertion.
      tester.takeException();
      return;
    }
    fail("no purchase button found; screen shows ${visibleText()}");
  }

  testWidgets("a plan with a contract opens it for signing instead of buying",
      (tester) async {
    await boot(tester, docs: const [contract]);
    await tapBuy(tester);

    expect(find.byType(WaiverSigningScreen), findsOneWidget,
        reason: "the contract must be put in front of the client");
  });

  testWidgets("an already-signed contract lets the purchase proceed",
      (tester) async {
    await boot(
      tester,
      docs: const [contract],
      signatures: [
        SignedDocument(
          id: "sig-1",
          docId: contract.id,
          title: contract.title,
          signedAt: "2026-01-01T00:00:00Z",
          documentVersionHash: documentVersionHash(contractBody),
        ),
      ],
    );
    await tapBuy(tester);

    expect(find.byType(WaiverSigningScreen), findsNothing,
        reason: "a signed contract shouldn't be asked for again");
  });

  testWidgets("editing the contract invalidates an old signature",
      (tester) async {
    await boot(
      tester,
      docs: const [contract],
      signatures: [
        SignedDocument(
          id: "sig-1",
          docId: contract.id,
          title: contract.title,
          signedAt: "2026-01-01T00:00:00Z",
          // Signed against the previous wording.
          documentVersionHash: documentVersionHash("An older agreement."),
        ),
      ],
    );
    await tapBuy(tester);

    expect(find.byType(WaiverSigningScreen), findsOneWidget,
        reason: "a reworded contract must be re-signed before buying");
  });

  testWidgets("an archived contract no longer blocks the purchase",
      (tester) async {
    await boot(tester, docs: const [
      WaiverDoc(
        id: "contract-gold-monthly",
        title: "Gold Monthly Agreement",
        body: contractBody,
        scope: "plan",
        planId: "gold-monthly",
        required: true,
        archived: true,
      ),
    ]);
    await tapBuy(tester);

    expect(find.byType(WaiverSigningScreen), findsNothing,
        reason: "a contract the admin removed shouldn't still gate the plan");
  });

  testWidgets("another plan's contract doesn't gate this one", (tester) async {
    await boot(tester, docs: const [
      WaiverDoc(
        id: "contract-other",
        title: "Other Agreement",
        body: contractBody,
        scope: "plan",
        planId: "some-other-plan",
        required: true,
      ),
    ]);
    await tapBuy(tester);

    expect(find.byType(WaiverSigningScreen), findsNothing,
        reason: "contracts are per plan");
  });
}
