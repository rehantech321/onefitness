/// One card or bank account saved on the client's Stripe Customer, as
/// list-payment-methods returns it — display details only (brand, last 4,
/// expiry); the card itself never leaves Stripe.
class SavedPaymentMethod {
  const SavedPaymentMethod({
    required this.id,
    required this.type,
    required this.brand,
    required this.last4,
    this.expMonth,
    this.expYear,
    this.isDefault = false,
  });

  final String id;

  /// "card" or "bank".
  final String type;
  final String brand;
  final String last4;
  final int? expMonth;
  final int? expYear;

  /// The one membership renewals are charged to.
  final bool isDefault;

  bool get isCard => type == "card";

  String get label {
    final name = isCard ? _brandName(brand) : brand;
    return last4.isEmpty ? name : "$name •••• $last4";
  }

  String? get expiry => expMonth == null || expYear == null ? null : "${expMonth.toString().padLeft(2, "0")}/${expYear! % 100}";

  factory SavedPaymentMethod.fromJson(Map<String, dynamic> j) => SavedPaymentMethod(
        id: j["id"] as String,
        type: j["type"] as String? ?? "card",
        brand: j["brand"] as String? ?? "",
        last4: j["last4"] as String? ?? "",
        expMonth: (j["expMonth"] as num?)?.toInt(),
        expYear: (j["expYear"] as num?)?.toInt(),
        isDefault: j["isDefault"] as bool? ?? false,
      );

  static String _brandName(String b) => switch (b) {
        "visa" => "Visa",
        "mastercard" => "Mastercard",
        "amex" => "American Express",
        "discover" => "Discover",
        "diners" => "Diners Club",
        "jcb" => "JCB",
        "unionpay" => "UnionPay",
        _ => "Card",
      };
}
