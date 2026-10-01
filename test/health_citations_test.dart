import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/legal/health_sources.dart";

/// App Review rejected v1.0 under guideline 1.4.1: health recommendations in
/// the Nutrition plan carried no citations. These pin the properties that
/// made the fix acceptable, so a future edit can't quietly undo them.
void main() {
  final all = [...kNutritionSources, ...kTrainingSources];

  test("every claim area the plan touches has a source behind it", () {
    final topics = kNutritionSources.map((s) => s.topic.toLowerCase()).join(" ");
    // The generated plan states protein/carb targets, suggests creatine, and
    // sets calorie and fluid targets. Each needs something to cite.
    for (final claim in const ["protein", "carbohydrate", "creatine", "supplement", "calorie"]) {
      expect(topics, contains(claim),
          reason: "the plan makes a '$claim' recommendation with nothing to cite");
    }
  });

  test("every source is complete enough to be a citation", () {
    for (final s in all) {
      expect(s.title, isNotEmpty);
      expect(s.publisher, isNotEmpty, reason: "${s.title} has no publisher");
      expect(s.year, isNotEmpty, reason: "${s.title} has no year");
      expect(s.topic, isNotEmpty, reason: "${s.title} says nothing about what it backs");
    }
  });

  test("every link is https and looks like a real address", () {
    for (final s in all) {
      final uri = Uri.tryParse(s.url);
      expect(uri, isNotNull, reason: "${s.title} has an unparseable URL");
      expect(uri!.scheme, "https", reason: "${s.title} must not use plain http");
      expect(uri.host, isNotEmpty);
      expect(uri.host, contains("."));
    }
  });

  test("sources are open-access or government, not paywalled publishers", () {
    // Publisher links for these position stands bounce through a login
    // gateway; the PubMed Central copies are free to read. A reviewer
    // tapping a citation must land on the text, not a sign-in wall.
    const allowed = ["pmc.ncbi.nlm.nih.gov", "ods.od.nih.gov", "dietaryguidelines.gov",
                     "odphp.health.gov", "health.gov"];
    for (final s in all) {
      final host = Uri.parse(s.url).host;
      expect(allowed.any((a) => host.endsWith(a)), isTrue,
          reason: "${s.title} points at $host, which may sit behind a login");
    }
  });

  test("the disclaimers say what they must", () {
    for (final d in const [kNutritionDisclaimer, kTrainingDisclaimer]) {
      expect(d.toLowerCase(), contains("not medical"));
      expect(d.toLowerCase(), contains("doctor"));
    }
    // Supplements are the sharpest edge; the nutrition one names them.
    expect(kNutritionDisclaimer.toLowerCase(), contains("supplement"));
  });
}
