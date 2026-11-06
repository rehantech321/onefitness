import "package:flutter/material.dart";
import "../../data/models/billing_address.dart";
import "../supabase/supabase_service.dart";
import "../theme/app_colors.dart";

/// Fields for a billing address. Reports every edit through [onChanged] with
/// the current address (possibly incomplete — check [BillingAddress.isComplete]).
class BillingAddressFields extends StatefulWidget {
  const BillingAddressFields({super.key, this.initial, required this.onChanged});
  final BillingAddress? initial;
  final ValueChanged<BillingAddress> onChanged;

  @override
  State<BillingAddressFields> createState() => _BillingAddressFieldsState();
}

class _BillingAddressFieldsState extends State<BillingAddressFields> {
  late final _line1 = TextEditingController(text: widget.initial?.line1);
  late final _line2 = TextEditingController(text: widget.initial?.line2);
  late final _city = TextEditingController(text: widget.initial?.city);
  late final _state = TextEditingController(text: widget.initial?.state);
  late final _zip = TextEditingController(text: widget.initial?.postalCode);

  @override
  void dispose() {
    for (final c in [_line1, _line2, _city, _state, _zip]) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() => widget.onChanged(BillingAddress(
        line1: _line1.text,
        line2: _line2.text,
        city: _city.text,
        state: _state.text.toUpperCase(),
        postalCode: _zip.text,
      ));

  InputDecoration _dec(String label) => InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder());

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _line1,
          decoration: _dec("Street address"),
          textCapitalization: TextCapitalization.words,
          keyboardType: TextInputType.streetAddress,
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _line2,
          decoration: _dec("Apt, suite (optional)"),
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _city,
          decoration: _dec("City"),
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _state,
                decoration: _dec("State"),
                textCapitalization: TextCapitalization.characters,
                maxLength: 2,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _zip,
                decoration: _dec("ZIP code"),
                keyboardType: TextInputType.number,
                onChanged: (_) => _emit(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Makes sure [clientId] has a billing address before a card is entered.
///
/// Returns the saved address straight away when there is one. Otherwise asks
/// for it in a dialog, saves it to the client's profile, and returns it — so
/// it is collected once and reused for every later purchase. Pass
/// [forceEdit] to let it be changed. Null means the dialog was dismissed (or
/// the save failed), and the caller should not open the card sheet.
Future<BillingAddress?> ensureBillingAddress(
  BuildContext context, {
  required String clientId,
  String? clientName,
  bool forceEdit = false,
}) async {
  BillingAddress? existing;
  try {
    existing = await SupabaseService.loadBillingAddress(clientId);
  } catch (_) {
    existing = null;
  }
  if (existing != null && !forceEdit) return existing;
  if (!context.mounted) return null;

  var draft = existing;
  final saved = await showDialog<BillingAddress>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(clientName == null ? "Billing address" : "$clientName's billing address"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Needed to take a card payment. It's saved to the profile for future purchases.",
                style: TextStyle(fontSize: 12, color: AppColors.mute),
              ),
              const SizedBox(height: 12),
              BillingAddressFields(initial: existing, onChanged: (a) => setState(() => draft = a)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: (draft?.isComplete ?? false) ? () => Navigator.pop(ctx, draft) : null,
            child: const Text("Save"),
          ),
        ],
      ),
    ),
  );
  if (saved == null) return null;
  try {
    await SupabaseService.saveBillingAddress(clientId, saved);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save the billing address — try again.")));
    }
    return null;
  }
  return saved;
}
