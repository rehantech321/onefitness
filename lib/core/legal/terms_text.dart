/// The ONE Fitness Terms & Conditions, as supplied by the business, with
/// Part D added.
///
/// Part D is not decoration: Apple App Review guideline 1.2 requires an
/// EULA stating zero tolerance for objectionable content and abusive users
/// before an app carrying user-generated content is approved. The supplied
/// Terms cover SMS and training services but not that, so removing Part D
/// would fail review.
///
/// Where the supplied text carried a bracketed placeholder for a number the
/// app already knows and can vary per plan — cancellation notice, package
/// expiry, billing notice — the wording points at what the client actually
/// sees rather than showing them "[X]". Placeholders for facts only the
/// business can supply are left bracketed: [WEBSITE].
///
/// Bump [kTermsVersion] whenever this changes materially — users whose
/// stored `profiles.accepted_terms_version` doesn't match are asked to
/// accept again on next sign-in.
library;

const String kTermsVersion = "2026-09-26";

const String kTermsEffectiveDate = "26 September 2026";

const String kTermsOfUse = """
These Terms govern your use of the services, app, website and text messaging
program of One Fitness Workout d/b/a ONE Fitness Marketplace ("ONE Fitness,"
"we," "us"). By booking a session, purchasing a package or membership, using
our app or website, or opting in to texts, you agree to these Terms and our
Privacy Policy.

═══ PART A: SMS MESSAGING TERMS ═══

1. Program name: ONE Fitness Client Alerts.

2. Program description: Clients and prospective clients who opt in receive
appointment reminders, booking confirmations, schedule changes, account and
billing notices, and, if they separately opt in, occasional promotional
offers from ONE Fitness.

3. How to opt in: by checking the optional, unchecked SMS consent box when
you create your account or in Profile Settings → Notification Preferences,
by texting START or JOIN to the number our messages come from, or by giving
written consent on our client intake form. Consent is not a condition of any
purchase.

4. Message frequency: varies; typically up to 8 messages per month.

5. Cost: Message and data rates may apply. Check your mobile plan for
details.

6. Opt out: Reply STOP, CANCEL, END, QUIT or UNSUBSCRIBE at any time, or
turn off Text messages in Profile Settings → Notification Preferences. You
will receive one confirmation text and no further messages unless you opt in
again.

7. Help: Reply HELP, or contact info@onefitnessworkout.com or
(818) 223-7001.

8. Carrier disclaimer: Carriers are not liable for delayed or undelivered
messages.

9. Privacy: Mobile information is never shared with third parties or
affiliates for marketing or promotional purposes. See our Privacy Policy.

10. Your number: You confirm you are the account holder or authorized user
of the mobile number you provide, and you will notify us if that number
changes or is reassigned.

═══ PART B: TRAINING SERVICES TERMS ═══

11. Health and medical clearance. You confirm you are physically able to
take part in exercise. You agree to consult a physician before starting any
program and to tell your coach about any injury, condition, medication,
pregnancy or symptom that could affect your training, before each session if
it changes. Stop exercising and tell your coach immediately if you feel
pain, dizziness, shortness of breath or discomfort.

12. Assumption of risk. Exercise, strength training and the use of equipment
carry inherent risks, including muscle strains, sprains, fractures, cardiac
events and, in rare cases, death. You voluntarily assume all such risks,
known and unknown, whether training one-on-one, in semi-private sessions,
following a program on your own, or using any facility where we train.

13. Release and waiver. To the fullest extent allowed by law, you release
ONE Fitness, its owners, coaches, employees, contractors and partner
facilities from all claims for injury, illness, death or property loss
arising from your participation in our services, except where caused by our
gross negligence or willful misconduct. Clients must also sign our separate
Liability Waiver and Intake Form before their first session.

14. Not medical advice. Training and nutrition programs are for general
fitness purposes. They are not medical or dietetic treatment and do not
diagnose, treat or cure any condition. Results vary and are not guaranteed.

15. Facility rules. Sessions take place at partner facilities (currently
2422 W Victory Blvd, Burbank, CA 91506). You agree to follow that facility's
rules and any access agreement or fee it requires. ONE Fitness is not
responsible for the facility's premises, equipment maintenance, or lost or
stolen property.

16. Packages, memberships and payments.
• Prices are listed at booking and may change with notice; changes do not
  affect sessions already paid for.
• Packages do not auto-renew. Unused package sessions expire as stated on
  the package you purchased.
• Memberships renew automatically each month on your billing date until you
  cancel. By purchasing a membership you authorize recurring charges to your
  payment method. Cancel at any time from Access Hub, or by contacting
  info@onefitnessworkout.com, giving at least the notice period stated on
  your plan before your next billing date; cancellation takes effect at the
  end of the current billing period.
• Unused membership sessions roll over only as described in your membership
  plan.
• Payments are non-refundable except where required by law or approved by
  ONE Fitness in writing.

17. Cancellations and no-shows. Cancel or reschedule by the deadline shown
on your booking. Late cancellations and no-shows are counted as a used
session and may incur the fee stated on your plan.

18. Conduct. We may suspend or end services, without refund of the current
period, for unsafe, abusive or disruptive behavior toward coaches, clients
or facility staff.

19. Photos and content. We will not use your photo, video or testimonial in
marketing without your written permission.

═══ PART C: GENERAL TERMS ═══

20. Limitation of liability. To the fullest extent allowed by law, ONE
Fitness is not liable for indirect, incidental, special or consequential
damages. Our total liability for any claim is limited to the amount you paid
us in the three months before the claim arose.

21. Indemnification. You agree to indemnify and hold harmless ONE Fitness
and its owners, coaches and contractors from claims, losses and costs
(including reasonable attorney fees) arising from your breach of these
Terms, false health information you provide, or your misuse of the services
or facility.

22. Dispute resolution. Please contact us first at
info@onefitnessworkout.com; most issues can be resolved directly. Any
dispute not resolved within 30 days will be brought in the state or federal
courts located in Los Angeles County, California, or in small claims court
where eligible.

23. Governing law. These Terms are governed by the laws of the State of
California.

24. Severability. If any part of these Terms is found unenforceable, the
rest stays in effect.

25. Changes. We may update these Terms; the effective date above shows the
latest version. Continued use after an update means you accept it. Material
changes to the SMS program will be sent by text or email.

26. Contact. ONE Fitness · 2422 W Victory Blvd, Burbank, CA 91506 ·
info@onefitnessworkout.com · (818) 223-7001

═══ PART D: COMMUNITY STANDARDS AND CONTENT ═══

27. ZERO TOLERANCE FOR OBJECTIONABLE CONTENT AND ABUSIVE BEHAVIOUR

There is zero tolerance for objectionable content or abusive users on ONE
Fitness. You may not post, send or upload content that is:

• harassing, threatening, bullying or intimidating;
• hateful or discriminatory on any basis, including race, ethnicity,
  national origin, religion, sex, gender identity, sexual orientation,
  disability or age;
• sexually explicit, obscene or pornographic;
• violent, or that encourages self-harm or harm to others;
• illegal, or that promotes illegal activity;
• spam, fraudulent, deceptive or a scam;
• impersonating another person, coach or business;
• someone else's personal or private information shared without consent.

This applies everywhere you can enter text or upload an image: chat
messages, your display name, your bio, reviews, posts, progress photos and
any other submission.

28. Enforcement. We review every report. Content that breaches these Terms
is removed and the account responsible is suspended or permanently banned.
Reports are reviewed and acted on within 24 hours. We may remove content or
terminate an account at any time, without notice, for any breach of these
Terms. A banned account cannot sign in, and its content is hidden from other
users.

29. Reporting and blocking. Every message, profile and review carries a
Report action. You can report content as spam, harassment or abuse,
inappropriate content, or for another reason you describe. You can block any
user: blocking immediately hides that person from your chats, search results
and coach listings, and stops the two of you from messaging each other.
Manage blocked users from Settings → Blocked users.

30. Your account. You must be 18 or older to use ONE Fitness. You are
responsible for what happens under your account and for keeping your
password secure. You may delete your account at any time from Profile
Settings → Delete Account. Deletion is permanent: your profile, photos,
messages and reports are removed. Records we must keep for tax and
accounting — payments and past bookings — are retained in anonymised form
with your personal details stripped out.
""";
