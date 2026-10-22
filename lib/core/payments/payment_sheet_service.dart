import "package:flutter/foundation.dart" show kIsWeb;
import "package:flutter_stripe/flutter_stripe.dart";
import "../supabase/supabase_service.dart";

/// Result of an in-app purchase attempt. [cancelled] is separated from
/// [error] on purpose: backing out of the sheet is a normal thing to do and
/// must not be reported as a failure.
class PaymentResult {
  const PaymentResult._({this.cancelled = false, this.error, this.noPaymentNeeded = false});

  const PaymentResult.success() : this._();
  const PaymentResult.cancelled() : this._(cancelled: true);
  const PaymentResult.failed(String message) : this._(error: message);

  /// The purchase went through with nothing to collect right now — a
  /// future-dated billing anchor can make the first invoice $0.
  const PaymentResult.nothingDue() : this._(noPaymentNeeded: true);

  final bool cancelled;
  final String? error;
  final bool noPaymentNeeded;

  bool get ok => error == null && !cancelled;
}

/// Runs a purchase entirely inside the app using Stripe's native Payment
/// Sheet — no browser, no hosted page, no redirect back.
///
/// Card data is collected by Stripe's own UI and sent directly to Stripe
/// against the PaymentIntent's client secret; it never reaches this app or
/// our backend, and saved cards are Stripe Customer/PaymentMethod objects.
/// That's what keeps the whole thing out of PCI scope.
///
/// Which tender types appear is decided per product type by the server (see
/// create-payment-intent): memberships get card + ACH, packages additionally
/// get Apple Pay. Cash is not a Stripe method and is handled separately.
/// The Apple Pay merchant identifier this build is entitled to use, or ""
/// when Apple Pay isn't set up.
///
/// Unlike the publishable key this CANNOT come from the server: it has to
/// match the `com.apple.developer.in-app-payments` entitlement compiled
/// into the binary, so a value the app wasn't signed for is worse than no
/// value at all. Supply it at build time:
///
///   flutter build ipa --dart-define=APPLE_PAY_MERCHANT_ID=merchant.com.onefitness.onefitness
///
/// Turning Apple Pay on takes three things, all of them outside this file:
///   1. A Merchant ID registered at developer.apple.com, and Apple Pay
///      enabled for it on the Stripe dashboard.
///   2. The Apple Pay capability added to the Runner target in Xcode, which
///      writes that same id into ios/Runner/Runner.entitlements.
///   3. This define, set to the same id, at build time.
///
/// Until all three are done this stays empty and the sheet offers cards and
/// ACH only — which is what it did anyway, since an unentitled Apple Pay
/// request can't succeed.
const kApplePayMerchantId = String.fromEnvironment("APPLE_PAY_MERCHANT_ID");

/// Whether this build can offer Apple Pay at all.
///
/// Asking the sheet for Apple Pay without a merchant identifier doesn't
/// just drop the Apple Pay button — iOS throws out of `initPaymentSheet`
/// before the sheet opens, so the whole payment dies, cards included:
///
///   `merchantIdentifier` is required, but none was found. Ensure you are
///   passing this to initStripe your StripeProvider.
///
/// which is what a coach saw instead of a "Take payment" sheet. Anything
/// that offers Apple Pay has to check this first.
bool get applePayConfigured => kApplePayMerchantId.isNotEmpty;

class PaymentSheetService {
  /// Set once per process, the first time a sheet is opened. The key comes
  /// from the backend rather than being compiled in, so rotating it or
  /// moving between test and live keys needs no app release.
  static String? _configuredKey;

  /// Points the SDK at the right account, once per key.
  ///
  /// The merchant identifier has to be set BEFORE applySettings(), and both
  /// sheet entry points go through here so neither can configure the SDK
  /// differently from the other.
  static Future<void> _configureStripe(String publishableKey) async {
    if (_configuredKey == publishableKey) return;
    Stripe.publishableKey = publishableKey;
    if (applePayConfigured) Stripe.merchantIdentifier = kApplePayMerchantId;
    await Stripe.instance.applySettings();
    _configuredKey = publishableKey;
  }

  /// Merchandise checkout. Same sheet and the same PCI posture as [purchase];
  /// it just resolves against the product catalogue instead of plans, and the
  /// server checks stock before taking anything.
  static Future<PaymentResult> purchaseProduct({
    required String productId,
    required String size,
    int quantity = 1,
    required String businessName,
  }) async {
    if (kIsWeb) {
      return const PaymentResult.failed("In-app payment isn't available on web yet.");
    }
    final Map<String, dynamic> intent;
    try {
      intent = await SupabaseService.createProductPayment(
        productId: productId,
        size: size,
        quantity: quantity,
      );
    } catch (e) {
      return PaymentResult.failed(e.toString().replaceFirst("Exception: ", ""));
    }
    return _present(intent, businessName);
  }

  /// Saving a card without buying anything — Profile Settings → Payment
  /// Details → "Add card". Same sheet, in setup mode: the card is attached
  /// to the client's Stripe Customer for later charges (renewals, a
  /// cancellation fee) and nothing is charged now.
  static Future<PaymentResult> addPaymentMethod({required String businessName}) async {
    if (kIsWeb) {
      return const PaymentResult.failed("Adding a card isn't available on web yet.");
    }
    final Map<String, dynamic> setup;
    try {
      setup = await SupabaseService.createSetupIntent();
    } catch (e) {
      return PaymentResult.failed(e.toString().replaceFirst("Exception: ", ""));
    }

    final clientSecret = setup["setupIntentClientSecret"] as String?;
    final publishableKey = setup["publishableKey"] as String?;
    if (clientSecret == null || clientSecret.isEmpty) {
      return const PaymentResult.failed("Couldn't start — please try again.");
    }
    if (publishableKey == null || publishableKey.isEmpty) {
      return const PaymentResult.failed(
        "Payments aren't configured yet — the Stripe publishable key is missing on the server.",
      );
    }
    await _configureStripe(publishableKey);

    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          setupIntentClientSecret: clientSecret,
          customerId: setup["customerId"] as String?,
          customerEphemeralKeySecret: setup["ephemeralKey"] as String?,
          merchantDisplayName: businessName,
          allowsDelayedPaymentMethods: true,
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      return const PaymentResult.success();
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) return const PaymentResult.cancelled();
      return PaymentResult.failed(e.error.localizedMessage ?? e.error.message ?? "Couldn't save that card.");
    } catch (e) {
      return PaymentResult.failed(e.toString().replaceFirst("Exception: ", ""));
    }
  }

  static Future<PaymentResult> purchase({
    required String planId,
    String? couponCode,
    String? targetClientId,
    String paymentMethod = "card",
    required String businessName,
    int? priceOverrideCents,
    String? accessExpiresAt,
  }) async {
    // The native sheet is iOS/Android only. Web would need Stripe Elements,
    // which this app doesn't ship — failing loudly beats silently doing
    // nothing on a platform where the sheet can't appear.
    if (kIsWeb) {
      return const PaymentResult.failed("In-app payment isn't available on web yet.");
    }

    final Map<String, dynamic> intent;
    try {
      intent = await SupabaseService.createPaymentIntent(
        planId: planId,
        couponCode: couponCode,
        targetClientId: targetClientId,
        paymentMethod: paymentMethod,
        priceOverrideCents: priceOverrideCents,
        accessExpiresAt: accessExpiresAt,
      );
    } catch (e) {
      return PaymentResult.failed(e.toString().replaceFirst("Exception: ", ""));
    }

    return _present(intent, businessName);
  }

  /// Everything from "we have an intent" to "the sheet closed" — shared by
  /// the plan and product flows so the two can't drift apart on Apple Pay
  /// handling, key configuration or cancellation semantics.
  static Future<PaymentResult> _present(Map<String, dynamic> intent, String businessName) async {
    if (intent["requiresPayment"] == false) return const PaymentResult.nothingDue();

    final clientSecret = intent["clientSecret"] as String?;
    final publishableKey = intent["publishableKey"] as String?;
    if (clientSecret == null || clientSecret.isEmpty) {
      return const PaymentResult.failed("Couldn't start the payment — please try again.");
    }
    if (publishableKey == null || publishableKey.isEmpty) {
      return const PaymentResult.failed(
        "Payments aren't configured yet — the Stripe publishable key is missing on the server.",
      );
    }

    await _configureStripe(publishableKey);

    final allowed = (intent["allowedMethods"] as Map?)?.cast<String, dynamic>() ?? const {};
    // The server's flag says whether this PRODUCT may offer Apple Pay;
    // [applePayConfigured] says whether this BUILD can. Both must hold.
    final applePayAllowed = allowed["applePay"] == true && applePayConfigured;

    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          customerId: intent["customerId"] as String?,
          customerEphemeralKeySecret: intent["ephemeralKey"] as String?,
          merchantDisplayName: businessName,
          // Apple Pay is a card wallet layered on top of the sheet, so it's
          // switched on here rather than in the server's method list — and
          // only for packages, per the product-type rules, and only when
          // this build carries a merchant identifier.
          applePay: applePayAllowed
              ? const PaymentSheetApplePay(merchantCountryCode: "US")
              : null,
          // Saved cards come from the Customer above, so returning clients
          // can pay without re-entering anything.
          allowsDelayedPaymentMethods: true,
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      return const PaymentResult.success();
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) return const PaymentResult.cancelled();
      return PaymentResult.failed(e.error.localizedMessage ?? e.error.message ?? "Payment failed.");
    } catch (e) {
      return PaymentResult.failed(e.toString().replaceFirst("Exception: ", ""));
    }
  }
}
