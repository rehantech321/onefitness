/// A client's billing address, stored on `clients.billing_address`.
class BillingAddress {
  const BillingAddress({
    required this.line1,
    this.line2 = "",
    required this.city,
    required this.state,
    required this.postalCode,
    this.country = "US",
  });

  final String line1;
  final String line2;
  final String city;
  final String state;
  final String postalCode;
  final String country;

  /// Enough for Stripe to accept it as a billing address.
  bool get isComplete =>
      line1.trim().isNotEmpty && city.trim().isNotEmpty && state.trim().isNotEmpty && postalCode.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        "line1": line1.trim(),
        "line2": line2.trim(),
        "city": city.trim(),
        "state": state.trim(),
        "postal_code": postalCode.trim(),
        "country": country,
      };

  static BillingAddress? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final a = BillingAddress(
      line1: raw["line1"]?.toString() ?? "",
      line2: raw["line2"]?.toString() ?? "",
      city: raw["city"]?.toString() ?? "",
      state: raw["state"]?.toString() ?? "",
      postalCode: raw["postal_code"]?.toString() ?? "",
      country: raw["country"]?.toString() ?? "US",
    );
    return a.isComplete ? a : null;
  }
}
