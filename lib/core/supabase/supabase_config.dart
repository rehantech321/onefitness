/// Connection info for the real ONE Fitness Supabase project — the exact
/// same backend the web app (onefitness-demo-package) talks to.
///
/// Only the project URL and the PUBLISHABLE (anon) key live here. Both are
/// meant to ship inside a client app — the web app inlines the identical
/// values into its own public JS bundle via Vite's `VITE_*` env vars, and
/// access is enforced by Postgres Row Level Security policies, not by
/// keeping this key secret. Never add the Supabase *service role* key, the
/// SMTP password, or the Stripe secret key here — those are server-only
/// (used by Supabase edge functions) and would leak to anyone who inspects
/// this app's compiled output if embedded in client code.
class SupabaseConfig {
  SupabaseConfig._();

  static const url = "https://nzpfndamxcwpvpxdlrol.supabase.co";
  static const publishableKey = "sb_publishable_PSCUheJXJxRPeYrbs9XxSQ_BoUZZljJ";
}
