/// Citations for the health and nutrition guidance the app shows.
///
/// App Review rejected version 1.0 under guideline 1.4.1: "the app provides
/// health or medical recommendations in the Nutrition plan without
/// citations, such as links to sources for this information... The
/// citations to the sources should be easy for the user to find."
///
/// So these are shown directly beneath the generated guidelines, on the
/// same screen, not buried in a legal page.
///
/// Every link was checked to be live and open-access before shipping. One
/// earlier candidate turned out to be a paper on fish vaccines, and two
/// publisher links bounced through a login gateway — the PubMed Central
/// copies below are free to read with no account, which is what a reviewer
/// (or a client) tapping a citation needs.
library;

class HealthSource {
  const HealthSource({
    required this.topic,
    required this.title,
    required this.publisher,
    required this.year,
    required this.url,
  });

  /// What this source backs up, so a client can tell which claim it covers.
  final String topic;
  final String title;
  final String publisher;
  final String year;
  final String url;
}

const List<HealthSource> kNutritionSources = [
  HealthSource(
    topic: "Protein intake",
    title: "ISSN Position Stand: Protein and Exercise",
    publisher: "Journal of the International Society of Sports Nutrition",
    year: "2017",
    url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC5477153/",
  ),
  HealthSource(
    topic: "Carbohydrate intake and timing",
    title: "Fundamentals of Glycogen Metabolism for Coaches and Athletes",
    publisher: "Nutrition Reviews",
    year: "2018",
    url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC6019055/",
  ),
  HealthSource(
    topic: "Creatine and supplements",
    title: "ISSN Position Stand: Safety and Efficacy of Creatine Supplementation",
    publisher: "Journal of the International Society of Sports Nutrition",
    year: "2017",
    url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC5469049/",
  ),
  HealthSource(
    topic: "Supplements and performance",
    title: "Dietary Supplements for Exercise and Athletic Performance",
    publisher: "NIH Office of Dietary Supplements",
    year: "Updated regularly",
    url: "https://ods.od.nih.gov/factsheets/ExerciseAndAthleticPerformance-Consumer/",
  ),
  HealthSource(
    topic: "Calories, fluids and overall diet",
    title: "Dietary Guidelines for Americans, 2020–2025",
    publisher: "U.S. Departments of Agriculture and Health and Human Services",
    year: "2020",
    url: "https://www.dietaryguidelines.gov/",
  ),
];

/// Shown with the citations. Short on purpose — a wall of legal text next
/// to the plan gets skipped, and this has to actually be read.
const String kNutritionDisclaimer =
    "These targets are general fitness guidance, not medical or dietetic "
    "advice, and they don't diagnose or treat any condition. Talk to your "
    "doctor or a registered dietitian before changing your diet or taking "
    "any supplement — especially if you are pregnant, taking medication or "
    "managing a health condition.";

/// The equivalent for training guidance.
const List<HealthSource> kTrainingSources = [
  HealthSource(
    topic: "Physical activity and resistance training",
    title: "Physical Activity Guidelines for Americans, 2nd edition",
    publisher: "U.S. Department of Health and Human Services",
    year: "2018",
    url: "https://odphp.health.gov/our-work/nutrition-physical-activity/physical-activity-guidelines",
  ),
  HealthSource(
    topic: "Protein and recovery",
    title: "ISSN Position Stand: Protein and Exercise",
    publisher: "Journal of the International Society of Sports Nutrition",
    year: "2017",
    url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC5477153/",
  ),
];

const String kTrainingDisclaimer =
    "This program is general fitness guidance, not medical advice. Stop and "
    "seek medical help if you feel pain, dizziness or shortness of breath. "
    "Check with your doctor before starting a new training program.";
