import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/widgets/app_text_field.dart";
import "package:onefitness/core/widgets/mini_field.dart";
import "package:onefitness/data/intake_forms.dart";

/// A field that doesn't say what it's for gets the letter keyboard, so
/// entering a number means switching the keyboard by hand — and on iOS the
/// numeric plane snaps back to letters after a character, because
/// autocapitalisation and autocorrect pull it back. These tests pin the
/// keyboard and the OS assist flags for each kind of field, and check the
/// fields that take numbers actually declare it.
void main() {
  Future<TextField> pumpField(WidgetTester tester, Widget field) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: field)));
    return tester.widget<TextField>(find.byType(TextField));
  }

  group("each kind raises the right keyboard", () {
    const expected = {
      FieldKind.text: TextInputType.text,
      FieldKind.name: TextInputType.name,
      FieldKind.email: TextInputType.emailAddress,
      FieldKind.phone: TextInputType.phone,
      FieldKind.integer: TextInputType.number,
      FieldKind.digits: TextInputType.number,
      FieldKind.address: TextInputType.streetAddress,
      FieldKind.date: TextInputType.datetime,
      FieldKind.search: TextInputType.text,
      FieldKind.code: TextInputType.text,
      FieldKind.measure: TextInputType.text,
      FieldKind.multiline: TextInputType.multiline,
      FieldKind.password: TextInputType.visiblePassword,
    };

    for (final entry in expected.entries) {
      testWidgets("${entry.key.name} -> ${entry.value}", (tester) async {
        final f = await pumpField(tester, AppField(kind: entry.key));
        expect(f.keyboardType, entry.value);
      });
    }

    testWidgets("decimal gets a number pad with a decimal point", (tester) async {
      final f = await pumpField(tester, const AppField(kind: FieldKind.decimal));
      expect(f.keyboardType, const TextInputType.numberWithOptions(decimal: true));
    });

    test("every kind is covered by this test", () {
      // So a kind added later can't quietly ship with no keyboard decided.
      expect(
        {...expected.keys, FieldKind.decimal}.length,
        FieldKind.values.length,
        reason: "a FieldKind was added without a keyboard assertion here",
      );
    });
  });

  group("autocapitalisation and autocorrect", () {
    // These are the settings that make a numeric plane stay put, so they
    // matter on every kind that accepts digits.
    for (final kind in [
      FieldKind.integer,
      FieldKind.decimal,
      FieldKind.digits,
      FieldKind.measure,
      FieldKind.date,
      FieldKind.phone,
      FieldKind.email,
      FieldKind.search,
      FieldKind.password,
    ]) {
      testWidgets("${kind.name}: no autocapitalisation, no autocorrect", (tester) async {
        final f = await pumpField(tester, AppField(kind: kind));
        expect(f.textCapitalization, TextCapitalization.none);
        expect(f.autocorrect, isFalse);
      });
    }

    testWidgets("a name is word-cased but never autocorrected", (tester) async {
      final f = await pumpField(tester, const AppField(kind: FieldKind.name));
      expect(f.textCapitalization, TextCapitalization.words);
      // Surnames and gym names must not be "corrected" into other words.
      expect(f.autocorrect, isFalse);
    });

    testWidgets("a code is upper-cased as it's typed", (tester) async {
      final f = await pumpField(tester, const AppField(kind: FieldKind.code));
      expect(f.textCapitalization, TextCapitalization.characters);
    });

    testWidgets("prose gets sentence case and autocorrect", (tester) async {
      final f = await pumpField(tester, const AppField(kind: FieldKind.text));
      expect(f.textCapitalization, TextCapitalization.sentences);
      expect(f.autocorrect, isTrue);
    });

    testWidgets("a password is kept out of suggestions entirely", (tester) async {
      final f = await pumpField(tester, const AppField(kind: FieldKind.password));
      expect(f.autocorrect, isFalse);
      expect(f.enableSuggestions, isFalse);
    });

    testWidgets("obscureText alone is enough to suppress suggestions", (tester) async {
      // Several password fields pass obscureText without naming the kind.
      final f = await pumpField(tester, const AppField(obscureText: true));
      expect(f.enableSuggestions, isFalse);
      expect(f.autocorrect, isFalse);
      // And no sentence case, which would capitalise the first letter of a
      // password the person didn't type that way.
      expect(f.textCapitalization, TextCapitalization.none);
    });
  });

  group("what can be typed", () {
    Future<String> type(WidgetTester tester, FieldKind kind, String raw) async {
      final c = TextEditingController();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AppField(kind: kind, controller: c))));
      await tester.enterText(find.byType(TextField), raw);
      return c.text;
    }

    testWidgets("an integer field refuses anything but digits", (tester) async {
      expect(await type(tester, FieldKind.integer, "12abc3"), "123");
    });

    testWidgets("a decimal field keeps the decimal point", (tester) async {
      expect(await type(tester, FieldKind.decimal, "72.5kg"), "72.5");
    });

    testWidgets("a measure field leaves the unit alone", (tester) async {
      // "30s", "1 mi", "5'11" are the whole point of this kind.
      expect(await type(tester, FieldKind.measure, "30s"), "30s");
      expect(await type(tester, FieldKind.measure, "5'11"), "5'11");
    });

    testWidgets("a date field keeps its separators", (tester) async {
      expect(await type(tester, FieldKind.date, "2026-03-01"), "2026-03-01");
    });

    testWidgets("a name field is not filtered", (tester) async {
      expect(await type(tester, FieldKind.name, "O'Brien-Smith"), "O'Brien-Smith");
    });

    testWidgets("a caller's own formatters still apply on top", (tester) async {
      final c = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AppField(
            kind: FieldKind.integer,
            controller: c,
            inputFormatters: [LengthLimitingTextInputFormatter(3)],
          ),
        ),
      ));
      await tester.enterText(find.byType(TextField), "123456");
      expect(c.text, "123");
    });
  });

  group("a field given several lines is treated as prose", () {
    testWidgets("maxLines > 1 gets the newline key", (tester) async {
      final f = await pumpField(tester, const AppField(maxLines: 4));
      expect(f.keyboardType, TextInputType.multiline);
      expect(f.textCapitalization, TextCapitalization.sentences);
    });

    testWidgets("minLines alone is enough", (tester) async {
      final f = await pumpField(tester, const AppField(minLines: 2, maxLines: 6));
      expect(f.keyboardType, TextInputType.multiline);
    });

    testWidgets("but a declared kind is not overridden", (tester) async {
      // A multi-line address box is still an address.
      final f = await pumpField(tester, const AppField(kind: FieldKind.address, maxLines: 3));
      expect(f.keyboardType, TextInputType.streetAddress);
    });
  });

  group("an explicit keyboardType still wins", () {
    testWidgets("over the one the kind would choose", (tester) async {
      final f = await pumpField(
        tester,
        const AppField(kind: FieldKind.text, keyboardType: TextInputType.url),
      );
      expect(f.keyboardType, TextInputType.url);
    });

    // Many fields pass a keyboard directly and name no kind. They must not
    // pick up the prose defaults: sentence capitalisation on a number pad
    // is the exact combination that snaps iOS back to the letters plane.
    for (final t in [TextInputType.number, TextInputType.phone, TextInputType.emailAddress]) {
      testWidgets("$t gets no capitalisation and no autocorrect", (tester) async {
        final f = await pumpField(tester, AppField(keyboardType: t));
        expect(f.textCapitalization, TextCapitalization.none);
        expect(f.autocorrect, isFalse);
      });
    }

    testWidgets("an explicit number keyboard does not start filtering characters", (tester) async {
      // A price field passing TextInputType.number still holds "12.50";
      // inferring a kind from the keyboard would have eaten the point.
      final c = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AppField(keyboardType: TextInputType.number, controller: c)),
      ));
      await tester.enterText(find.byType(TextField), "12.50");
      expect(c.text, "12.50");
    });

    testWidgets("an explicit multiline keyboard keeps prose assists", (tester) async {
      final f = await pumpField(tester, const AppField(keyboardType: TextInputType.multiline));
      expect(f.textCapitalization, TextCapitalization.sentences);
      expect(f.autocorrect, isTrue);
    });
  });

  group("MiniField", () {
    // Sets, reps, calories, macros, dollar minimums — these are the boxes
    // the complaint was really about.
    testWidgets("defaults to a number pad", (tester) async {
      final f = await pumpField(
        tester,
        MiniField(label: "Calories", value: "", onChange: (_) {}),
      );
      expect(f.keyboardType, const TextInputType.numberWithOptions(decimal: true));
      expect(f.textCapitalization, TextCapitalization.none);
      expect(f.autocorrect, isFalse);
    });

    testWidgets("whole-number boxes refuse a decimal point", (tester) async {
      var typed = "";
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MiniField(
            label: "Sets",
            value: "",
            kind: FieldKind.integer,
            onChange: (v) => typed = v,
          ),
        ),
      ));
      await tester.enterText(find.byType(TextField), "3.5");
      expect(typed, "35");
    });

    testWidgets("a measure box keeps its unit", (tester) async {
      var typed = "";
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MiniField(
            label: "Rest",
            value: "",
            kind: FieldKind.measure,
            onChange: (v) => typed = v,
          ),
        ),
      ));
      await tester.enterText(find.byType(TextField), "90s");
      expect(typed, "90s");
    });
  });

  group("intake questions declare what they take", () {
    // Age, weight and a phone number were all plain "text", so a client
    // filling in the assessment had to switch the keyboard for every one.
    final byId = {
      for (final form in kIntakeForms)
        for (final a in form.assessments)
          if (a.schema != null)
            for (final s in a.schema!.sections)
              for (final q in s.questions) q.id: q,
    };

    void expectKind(String id, FieldKind kind) {
      final q = byId[id];
      expect(q, isNotNull, reason: "no intake question with id '$id'");
      expect(q!.inputKind, kind, reason: "question '${q.label}'");
    }

    test("ages and counts take whole numbers", () {
      expectKind("age", FieldKind.integer);
      expectKind("daysPerWeek", FieldKind.integer);
      expectKind("mealsPerDay", FieldKind.integer);
    });

    test("weights take a decimal", () {
      expectKind("weight", FieldKind.decimal);
      expectKind("goalWeight", FieldKind.decimal);
      expectKind("sleep", FieldKind.decimal);
    });

    test("height keeps letters and punctuation, for 5'11", () {
      expectKind("height", FieldKind.measure);
    });

    test("the emergency contact's phone gets a phone pad", () {
      expectKind("ecPhone", FieldKind.phone);
    });

    test("names are word-cased", () {
      expectKind("fullName", FieldKind.name);
      expectKind("ecName", FieldKind.name);
    });

    test("prose questions are left alone", () {
      expect(byId["medications"]!.inputKind, isNull);
      expect(byId["supplements"]!.inputKind, isNull);
    });

    test("no question asks for a keyboard that filters out its own answer", () {
      // A digits-only kind on a question whose label implies units or
      // punctuation would silently eat what the client typed.
      for (final q in byId.values) {
        if (q.inputKind == FieldKind.integer || q.inputKind == FieldKind.decimal) {
          expect(
            RegExp(r"feet|inches|ft|'|\bheight\b", caseSensitive: false).hasMatch(q.label),
            isFalse,
            reason: "'${q.label}' is numeric-only but reads like it wants units",
          );
        }
      }
    });
  });
}
