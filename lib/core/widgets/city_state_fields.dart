import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "../theme/app_colors.dart";
import "address_fields.dart" show MapPickButton;
import "map_location_picker.dart";
import "widgets.dart";

/// City and State side by side.
///
/// Both are read together to place the client: the booking screen geocodes
/// "City, State" to work out which gym is nearest them. City alone is
/// ambiguous — Burbank is in California and Illinois, Glendale in half a
/// dozen states — so the state is what makes the answer definite rather
/// than a guess.
///
/// One widget for all four places a client's location is entered (signup,
/// their own Profile Settings, a coach adding a client, a coach editing
/// one), so the field order, widths and hint text can't drift apart.
class CityStateFields extends StatelessWidget {
  const CityStateFields({
    super.key,
    required this.city,
    required this.state,
    this.onChanged,
    this.helper = "Used to show you the gym nearest you.",
    this.cityLabel = "City",
    this.stateLabel = "State",
    this.showMapButton = true,
  });

  final TextEditingController city;
  final TextEditingController state;
  final VoidCallback? onChanged;

  /// Null hides it — the coach-facing forms are already dense.
  final String? helper;
  final String cityLabel;
  final String stateLabel;

  /// "Set on map / search / use current location" — fills City and State
  /// from wherever the pin lands.
  final bool showMapButton;

  Future<void> _pickOnMap(BuildContext context) async {
    final picked = await showMapLocationPicker(
      context,
      title: "Where are you based?",
      subtitle: "Search for your address or city, drag the map, or tap the crosshair to use where you are now.",
    );
    if (picked == null || !context.mounted) return;
    final place = picked.place;
    if (place == null || (place.city.isEmpty && place.state.isEmpty)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text("Couldn't name that spot — type your city and state instead."),
      ));
      return;
    }
    if (place.city.isNotEmpty) city.text = place.city;
    if (place.state.isNotEmpty) state.text = place.state;
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // City takes the larger share: names like "North Hollywood" run
            // long, while a state is usually two characters.
            Expanded(
              flex: 3,
              child: FieldLabeled(
                label: cityLabel,
                child: AppField(kind: FieldKind.name, 
                  controller: city,
                  placeholder: "e.g. Burbank",
                  onChanged: (_) => onChanged?.call(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FieldLabeled(
                label: stateLabel,
                child: AppField(kind: FieldKind.code, 
                  controller: state,
                  placeholder: "e.g. CA",
                  // Upper-cased as typed: "ca" and "CA" geocode the same,
                  // but the profile reads better and matches how the state
                  // is shown everywhere else.
                  inputFormatters: [UpperCaseTextFormatter()],
                  onChanged: (_) => onChanged?.call(),
                ),
              ),
            ),
          ],
        ),
        if (showMapButton) ...[
          const SizedBox(height: 8),
          MapPickButton(onPressed: () => _pickOnMap(context)),
        ],
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              helper!,
              style: const TextStyle(fontSize: 11, color: AppColors.mute, height: 1.4),
            ),
          ),
      ],
    );
  }
}

/// Upper-cases a state as it's typed. Kept here rather than inline so the
/// four forms share one behaviour.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
