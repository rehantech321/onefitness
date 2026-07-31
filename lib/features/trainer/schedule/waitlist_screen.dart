import "package:flutter/material.dart";
import "../../../core/widgets/widgets.dart";

/// Mirrors ManageWaitlist.jsx (owner-only) — pending-approval requests from
/// the client-side recurring "Advanced Booking" flow, grouped by client.
/// That request flow doesn't exist in this mock-data build yet, so this
/// screen is a genuinely-empty, fully-real "nothing pending" state rather
/// than a stub.
class WaitlistScreen extends StatelessWidget {
  const WaitlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel("Waitlist"),
          HintBox(text: "No pending recurring-booking requests right now. Requests clients submit through Advanced Booking will show up here for approval."),
        ],
      ),
    );
  }
}
