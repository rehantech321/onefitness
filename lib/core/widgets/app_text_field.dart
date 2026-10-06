import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "../theme/app_colors.dart";

/// What a field is *for*, which decides the keyboard it raises and how the
/// OS treats what's typed into it.
///
/// This exists because a field with no declared type gets the plain
/// alphabetic keyboard, so entering a number means switching the keyboard
/// by hand — and on iOS the numeric plane snaps straight back to letters
/// after a character or two, because autocapitalisation and autocorrect
/// pull it back. Typing a weight or a phone number became a fight. Naming
/// the kind once, here, is what stops that: a number field raises a number
/// pad, so there is nothing to switch.
///
/// The kinds that allow letters alongside digits ([measure], [code]) can't
/// use a number pad, so they instead turn autocorrect and autocapitalisation
/// off, which is what makes the numeric plane stay put.
enum FieldKind {
  /// Ordinary prose — a note, a description. Sentence case, autocorrect on.
  text,

  /// A person's or place's name. Word case, autocorrect off so surnames
  /// and gym names aren't "corrected" into something else.
  name,

  email,
  phone,

  /// Whole numbers only: sets, reps, age, days per week.
  integer,

  /// Numbers that can have a fractional part: weight, money, macros.
  decimal,

  /// Digits only and nothing else: ZIP, verification code.
  digits,

  /// A short identifier typed in capitals, e.g. a coupon code or a state
  /// abbreviation. Letters allowed, so no number pad.
  code,

  /// A search box. No autocorrect or capitalisation getting in the way.
  search,

  /// A street address. Word case, and the platform's address keyboard.
  address,

  /// A date typed by hand, e.g. YYYY-MM-DD. Needs digits and separators
  /// together, so it gets the numbers-and-punctuation keyboard rather than
  /// a digits-only pad that would make the dashes untypable.
  date,

  /// An amount with a unit, where letters are part of the answer —
  /// "30s", "1 mi", "135 lbs", "5'11". Letters stay available.
  measure,

  /// Free text over several lines.
  multiline,

  /// A password or passphrase. Never autocorrected, never suggested, and
  /// kept out of the keyboard's learned-words store.
  password,
}

/// The keyboard each kind raises. Null means the platform default.
TextInputType? keyboardForKind(FieldKind kind) => switch (kind) {
      FieldKind.email => TextInputType.emailAddress,
      FieldKind.phone => TextInputType.phone,
      FieldKind.integer || FieldKind.digits => TextInputType.number,
      FieldKind.decimal => const TextInputType.numberWithOptions(decimal: true),
      FieldKind.multiline => TextInputType.multiline,
      FieldKind.name => TextInputType.name,
      FieldKind.address => TextInputType.streetAddress,
      FieldKind.date => TextInputType.datetime,
      FieldKind.password => TextInputType.visiblePassword,
      FieldKind.text || FieldKind.code || FieldKind.search || FieldKind.measure => TextInputType.text,
    };

TextCapitalization capitalizationForKind(FieldKind kind) => switch (kind) {
      FieldKind.name || FieldKind.address => TextCapitalization.words,
      FieldKind.code => TextCapitalization.characters,
      FieldKind.text || FieldKind.multiline => TextCapitalization.sentences,
      // Everything else: none. On a field that accepts digits this matters
      // for more than tidiness — autocapitalisation is what yanks iOS back
      // to the letters plane mid-entry.
      _ => TextCapitalization.none,
    };

bool autocorrectForKind(FieldKind kind) => switch (kind) {
      FieldKind.text || FieldKind.multiline => true,
      _ => false,
    };

/// Only what the field can actually hold. Deliberately absent for [measure]
/// and [code], where letters are legitimate.
List<TextInputFormatter> formattersForKind(FieldKind kind) => switch (kind) {
      FieldKind.integer || FieldKind.digits => [FilteringTextInputFormatter.digitsOnly],
      // Digits and a decimal point. A character filter, so it can't police
      // how many dots there are — every reader of these values parses with
      // tryParse and falls back, so a stray second dot is harmless.
      FieldKind.decimal => [FilteringTextInputFormatter.allow(RegExp(r"[0-9.]"))],
      _ => const [],
    };

/// Capitalisation and autocorrect for a field that supplies its own
/// [AppField.keyboardType] rather than naming a kind.
///
/// Inferred from the keyboard that will actually appear, because a number,
/// phone or email pad combined with sentence capitalisation is precisely
/// the combination that snaps iOS back to the letters plane — so falling
/// back to the prose defaults here would reintroduce the bug on the fields
/// that were already declaring a numeric keyboard.
///
/// Only the assists are inferred, never the character filters: a field that
/// asks for a number keyboard may still legitimately hold "12.50" or
/// "+1 323", so what it accepts is left exactly as it was.
({TextCapitalization capitalization, bool autocorrect}) _assistsForKeyboard(TextInputType t) {
  if (t == TextInputType.text || t == TextInputType.multiline) {
    return (capitalization: TextCapitalization.sentences, autocorrect: true);
  }
  if (t == TextInputType.name) {
    return (capitalization: TextCapitalization.words, autocorrect: false);
  }
  return (capitalization: TextCapitalization.none, autocorrect: false);
}

/// Mirrors FormPrimitives.jsx `Field` — dark bordered text input.
class AppField extends StatelessWidget {
  const AppField({
    super.key,
    this.controller,
    this.placeholder,
    this.obscureText = false,
    this.kind = FieldKind.text,
    this.keyboardType,
    this.onChanged,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.textCapitalization,
    this.autocorrect,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final bool obscureText;

  /// What this field is for — see [FieldKind]. Drives the keyboard, the
  /// capitalisation and what characters are accepted.
  final FieldKind kind;

  /// Overrides the keyboard [kind] would choose. Rarely needed.
  final TextInputType? keyboardType;

  final ValueChanged<String>? onChanged;
  final int? minLines;
  final int? maxLines;
  final int? maxLength;

  /// e.g. upper-casing a state code as it's typed. Applied on top of
  /// whatever [kind] already restricts.
  final List<TextInputFormatter>? inputFormatters;

  /// Overrides for the rare field that doesn't fit its kind.
  final TextCapitalization? textCapitalization;
  final bool? autocorrect;

  /// e.g. a Search key on a search box. Single-line fields default to Done.
  final TextInputAction? textInputAction;

  /// Runs on the keyboard's action key, after the keyboard closes.
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final multiline = (maxLines ?? 1) != 1 || minLines != null;
    final singleLine = !multiline;
    // A field given several lines is prose, whatever kind it claims — it
    // needs the newline key.
    final effectiveKind = multiline && kind == FieldKind.text ? FieldKind.multiline : kind;
    final isPassword = obscureText || effectiveKind == FieldKind.password;

    // A caller that named no kind but did pass a keyboard gets its assists
    // from that keyboard rather than from the prose defaults.
    final declaredKind = kind != FieldKind.text;
    var assists = keyboardType != null && !declaredKind
        ? _assistsForKeyboard(keyboardType!)
        : (capitalization: capitalizationForKind(effectiveKind), autocorrect: autocorrectForKind(effectiveKind));

    // Several password fields say only `obscureText: true`. They must not
    // inherit sentence case, which would capitalise the first letter of a
    // password the person did not type that way.
    if (isPassword) {
      assists = (capitalization: TextCapitalization.none, autocorrect: false);
    }

    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType ?? keyboardForKind(effectiveKind),
      textCapitalization: textCapitalization ?? assists.capitalization,
      autocorrect: autocorrect ?? (isPassword ? false : assists.autocorrect),
      enableSuggestions: !isPassword && assists.autocorrect,
      onChanged: onChanged,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters: [...formattersForKind(effectiveKind), ...?inputFormatters],
      // Ways out of the keyboard, since a phone/number pad has no return
      // key on iOS: tapping anywhere outside the field closes it, and so
      // does the keyboard's own Done/return key on a single-line field.
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      textInputAction: textInputAction ?? (singleLine ? TextInputAction.done : null),
      onSubmitted: singleLine || onSubmitted != null
          ? (v) {
              FocusManager.instance.primaryFocus?.unfocus();
              onSubmitted?.call(v);
            }
          : null,
      buildCounter: maxLength == null ? null : (context, {required currentLength, required isFocused, maxLength}) => null,
      style: const TextStyle(color: AppColors.txt, fontSize: 14),
      cursorColor: AppColors.gold,
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: const TextStyle(color: AppColors.mute, fontSize: 14),
        filled: true,
        fillColor: AppColors.bg,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
      ),
    );
  }
}

/// Mirrors FormPrimitives.jsx `FieldLabeled` — small muted label above a field.
class FieldLabeled extends StatelessWidget {
  const FieldLabeled({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.mute, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}
