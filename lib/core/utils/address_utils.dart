/// A US street address split into the parts the location forms show
/// separately. Stored everywhere as one string ("2422 W Victory Blvd.,
/// Burbank, CA 91506") — the calendar feed, the web app and every client
/// screen read that single field — so this only exists to edit it piece by
/// piece and to fill the pieces in from a map pick.
class AddressParts {
  const AddressParts({
    this.street = "",
    this.city = "",
    this.state = "",
    this.zip = "",
  });

  final String street;
  final String city;
  final String state;
  final String zip;

  bool get isEmpty =>
      street.isEmpty && city.isEmpty && state.isEmpty && zip.isEmpty;

  /// "street, city, ST 12345", leaving out whatever is blank.
  String compose() => [
    street.trim(),
    city.trim(),
    [state.trim(), zip.trim()].where((v) => v.isNotEmpty).join(" "),
  ].where((v) => v.isNotEmpty).join(", ");

  /// Best-effort split of a saved one-line address. Anything it can't place
  /// stays in [street], so nothing typed earlier is ever lost.
  static AddressParts parse(String address) {
    final parts = address
        .split(",")
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isNotEmpty && _country.hasMatch(parts.last)) parts.removeLast();
    if (parts.isEmpty) return const AddressParts();

    var state = "";
    var zip = "";
    final last = parts.last;
    final stateZip = _stateZip.firstMatch(last);
    final zipOnly = _zip.firstMatch(last);
    if (stateZip != null) {
      state = stateZip.group(1)!.trim();
      zip = stateZip.group(2)!;
    } else if (zipOnly != null) {
      zip = zipOnly.group(0)!;
    } else if (_stateOnly.hasMatch(last)) {
      state = last;
    } else {
      return AddressParts(street: parts.join(", "));
    }
    parts.removeLast();

    // With only one part left it's the street — a city on its own with no
    // street is rarer than a street with no city typed yet.
    final city = parts.length >= 2 ? parts.removeLast() : "";
    return AddressParts(
      street: parts.join(", "),
      city: city,
      state: state,
      zip: zip,
    );
  }

  static final _country = RegExp(
    r"^(usa|us|united states( of america)?)$",
    caseSensitive: false,
  );
  static final _stateZip = RegExp(
    r"^([A-Za-z][A-Za-z .]*?)\s+(\d{5}(?:-\d{4})?)$",
  );
  static final _zip = RegExp(r"^\d{5}(?:-\d{4})?$");
  static final _stateOnly = RegExp(r"^[A-Za-z]{2}$");
}

/// "California" → "CA". Platform geocoders return the full name on Android
/// and sometimes the code on iOS; the forms always show the two-letter code.
/// Unknown names (outside the US) come back unchanged.
String stateCode(String state) {
  final s = state.trim();
  if (s.length == 2) return s.toUpperCase();
  return _usStates[s.toLowerCase()] ?? s;
}

const _usStates = {
  "alabama": "AL",
  "alaska": "AK",
  "arizona": "AZ",
  "arkansas": "AR",
  "california": "CA",
  "colorado": "CO",
  "connecticut": "CT",
  "delaware": "DE",
  "district of columbia": "DC",
  "florida": "FL",
  "georgia": "GA",
  "hawaii": "HI",
  "idaho": "ID",
  "illinois": "IL",
  "indiana": "IN",
  "iowa": "IA",
  "kansas": "KS",
  "kentucky": "KY",
  "louisiana": "LA",
  "maine": "ME",
  "maryland": "MD",
  "massachusetts": "MA",
  "michigan": "MI",
  "minnesota": "MN",
  "mississippi": "MS",
  "missouri": "MO",
  "montana": "MT",
  "nebraska": "NE",
  "nevada": "NV",
  "new hampshire": "NH",
  "new jersey": "NJ",
  "new mexico": "NM",
  "new york": "NY",
  "north carolina": "NC",
  "north dakota": "ND",
  "ohio": "OH",
  "oklahoma": "OK",
  "oregon": "OR",
  "pennsylvania": "PA",
  "rhode island": "RI",
  "south carolina": "SC",
  "south dakota": "SD",
  "tennessee": "TN",
  "texas": "TX",
  "utah": "UT",
  "vermont": "VT",
  "virginia": "VA",
  "washington": "WA",
  "west virginia": "WV",
  "wisconsin": "WI",
  "wyoming": "WY",
  "puerto rico": "PR",
};
