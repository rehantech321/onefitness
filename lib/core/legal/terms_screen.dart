import "package:flutter/material.dart";
import "../theme/app_colors.dart";
import "../widgets/widgets.dart";
import "terms_text.dart";

/// The full Terms of Use, readable on its own. Reached from the signup
/// screen's "Terms of Use" link, from the re-acceptance gate, and from
/// Profile Settings so it stays available after signup.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: BackBar(onBack: onBack, title: "Terms of Use"),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "Effective $kTermsEffectiveDate",
                        style: TextStyle(fontSize: 11, color: AppColors.mute),
                      ),
                      SizedBox(height: 14),
                      Text(
                        kTermsOfUse,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.txt,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "I agree to the Terms of Use" / "I am 18 or older" rows used by the
/// signup screens and the re-acceptance gate. A single widget so both
/// consent gates look and behave identically wherever they appear.
class ConsentCheckbox extends StatelessWidget {
  const ConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.child,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A 24px box inside a 44px row — comfortably tappable, and the
            // whole row is the target, not just the box.
            SizedBox(
              width: 26,
              height: 26,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: AppColors.gold,
                checkColor: Colors.white,
                side: const BorderSide(color: AppColors.line, width: 1.5),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
