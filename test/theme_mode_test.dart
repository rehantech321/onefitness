import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:onefitness/core/theme/app_colors.dart";
import "package:onefitness/core/theme/palette_scope.dart";
import "package:onefitness/core/widgets/theme_mode_picker.dart";
import "package:onefitness/core/theme/app_theme.dart";
import "package:onefitness/core/utils/booking_utils.dart";
import "package:onefitness/core/widgets/status_dot.dart";
import "package:onefitness/data/providers/theme_mode_provider.dart";

/// Light and dark mode.
///
/// The colour tokens stopped being `static const` and became getters over a
/// swappable palette — that one change is what lets 170 screens re-theme
/// without being rewritten. These tests cover the parts that can go wrong
/// quietly: a palette that doesn't actually swap, a light palette with
/// unreadable contrast, and "match phone" resolving the wrong way.
void main() {
  // ThemeModeNotifier.set() writes the choice through SharedPreferences.
  // Without a mock, getInstance() never completes under flutter_test, so any
  // test that awaits set() hangs until the ten-minute timeout — which looks
  // exactly like an infinite rebuild loop and is nothing of the kind.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Each test installs its own palette; leave the app in its default.
  tearDown(() => AppColors.apply(AppPalette.dark));

  group("swapping the palette", () {
    test("dark is the default", () {
      AppColors.apply(AppPalette.dark);
      expect(AppColors.bg, AppPalette.dark.bg);
      expect(AppColors.palette.isDark, isTrue);
    });

    test("applying light changes every token that should change", () {
      AppColors.apply(AppPalette.dark);
      final darkBg = AppColors.bg;
      final darkTxt = AppColors.txt;
      final darkCard = AppColors.card;

      AppColors.apply(AppPalette.light);
      expect(AppColors.bg, isNot(darkBg));
      expect(AppColors.txt, isNot(darkTxt));
      expect(AppColors.card, isNot(darkCard));
      expect(AppColors.palette.isDark, isFalse);
    });

    test("apply reports whether anything changed", () {
      AppColors.apply(AppPalette.dark);
      expect(AppColors.apply(AppPalette.light), isTrue);
      expect(AppColors.apply(AppPalette.light), isFalse, reason: "same palette twice is a no-op");
    });

    test("the aliased tokens follow their source", () {
      // grn, success and calendarUpcoming are all gold by design. If one
      // stopped tracking it, a success state would go off-brand in one theme
      // only — the kind of thing nobody notices until a screenshot.
      for (final p in [AppPalette.dark, AppPalette.light]) {
        AppColors.apply(p);
        expect(AppColors.grn, AppColors.gold);
        expect(AppColors.success, AppColors.gold);
        expect(AppColors.calendarUpcoming, AppColors.gold);
      }
    });
  });

  group("the light palette is actually readable", () {
    double luminance(Color c) => c.computeLuminance();
    double contrast(Color a, Color b) {
      final la = luminance(a), lb = luminance(b);
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    test("body text on the page background clears WCAG AA", () {
      for (final p in [AppPalette.dark, AppPalette.light]) {
        expect(contrast(p.txt, p.bg), greaterThan(4.5), reason: "txt on bg, isDark=${p.isDark}");
        expect(contrast(p.txt, p.card), greaterThan(4.5), reason: "txt on card, isDark=${p.isDark}");
      }
    });

    test("muted text stays legible, not just faint", () {
      // Muted carries dates, counts and hints — it's secondary, not
      // decorative, so hold it to the large-text floor rather than nothing.
      for (final p in [AppPalette.dark, AppPalette.light]) {
        expect(contrast(p.mute, p.bg), greaterThan(3.0), reason: "mute on bg, isDark=${p.isDark}");
        expect(contrast(p.mute, p.card), greaterThan(3.0), reason: "mute on card, isDark=${p.isDark}");
      }
    });

    test("button labels are readable on the accent fill", () {
      // gold is every primary button and selected chip. In light mode it had
      // to invert to near-black — the dark theme's #D9D9D9 on white would be
      // all but invisible.
      for (final p in [AppPalette.dark, AppPalette.light]) {
        expect(contrast(p.onGold, p.gold), greaterThan(4.5), reason: "onGold on gold, isDark=${p.isDark}");
      }
    });

    test("cards are distinguishable from the page", () {
      // Dark gets this from #000 vs #161617. Light would lose it entirely if
      // both were white.
      for (final p in [AppPalette.dark, AppPalette.light]) {
        expect(p.card, isNot(p.bg), reason: "card must not equal bg, isDark=${p.isDark}");
      }
    });

    test("light really is light and dark really is dark", () {
      expect(luminance(AppPalette.light.bg), greaterThan(0.5));
      expect(luminance(AppPalette.dark.bg), lessThan(0.1));
    });
  });

  group("choosing a theme", () {
    test("explicit choices ignore the phone", () {
      AppTheme.themeFor(ThemeMode.light, Brightness.dark);
      expect(AppColors.palette.isDark, isFalse);

      AppTheme.themeFor(ThemeMode.dark, Brightness.light);
      expect(AppColors.palette.isDark, isTrue);
    });

    test("match phone follows the device", () {
      AppTheme.themeFor(ThemeMode.system, Brightness.light);
      expect(AppColors.palette.isDark, isFalse);

      AppTheme.themeFor(ThemeMode.system, Brightness.dark);
      expect(AppColors.palette.isDark, isTrue);
    });

    test("the ThemeData matches the palette it installed", () {
      // These are two separate things that both have to be right: the
      // app's own widgets read AppColors, while dialogs, SnackBars and text
      // selection come from ThemeData. If they disagreed you'd get a light
      // app with dark dialogs.
      final light = AppTheme.themeFor(ThemeMode.light, Brightness.dark);
      expect(light.scaffoldBackgroundColor, AppPalette.light.bg);
      expect(light.colorScheme.primary, AppPalette.light.gold);
      expect(light.brightness, Brightness.light);

      final dark = AppTheme.themeFor(ThemeMode.dark, Brightness.light);
      expect(dark.scaffoldBackgroundColor, AppPalette.dark.bg);
      expect(dark.brightness, Brightness.dark);
    });

    test("dialogs and sheets are themed, not left on the Material default", () {
      final light = AppTheme.themeFor(ThemeMode.light, Brightness.light);
      expect(light.dialogTheme.backgroundColor, AppPalette.light.card);
      expect(light.bottomSheetTheme.backgroundColor, AppPalette.light.card);
      expect(light.popupMenuTheme.color, AppPalette.light.card);
    });
  });

  group("the label shown in settings", () {
    test("names each mode", () {
      expect(themeModeLabel(ThemeMode.light), "Light");
      expect(themeModeLabel(ThemeMode.dark), "Dark");
      expect(themeModeLabel(ThemeMode.system), "Match phone");
    });
  });

  group("collections of colours re-theme too", () {
    test("status meta follows the palette, not the first read", () {
      // These were const and had to become something else. As a `final`
      // they'd be built once, lazily, and keep whichever palette happened
      // to be active at that moment — so a theme switch would leave client
      // status dots and flag colours stuck on the old theme.
      AppColors.apply(AppPalette.dark);
      final darkNew = kStatusMeta[ClientStatus.newClient]!.color;
      AppColors.apply(AppPalette.light);
      final lightNew = kStatusMeta[ClientStatus.newClient]!.color;
      expect(lightNew, isNot(darkNew));
      expect(lightNew, AppPalette.light.statusNew);
    });

    test("attendance options follow the palette", () {
      AppColors.apply(AppPalette.dark);
      final darkFirst = kAttendanceOptions.first.color;
      AppColors.apply(AppPalette.light);
      expect(kAttendanceOptions.first.color, isNot(darkFirst));
    });
  });

  group("the saved choice is in force on the first frame", () {
    // Cold start used to open on ThemeMode.system and correct itself a frame
    // or more later, once SharedPreferences came back. Someone whose phone is
    // light but who chose Dark got a white flash on every launch — worst on
    // the sign-in screen, which is the first thing drawn.

    test("readStored returns the stored choice", () async {
      SharedPreferences.setMockInitialValues({"themeMode": "dark"});
      expect(await ThemeModeNotifier.readStored(), ThemeMode.dark);
    });

    test("readStored returns null when nothing is stored", () async {
      SharedPreferences.setMockInitialValues({});
      expect(await ThemeModeNotifier.readStored(), isNull);
    });

    test("a seeded choice is the notifier's very first value", () {
      // No pump, no await: the value is right the instant it's read.
      final container = ProviderContainer(
        overrides: [initialThemeModeProvider.overrideWithValue(ThemeMode.dark)],
      );
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    testWidgets("the first frame paints the seeded palette", (tester) async {
      // The phone says light; the stored choice says dark. Nothing below
      // should ever paint light, not even for one frame.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialThemeModeProvider.overrideWithValue(ThemeMode.dark),
          ],
          child: PaletteScope(
            builder: (context, theme) =>
                MaterialApp(theme: theme, home: const _ConstPainter()),
          ),
        ),
      );

      expect(
        tester.widget<ColoredBox>(find.byKey(const Key("painted"))).color,
        AppPalette.dark.bg,
        reason: "cold start flashed the phone's palette before the saved one",
      );
    });

    testWidgets("with nothing stored, the phone decides", (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [initialThemeModeProvider.overrideWithValue(null)],
          child: PaletteScope(
            builder: (context, theme) =>
                MaterialApp(theme: theme, home: const _ConstPainter()),
          ),
        ),
      );

      expect(
        tester.widget<ColoredBox>(find.byKey(const Key("painted"))).color,
        AppPalette.dark.bg,
      );
    });
  });

  group("a theme change reaches the screen you're on", () {
    // The bug these cover: picking Dark repainted only the *next* screen
    // opened. AppColors' tokens are static getters, so nothing below has a
    // dependency Flutter tracks, and Element.updateChild short-circuits on
    // identical widget instances — so a rebuild of the root stopped at the
    // first `const` child, which in this app is nearly all of them.
    //
    // Every child below is deliberately `const`, because a non-const one
    // would rebuild anyway and the test would pass without the fix.

    Widget harness() => ProviderScope(
      child: PaletteScope(
        builder: (context, theme) => MaterialApp(
          theme: theme,
          home: const _ConstPainter(),
        ),
      ),
    );

    Color paintedColor(WidgetTester tester) => tester
        .widget<ColoredBox>(find.byKey(const Key("painted")))
        .color;

    testWidgets("repaints without navigating anywhere", (tester) async {
      await tester.pumpWidget(harness());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PaletteScope)),
      );

      await container.read(themeModeProvider.notifier).set(ThemeMode.light);
      await tester.pumpAndSettle();
      final light = paintedColor(tester);

      await container.read(themeModeProvider.notifier).set(ThemeMode.dark);
      await tester.pumpAndSettle();
      final dark = paintedColor(tester);

      expect(light, isNot(dark), reason: "const child kept its old palette");
      expect(light, AppPalette.light.bg);
      expect(dark, AppPalette.dark.bg);
    });

    testWidgets("keeps the state of the screen it repaints", (tester) async {
      // The reason this marks elements dirty instead of swapping a ValueKey:
      // a key change would rebuild by destroying every element below, losing
      // scroll position and any half-typed form. Switching theme mid-workout
      // must not discard an in-progress set log.
      await tester.pumpWidget(harness());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PaletteScope)),
      );

      final state = tester.state<_ConstPainterState>(
        find.byType(_ConstPainter),
      );
      state.enter("97.5");
      await tester.pump();
      final createdAt = state.createdAt;

      await container.read(themeModeProvider.notifier).set(ThemeMode.light);
      await tester.pumpAndSettle();

      expect(find.text("97.5"), findsOneWidget, reason: "screen state was lost");
      expect(
        tester.state<_ConstPainterState>(find.byType(_ConstPainter)).createdAt,
        createdAt,
        reason: "State was recreated, not rebuilt in place",
      );
    });

    testWidgets("re-selecting the same mode schedules no extra work", (tester) async {
      // AppColors.apply returns false when the palette is unchanged, which is
      // what stops the post-frame repaint from re-triggering itself forever.
      await tester.pumpWidget(harness());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PaletteScope)),
      );
      await container.read(themeModeProvider.notifier).set(ThemeMode.dark);
      await tester.pumpAndSettle();

      await container.read(themeModeProvider.notifier).set(ThemeMode.dark);
      // Would time out if each repaint dirtied the tree again.
      await tester.pumpAndSettle();
      expect(paintedColor(tester), AppPalette.dark.bg);
    });
  });

  group("the toggle in the drawer", () {
    /// The button as the drawer header holds it.
    Widget harness() => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: const [ThemeModeToggleButton()]),
        ),
      ),
    );

    testWidgets("offers all three modes, not just light and dark", (tester) async {
      await tester.pumpWidget(harness());
      await tester.tap(find.byType(ThemeModeToggleButton));
      await tester.pumpAndSettle();

      // "Match phone" is the default and the only way back to it, so a
      // toggle that dropped it would make the default unreachable.
      expect(find.text("Light"), findsOneWidget);
      expect(find.text("Dark"), findsOneWidget);
      expect(find.text("Match phone"), findsOneWidget);
    });

    testWidgets("picking a mode changes it", (tester) async {
      await tester.pumpWidget(harness());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ThemeModeToggleButton)),
      );
      expect(container.read(themeModeProvider), ThemeMode.system);

      await tester.tap(find.byType(ThemeModeToggleButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Dark"));
      await tester.pumpAndSettle();

      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    testWidgets("the icon reflects the mode in force", (tester) async {
      // The button is the only indication of the current mode once the menu
      // is shut, so a static icon would leave people guessing.
      await tester.pumpWidget(harness());
      final before = tester.widget<Icon>(
        find.descendant(
          of: find.byType(ThemeModeToggleButton),
          matching: find.byType(Icon),
        ),
      );

      await tester.tap(find.byType(ThemeModeToggleButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Light"));
      await tester.pumpAndSettle();

      final after = tester.widget<Icon>(
        find.descendant(
          of: find.byType(ThemeModeToggleButton),
          matching: find.byType(Icon),
        ),
      );
      expect(after.icon, isNot(before.icon));
    });
  });
}

/// A screen that paints from [AppColors] and holds some state.
///
/// Built as `const` wherever it's used on purpose: that is the exact shape
/// that made the original bug invisible to a root rebuild. It also keeps a
/// TextField and a creation stamp, so a test can tell a rebuild-in-place
/// from a destroy-and-recreate.
class _ConstPainter extends StatefulWidget {
  const _ConstPainter();

  @override
  State<_ConstPainter> createState() => _ConstPainterState();
}

class _ConstPainterState extends State<_ConstPainter> {
  /// Identity for this State object. Survives a rebuild; changes if the
  /// element was thrown away and a new one built in its place.
  final Object createdAt = Object();

  /// Stands in for anything a screen holds that a user would hate to lose —
  /// a typed weight, a scroll offset, a half-finished form. Deliberately not
  /// a real TextField: a focused one blinks its cursor forever, and
  /// pumpAndSettle never returns while an animation is running.
  String entered = "";

  void enter(String value) => setState(() => entered = value);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key("painted"),
      color: AppColors.bg,
      child: Center(child: Text(entered, textDirection: TextDirection.ltr)),
    );
  }
}
