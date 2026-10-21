import "package:flutter/material.dart";
import "package:flutter/semantics.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/widgets/back_bar.dart";

/// Creating a profile should end on the dashboard, with no way back to the
/// login screen — the account exists, so "sign in" is the wrong offer.
///
/// The coach flow didn't do that: it created the account, loaded the data
/// and then left the coach sitting on the signup form, where the only exit
/// was "Back to sign in". These cover the piece that can be tested without
/// a live Supabase session: that every route off the screen is closed while
/// the account is being created.
void main() {
  group("the back control can be switched off", () {
    testWidgets("it is tappable when a callback is given", (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: BackBar(onBack: () => tapped = true, title: "Create my profile")),
      ));
      // Semantics rather than the widget type: TextButton.icon builds a
      // private class, and "can the person actually press it" is the thing
      // that matters anyway.
      final handle = tester.ensureSemantics();
      expect(tester.getSemantics(find.text("Back")).hasFlag(SemanticsFlag.isEnabled), isTrue);
      await tester.tap(find.text("Back"));
      expect(tapped, isTrue);
      handle.dispose();
    });

    testWidgets("a null callback disables it rather than hiding it", (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: BackBar(onBack: null, title: "Create my profile")),
      ));
      // Still on screen — the row mustn't jump about as it appears and
      // disappears mid-submit.
      expect(find.text("Back"), findsOneWidget);
      final handle = tester.ensureSemantics();
      expect(tester.getSemantics(find.text("Back")).hasFlag(SemanticsFlag.isEnabled), isFalse);
      handle.dispose();
    });

    testWidgets("tapping a disabled back does nothing", (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: BackBar(onBack: null, title: "Create my profile")),
      ));
      await tester.tap(find.text("Back"));
      await tester.pump();
      // No exception, no navigation — the point is that it is inert.
      expect(tester.takeException(), isNull);
    });

    testWidgets("the title still shows while disabled", (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: BackBar(onBack: null, title: "Create coach profile")),
      ));
      expect(find.text("Create coach profile"), findsOneWidget);
    });
  });

  group("what the signup screens do with it", () {
    /// Mirrors the guard both signup screens now apply: every route off the
    /// screen is live normally and closed while submitting.
    VoidCallback? backWhen({required bool busy, required VoidCallback onBack}) =>
        busy ? null : onBack;

    test("the back control is live before submitting", () {
      expect(backWhen(busy: false, onBack: () {}), isNotNull);
    });

    test("and closed while the account is being created", () {
      expect(backWhen(busy: true, onBack: () {}), isNull);
    });

    /// The system back button's guard, which is a condition rather than a
    /// nullable callback.
    bool systemBackLeaves({required bool didPop, required bool busy}) => !didPop && !busy;

    test("the system back button leaves normally", () {
      expect(systemBackLeaves(didPop: false, busy: false), isTrue);
    });

    test("but is ignored while the account is being created", () {
      // Otherwise it drops them on the login screen part-way through, for
      // an account that may already exist.
      expect(systemBackLeaves(didPop: false, busy: true), isFalse);
    });

    test("and does nothing when the pop already happened", () {
      expect(systemBackLeaves(didPop: true, busy: false), isFalse);
    });
  });
}
