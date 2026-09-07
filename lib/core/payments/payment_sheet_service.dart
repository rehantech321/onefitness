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
class PaymentSheetService {
  /// Set once per process, the first time a sheet is opened. The key comes
  /// from the backend rather than being compiled in, so rotating it or
  /// moving between test and live keys needs no app release.
  static String? _configuredKey;

  static Future<PaymentResult> purchase({
    required String planId,
    String? couponCode,
    String? targetClientId,
    String paymentMethod = "card",
    required String businessName,
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
      );
    } catch (e) {
      return PaymentResult.failed(e.toString().replaceFirst("Exception: ", ""));
    }

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

    if (_configuredKey != publishableKey) {
      Stripe.publishableKey = publishableKey;
      await Stripe.instance.applySettings();
      _configuredKey = publishableKey;
    }

    final allowed = (intent["allowedMethods"] as Map?)?.cast<String, dynamic>() ?? const {};
    final applePayAllowed = allowed["applePay"] == true;

    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          customerId: intent["customerId"] as String?,
          customerEphemeralKeySecret: intent["ephemeralKey"] as String?,
          merchantDisplayName: businessName,
          // Apple Pay is a card wallet layered on top of the sheet, so it's
          // switched on here rather than in the server's method list — and
          // only for packages, per the product-type rules.
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
