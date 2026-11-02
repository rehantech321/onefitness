import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/models/client_info.dart";
import "package:onefitness/data/models/client_record.dart";
import "package:onefitness/data/models/intake_schema.dart";
import "package:onefitness/data/providers/client_providers.dart";
import "package:onefitness/data/providers/trainer_providers.dart";
import "package:onefitness/features/trainer/clients/intake_tab.dart";

/// The coach's Assessments tab, reported as freezing on open.
///
/// `pumpAndSettle` is the detector: it drives frames until the tree stops
/// scheduling new ones and throws if that never happens. A build that keeps
/// re-triggering itself renders content and then pins the UI thread — which
/// looks exactly like a freeze on a device, with the page visible but dead
/// to touch.
void main() {
  Future<void> pumpTab(
    WidgetTester tester, {
    required ClientRecord record,
    ClientInfo? info,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(trainerClientRecordsProvider.notifier).setAll({record.id: record});
    container.read(trainerRosterProvider.notifier).setAll([
      info ?? ClientInfo(id: record.id, name: "Chris McCarthy"),
    ]);
    container.read(membershipPlansProvider.notifier).setAll(const []);
    container.read(trainerAuthProvider.notifier).signIn("owner");

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: IntakeTab(clientId: record.id))),
      ),
    );
  }

  testWidgets("opening the list settles instead of rebuilding forever", (tester) async {
    await pumpTab(tester, record: const ClientRecord(id: "c1"));
    // Throws on timeout if the tree never stops scheduling frames.
    await tester.pumpAndSettle();
    expect(find.text("Personalized Training Intake"), findsOneWidget);
    expect(find.text("Nutrition Program Intake"), findsOneWidget);
  });

  testWidgets("a client with no plan still settles", (tester) async {
    // The physical assessment row is shown to staff even unentitled, and its
    // entitlement check is the one piece of this screen that can schedule
    // work after a frame.
    await pumpTab(
      tester,
      record: const ClientRecord(id: "c1"),
      info: const ClientInfo(id: "c1", name: "Chris McCarthy"),
    );
    await tester.pumpAndSettle();
    expect(find.text("Free Physical Assessment Session"), findsOneWidget);
  });

  testWidgets("a completed intake settles too", (tester) async {
    await pumpTab(
      tester,
      record: const ClientRecord(
        id: "c1",
        intake: {
          "personalTraining": IntakeRecord(completed: true, by: "Client", at: "2026-10-02"),
          "nutritional": IntakeRecord(completed: true, by: "Client", at: "2026-10-02"),
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Personalized Training Intake"), findsOneWidget);
  });

  testWidgets("the roster not having loaded yet still settles", (tester) async {
    // trainerRosterProvider is seeded separately from client records, so
    // there is a window where the record exists and the ClientInfo doesn't.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(trainerClientRecordsProvider.notifier).setAll({"c1": const ClientRecord(id: "c1")});
    container.read(trainerRosterProvider.notifier).setAll(const []);
    container.read(membershipPlansProvider.notifier).setAll(const []);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: IntakeTab(clientId: "c1"))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Personalized Training Intake"), findsOneWidget);
  });

  testWidgets("opening the physical assessment settles", (tester) async {
    await pumpTab(tester, record: const ClientRecord(id: "c1"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Free Physical Assessment Session"));
    await tester.pumpAndSettle();
    expect(find.text("Physical Assessment"), findsOneWidget);
  });

  testWidgets("opening the training questionnaire settles", (tester) async {
    await pumpTab(tester, record: const ClientRecord(id: "c1"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Personalized Training Intake"));
    await tester.pumpAndSettle();
  });

  testWidgets("opening the nutrition questionnaire settles", (tester) async {
    await pumpTab(tester, record: const ClientRecord(id: "c1"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Nutrition Program Intake"));
    await tester.pumpAndSettle();
  });
}
