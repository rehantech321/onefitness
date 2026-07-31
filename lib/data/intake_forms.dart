import "models/intake_schema.dart";

/// Mirrors src/features/intake/schemas.js — TRAINING_INTAKE_SCHEMA,
/// NUTRITION_SCHEMA, and the INTAKE_FORMS list that groups them for the
/// Assessments screen. The Physical Assessment entry has no schema (it's a
/// coach-conducted movement screen, out of scope for the client-facing app).
const kTrainingIntakeSchema = IntakeSchema(
  title: "Personalized Training Intake",
  sections: [
    IntakeSection(title: "How Did You Hear About Us?", questions: [
      IntakeQuestion(
        id: "referralSource",
        label: "How did you hear about ONE Fitness?",
        type: "single",
        options: ["Instagram", "Social media", "Promotional content", "Google", "Friend / referral", "Walk-in", "Other"],
      ),
      IntakeQuestion(
        id: "referralName",
        label: "Who referred you? (first, last name and email)",
        type: "text",
        showIfId: "referralSource",
        showIfValue: "Friend / referral",
      ),
      IntakeQuestion(id: "referralOther", label: "Tell us more", type: "text", showIfId: "referralSource", showIfValue: "Other"),
    ]),
    IntakeSection(title: "Basic Client Information", questions: [
      IntakeQuestion(id: "fullName", label: "Full Name", type: "text"),
      IntakeQuestion(id: "age", label: "Age", type: "text"),
      IntakeQuestion(id: "sex", label: "Sex at birth", type: "text"),
      IntakeQuestion(id: "genderIdentity", label: "Gender Identity", type: "text"),
      IntakeQuestion(id: "height", label: "Height", type: "text"),
      IntakeQuestion(id: "weight", label: "Current Weight", type: "text"),
      IntakeQuestion(id: "goalWeight", label: "Goal Weight (if applicable)", type: "text"),
      IntakeQuestion(id: "occupation", label: "Occupation", type: "text"),
      IntakeQuestion(
        id: "activity",
        label: "Daily Activity Level Outside of Training",
        type: "single",
        options: ["Sedentary", "Lightly Active", "Moderately Active", "Very Active"],
      ),
      IntakeQuestion(id: "sleep", label: "Average Hours of Sleep Per Night", type: "text"),
    ]),
    IntakeSection(title: "Goals", questions: [
      IntakeQuestion(
        id: "primaryGoal",
        label: "Primary Goal (choose multiple)",
        type: "multi",
        options: [
          "Fat Loss",
          "Muscle Gain",
          "Body Recomposition",
          "Strength",
          "Athletic Performance",
          "Endurance",
          "Mobility/Flexibility",
          "General Health",
          "Injury Recovery",
          "Other",
        ],
      ),
      IntakeQuestion(id: "primaryGoalOther", label: "Tell us more", type: "text", showIfId: "primaryGoal", showIfValue: "Other"),
      IntakeQuestion(id: "success", label: "What does success look like to you?", type: "textarea"),
      IntakeQuestion(id: "improve", label: "Specific body areas to improve", type: "textarea"),
      IntakeQuestion(id: "avoidOver", label: "Specific body areas to avoid overdeveloping", type: "textarea"),
    ]),
    IntakeSection(title: "Medical & Injury History", questions: [
      IntakeQuestion(id: "currentInjuries", label: "Current injuries or pain", type: "textarea"),
      IntakeQuestion(id: "pastInjuries", label: "Past injuries or surgeries", type: "textarea"),
      IntakeQuestion(id: "conditions", label: "Medical conditions", type: "textarea"),
      IntakeQuestion(id: "limitations", label: "Physical limitations", type: "textarea"),
      IntakeQuestion(id: "medications", label: "Medications", type: "text"),
      IntakeQuestion(id: "supplements", label: "Supplements", type: "text"),
      IntakeQuestion(id: "redFlags", label: "Any dizziness, fainting, chest pain, or shortness of breath during exercise?", type: "textarea"),
    ]),
    IntakeSection(title: "Training History", questions: [
      IntakeQuestion(id: "experience", label: "Training experience", type: "single", options: ["Beginner", "Intermediate", "Advanced"]),
      IntakeQuestion(id: "sports", label: "Previous sports or athletic background", type: "textarea"),
      IntakeQuestion(id: "currentRoutine", label: "Current workout routine", type: "textarea"),
      IntakeQuestion(id: "daysPerWeek", label: "How many days per week can you realistically train?", type: "text"),
      IntakeQuestion(
        id: "style",
        label: "Preferred training style",
        type: "multi",
        options: [
          "Strength Training",
          "HIIT",
          "Hypertrophy/Bodybuilding",
          "Powerlifting",
          "Functional Training",
          "Boxing",
          "Cardio",
          "Athletic Performance",
          "Hybrid",
        ],
      ),
      IntakeQuestion(id: "painExercises", label: "Exercises that cause pain/discomfort", type: "textarea"),
    ]),
    IntakeSection(title: "Lifestyle & Accountability", questions: [
      IntakeQuestion(id: "obstacles", label: "Main obstacles preventing consistency", type: "textarea"),
      IntakeQuestion(id: "motivation", label: "Motivation level", type: "scale", min: 1, max: 10),
      IntakeQuestion(id: "travel", label: "Travel frequently?", type: "single", options: ["Yes", "No"]),
      IntakeQuestion(id: "accountability", label: "Preferred accountability style", type: "single", options: ["Balanced", "Strict", "Gentle", "Highly Motivational"]),
      IntakeQuestion(
        id: "commStyle",
        label: "Preferred communication style from trainer",
        type: "single",
        options: ["Before, After & During Exercise", "Only Before & After the Exercise"],
      ),
      IntakeQuestion(id: "anythingElse", label: "Anything else important the trainer should know?", type: "textarea"),
    ]),
    IntakeSection(title: "Emergency Contact", questions: [
      IntakeQuestion(id: "ecName", label: "Emergency contact name", type: "text"),
      IntakeQuestion(id: "ecRelationship", label: "Relationship", type: "text"),
      IntakeQuestion(id: "ecPhone", label: "Phone number", type: "text"),
    ]),
  ],
);

const kNutritionIntakeSchema = IntakeSchema(
  title: "Nutrition Program Intake",
  sections: [
    IntakeSection(title: "Basic Client Information", questions: [
      IntakeQuestion(id: "fullName", label: "Full Name", type: "text"),
      IntakeQuestion(id: "age", label: "Age", type: "text"),
      IntakeQuestion(id: "sex", label: "Sex at birth", type: "text"),
      IntakeQuestion(id: "genderIdentity", label: "Gender Identity", type: "text"),
      IntakeQuestion(id: "height", label: "Height", type: "text"),
      IntakeQuestion(id: "weight", label: "Current Weight", type: "text"),
      IntakeQuestion(id: "goalWeight", label: "Goal Weight (if applicable)", type: "text"),
    ]),
    IntakeSection(title: "Nutrition Information", questions: [
      IntakeQuestion(
        id: "mainGoal",
        label: "Main nutrition goal (choose multiple)",
        type: "multi",
        options: ["Fat Loss", "Muscle Gain", "Maintenance", "Performance", "Overall Health", "Other"],
      ),
      IntakeQuestion(id: "mainGoalOther", label: "Tell us more", type: "text", showIfId: "mainGoal", showIfValue: "Other"),
      IntakeQuestion(id: "allergies", label: "Food allergies", type: "textarea"),
      IntakeQuestion(id: "intolerances", label: "Food intolerances/sensitivities", type: "textarea"),
      IntakeQuestion(id: "dislikes", label: "Foods you absolutely dislike", type: "textarea"),
      IntakeQuestion(id: "enjoy", label: "Foods you enjoy", type: "textarea"),
      IntakeQuestion(
        id: "dietaryStyle",
        label: "Dietary style",
        type: "single",
        options: ["No Restrictions", "Vegetarian", "Vegan", "Pescatarian", "Kosher", "Halal", "Gluten-Free", "Dairy-Free", "Other"],
      ),
      IntakeQuestion(id: "dietaryStyleOther", label: "Tell us more", type: "text", showIfId: "dietaryStyle", showIfValue: "Other"),
      IntakeQuestion(id: "mealsPerDay", label: "How many meals per day do you eat on average?", type: "text"),
      IntakeQuestion(id: "hungryTimes", label: "Times of day you get most hungry", type: "text"),
      IntakeQuestion(id: "eatingOut", label: "Frequency of eating out per week", type: "text"),
      IntakeQuestion(id: "alcohol", label: "Alcohol consumption", type: "single", options: ["No alcohol", "A couple drinks a month", "A couple drinks a week", "More"]),
      IntakeQuestion(id: "smoking", label: "Smoking/nicotine use", type: "single", options: ["Yes", "Occasional", "None"]),
      IntakeQuestion(
        id: "cravings",
        label: "Cravings",
        type: "multi",
        options: ["Sweet", "Salty", "Fast Food", "Late Night Eating", "Emotional Eating", "None"],
      ),
      IntakeQuestion(id: "cooking", label: "Cooking ability", type: "single", options: ["Beginner", "Moderate", "Advanced"]),
      IntakeQuestion(id: "budget", label: "Budget level for groceries", type: "single", options: ["Low", "Moderate", "High"]),
      IntakeQuestion(
        id: "access",
        label: "Access to",
        type: "multi",
        options: ["Microwave", "Refrigerator", "Stove", "Air Fryer", "Blender", "Meal Prep Time"],
      ),
    ]),
  ],
);

const kIntakeForms = [
  IntakeFormGroup(
    key: "training",
    title: "Training Intake",
    assessments: [
      AssessmentDef(key: "personalTraining", title: "Personalized Training Intake", by: "Client or Programmer", schema: kTrainingIntakeSchema),
      AssessmentDef(key: "physical", title: "Free Physical Assessment Session", by: "Coach · first training session", clientCanFill: false, physical: true),
    ],
  ),
  IntakeFormGroup(
    key: "nutrition",
    title: "Nutrition Intake",
    assessments: [
      AssessmentDef(key: "nutritional", title: "Nutrition Program Intake", by: "Client or Programmer", schema: kNutritionIntakeSchema),
    ],
  ),
];
