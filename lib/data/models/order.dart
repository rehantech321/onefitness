/// A merchandise order — what staff fulfil and the buyer tracks. Distinct
/// from the `charges` ledger entry the same purchase writes: that records
/// the money, this records the thing being handed over.
class Order {
  const Order({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.productId,
    required this.productName,
    required this.status,
    this.size,
    this.quantity = 1,
    this.amountCents = 0,
    this.createdAt,
  });

  final String id;
  final String clientId;
  final String clientName;
  final String productId;
  final String productName;
  final String? size;
  final int quantity;
  final int amountCents;

  /// paid | preparing | ready | completed | cancelled
  final String status;
  final DateTime? createdAt;

  bool get isOpen => status != "completed" && status != "cancelled";
}

/// The lifecycle, in order. Kept as a list rather than scattered string
/// literals so the admin picker and the client's progress display can't
/// disagree about what the stages are or what order they come in.
const kOrderStatuses = ["paid", "preparing", "ready", "completed"];

String orderStatusLabel(String status) => switch (status) {
  "paid" => "Paid",
  "preparing" => "Preparing",
  "ready" => "Ready for pickup",
  "completed" => "Collected",
  "cancelled" => "Cancelled",
  _ => status,
};

/// What the buyer is told, which is not the same as the internal label —
/// "Paid" states a fact they already know, whereas what they actually want
/// is what happens next.
String orderStatusBlurb(String status) => switch (status) {
  "paid" => "We've got your order and will start preparing it shortly.",
  "preparing" => "Your order is being put together.",
  "ready" => "Ready to collect at the gym.",
  "completed" => "Collected — enjoy!",
  "cancelled" => "This order was cancelled.",
  _ => "",
};
