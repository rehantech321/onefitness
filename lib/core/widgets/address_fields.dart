import "package:flutter/material.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../theme/app_colors.dart";
import "../utils/address_utils.dart";
import "../utils/nearest_location.dart" show geocodeAddress;
import "map_location_picker.dart";
import "app_text_field.dart";
import "city_state_fields.dart" show UpperCaseTextFormatter;
import "widgets.dart";

/// Street, then City / State / ZIP on one row — edits one address that's
/// stored as a single line (see [AddressParts]).
///
/// [address] is the stored line; every edit reports the recomposed line
/// through [onChanged]. The fields keep their own state while typing (a
/// half-typed address doesn't always split back the same way), and only
/// re-read [address] when it changes from outside — a map pick, or the
/// settings reloading.
class AddressFields extends StatefulWidget {
  const AddressFields({
    super.key,
    required this.address,
    required this.onChanged,
    this.showMapButton = false,
  });

  final String address;
  final ValueChanged<String> onChanged;

  /// Adds "Set on map / search / use current location", which fills all
  /// four fields from wherever the pin lands. Off where the screen has its
  /// own map button that also keeps the pin (the gym's locations).
  final bool showMapButton;

  @override
  State<AddressFields> createState() => _AddressFieldsState();
}

class _AddressFieldsState extends State<AddressFields> {
  final _street = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _zip = TextEditingController();

  /// The line this widget last produced or was given — anything else
  /// arriving in [AddressFields.address] is an outside change.
  late String _last = widget.address;

  @override
  void initState() {
    super.initState();
    _fill(widget.address);
  }

  @override
  void didUpdateWidget(covariant AddressFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.address != _last) {
      _last = widget.address;
      _fill(widget.address);
    }
  }

  void _fill(String address) {
    final p = AddressParts.parse(address);
    _street.text = p.street;
    _city.text = p.city;
    _state.text = p.state;
    _zip.text = p.zip;
  }

  void _changed() {
    _last = AddressParts(
      street: _street.text,
      city: _city.text,
      state: _state.text,
      zip: _zip.text,
    ).compose();
    widget.onChanged(_last);
  }

  Future<void> _pickOnMap() async {
    // Start on the address already typed, when it can be placed.
    final typed = _last.trim().isEmpty ? null : await geocodeAddress(_last);
    if (!mounted) return;
    final picked = await showMapLocationPicker(
      context,
      title: "Set your address",
      subtitle: "Search for the address, drag the map onto it, or tap the crosshair to use where you are now.",
      initial: typed == null ? null : PickedPoint(lat: typed.lat, lng: typed.lng),
    );
    if (picked == null || !mounted) return;
    final place = picked.place;
    if (place == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text("Couldn't find an address at that spot — type it in instead."),
      ));
      return;
    }
    setState(() {
      _street.text = place.street;
      _city.text = place.city;
      _state.text = place.state;
      _zip.text = place.zip;
    });
    _changed();
  }

  @override
  void dispose() {
    _street.dispose();
    _city.dispose();
    _state.dispose();
    _zip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabeled(
          label: "Street address",
          child: AppField(
            kind: FieldKind.address,
            controller: _street,
            placeholder: "e.g. 2422 W Victory Blvd.",
            onChanged: (_) => _changed(),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: FieldLabeled(
                label: "City",
                child: AppField(
                  kind: FieldKind.name,
                  controller: _city,
                  placeholder: "Burbank",
                  onChanged: (_) => _changed(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FieldLabeled(
                label: "State",
                child: AppField(
                  kind: FieldKind.code,
                  controller: _state,
                  placeholder: "CA",
                  inputFormatters: [UpperCaseTextFormatter()],
                  onChanged: (_) => _changed(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: FieldLabeled(
                label: "ZIP",
                child: AppField(
                  kind: FieldKind.digits,
                  controller: _zip,
                  placeholder: "91506",
                  maxLength: 5,
                  onChanged: (_) => _changed(),
                ),
              ),
            ),
          ],
        ),
        if (widget.showMapButton) ...[
          const SizedBox(height: 10),
          MapPickButton(onPressed: _pickOnMap),
        ],
      ],
    );
  }
}

/// The outlined "Set on map / search / use current location" button, shared
/// by the address and city/state forms so they look the same.
class MapPickButton extends StatelessWidget {
  const MapPickButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.gold,
        side: const BorderSide(color: AppColors.goldDim),
        minimumSize: const Size.fromHeight(44),
      ),
      icon: const Icon(LucideIcons.map, size: 15),
      label: const Text(
        "Set on map / search / use current location",
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}
