/// One day's habit log — mirrors habitHelpers.js `getHabitLog` shape
/// `{ date, checked, energy, motivation }`.
class HabitLogEntry {
  const HabitLogEntry({this.checked = const {}, this.energy, this.motivation});

  final Map<String, bool> checked;
  final int? energy;
  final int? motivation;

  HabitLogEntry copyWith({Map<String, bool>? checked, int? energy, int? motivation}) => HabitLogEntry(
        checked: checked ?? this.checked,
        energy: energy ?? this.energy,
        motivation: motivation ?? this.motivation,
      );
}
