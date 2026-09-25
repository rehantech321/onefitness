/// The Terms of Use every user must accept before creating an account or,
/// for existing users, on their next sign-in.
///
/// Apple guideline 1.2 requires an EULA that states a zero-tolerance policy
/// for objectionable content and abusive users. Bump [kTermsVersion] whenever
/// the text changes materially — users whose stored
/// `profiles.accepted_terms_version` doesn't match are asked to accept again.
const String kTermsVersion = "2026-09-25";

const String kTermsEffectiveDate = "25 September 2026";

const String kTermsOfUse = """
ONE Fitness connects clients with coaches for in-person training sessions. By
creating an account you agree to these Terms of Use.

1. ZERO TOLERANCE FOR OBJECTIONABLE CONTENT AND ABUSIVE BEHAVIOUR

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

This applies everywhere you can enter text or upload an image: chat messages,
your display name, your bio, reviews, posts, progress photos and any other
submission.

2. ENFORCEMENT

We review every report. Content that breaches these Terms is removed and the
account responsible is suspended or permanently banned. Reports are reviewed
and acted on within 24 hours. We may remove content or terminate an account
at any time, without notice, for any breach of these Terms.

A banned account cannot sign in, and its content is hidden from other users.

3. REPORTING AND BLOCKING

Every message, profile and review carries a Report action. You can report
content as spam, harassment or abuse, inappropriate content, or for another
reason you describe.

You can block any user. Blocking immediately hides that person from your
chats, search results and coach listings, and stops the two of you from
messaging each other. Manage blocked users from Settings → Blocked users.

4. YOUR ACCOUNT

You must be 18 or older to use ONE Fitness. You are responsible for what
happens under your account and for keeping your password secure. Keep your
contact details accurate so your coach can reach you about a session.

You may delete your account at any time from Settings → Delete Account.
Deletion is permanent. Your profile, photos, messages and reports are removed.
Records we must keep for tax and accounting — payments and past bookings —
are retained in anonymised form with your personal details stripped out.

5. SESSIONS, BOOKINGS AND PAYMENTS

Sessions are delivered in person by independent coaches. Payments are handled
by Stripe; we do not store your full card details. Cancellation and no-show
terms are shown on the plan you buy and in the agreement you sign for it.

Training carries risk of injury. You confirm you are physically able to take
part and will tell your coach about any condition affecting your training.

6. CHANGES

We may update these Terms. If we do, you will be asked to accept the new
version the next time you sign in.

Questions about these Terms, or to report an urgent safety concern, contact
ONE Fitness from Menu → Support.
""";
