class HabitDef {
  const HabitDef({required this.id, required this.label, required this.emoji});
  final String id;
  final String label;
  final String emoji;
}

/// Mirrors habitHelpers.js `DEFAULT_HABITS`.
const kDefaultHabits = [
  HabitDef(id: "water", label: "Drink water", emoji: "\u{1F4A7}"),
  HabitDef(id: "sleep", label: "Get 8 hours of sleep", emoji: "\u{1F634}"),
  HabitDef(id: "meal", label: "Follow meal plan", emoji: "\u{1F957}"),
  HabitDef(id: "supps", label: "Take supplements", emoji: "\u{1F48A}"),
  HabitDef(id: "workout", label: "Complete workout", emoji: "\u{1F3CB}"),
  HabitDef(id: "stretch", label: "Stretch / mobility", emoji: "\u{1F9D8}"),
  HabitDef(id: "steps", label: "Hit daily step goal", emoji: "\u{1F45F}"),
];
