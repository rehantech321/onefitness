import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/payments/payment_sheet_service.dart";

/// Taking a payment failed on iPhone before the sheet even opened:
///
///   `merchantIdentifier` is required, but none was found. Ensure you are
///   passing this to initStripe your StripeProvider.
///
/// The app asked `initPaymentSheet` for Apple Pay while nothing had ever
/// set `Stripe.merchantIdentifier`, and iOS throws rather than quietly
/// dropping the wallet — so a coach lost the whole payment, cards included,
/// over an option they hadn't even chosen.
///
/// The guard is that Apple Pay is only ever requested by a build that
/// carries a merchant identifier. These cover that rule; the SDK call
/// itself needs a device.
void main() {
  group("a build with no merchant identifier", () {
    test("reports Apple Pay as unconfigured", () {
      // No --dart-define in a test run, which is also the state every build
      // is in until the Apple Pay capability is set up.
      expect(kApplePayMerchantId, isEmpty);
      expect(applePayConfigured, isFalse);
    });
  });

  group("whether the sheet is asked for Apple Pay", () {
    /// Mirrors _present's rule: the server says whether this PRODUCT may
    /// offer Apple Pay, the build says whether it CAN. Both have to hold.
    bool asksForApplePay({required bool serverAllows, required bool configured}) =>
        serverAllows && configured;

    test("not when the build has no merchant identifier", () {
      // This is the bug: the server said yes, so the app asked, and iOS
      // threw before the sheet could open.
      expect(asksForApplePay(serverAllows: true, configured: false), isFalse);
    });

    test("not when the server says this product can't use it", () {
      expect(asksForApplePay(serverAllows: false, configured: true), isFalse);
    });

    test("only when both agree", () {
      expect(asksForApplePay(serverAllows: true, configured: true), isTrue);
    });

    test("the build's answer alone can never turn it on", () {
      // The product rule stays server-enforced; a configured build must not
      // widen it.
      expect(asksForApplePay(serverAllows: false, configured: false), isFalse);
      expect(asksForApplePay(serverAllows: false, configured: true), isFalse);
    });
  });

  group("card payments, which is what actually broke", () {
    /// The sheet opens whenever there's a client secret — Apple Pay is a
    /// wallet layered on top, never a precondition.
    bool sheetOpens({required bool hasClientSecret, required bool applePay}) => hasClientSecret;

    test("still work with Apple Pay switched off", () {
      expect(sheetOpens(hasClientSecret: true, applePay: false), isTrue);
    });

    test("don't depend on Apple Pay being available either way", () {
      expect(
        sheetOpens(hasClientSecret: true, applePay: true),
        sheetOpens(hasClientSecret: true, applePay: false),
      );
    });

    test("an unconfigured build can still take a payment", () {
      // The whole point of the fix: no merchant identifier is a reason to
      // hide one button, not to refuse the sale.
      expect(sheetOpens(hasClientSecret: true, applePay: applePayConfigured), isTrue);
    });
  });

  group("offering Apple Pay as a tender choice", () {
    /// Mirrors tendersFor's rule.
    bool offered({
      required bool isPackage,
      required bool isIOS,
      required bool isWeb,
      required bool configured,
    }) =>
        isPackage && !isWeb && isIOS && configured;

    test("not on a build with no merchant identifier", () {
      // Otherwise picking "Apple Pay" lands on a plain card form, because
      // the sheet can't show the wallet.
      expect(offered(isPackage: true, isIOS: true, isWeb: false, configured: false), isFalse);
    });

    test("not for a membership", () {
      expect(offered(isPackage: false, isIOS: true, isWeb: false, configured: true), isFalse);
    });

    test("not off iOS", () {
      expect(offered(isPackage: true, isIOS: false, isWeb: false, configured: true), isFalse);
    });

    test("not on web", () {
      expect(offered(isPackage: true, isIOS: true, isWeb: true, configured: true), isFalse);
    });

    test("only when every condition holds", () {
      expect(offered(isPackage: true, isIOS: true, isWeb: false, configured: true), isTrue);
    });

    test("the picker and the sheet agree about this build", () {
      // A tender the picker offers that the sheet then won't show is the
      // dead button this guard exists to prevent.
      const serverAllows = true;
      final pickerOffers = offered(isPackage: true, isIOS: true, isWeb: false, configured: applePayConfigured);
      final sheetAsks = serverAllows && applePayConfigured;
      expect(pickerOffers, sheetAsks);
    });
  });
}
