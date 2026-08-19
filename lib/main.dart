import "dart:async";
import "package:app_links/app_links.dart";
import "package:flutter/foundation.dart" show kIsWeb;
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "core/supabase/supabase_service.dart";
import "core/theme/app_colors.dart";
import "core/theme/app_theme.dart";
import "data/providers/client_providers.dart";
import "data/providers/role_provider.dart";
import "data/providers/supabase_bootstrap_provider.dart";
import "data/providers/trainer_providers.dart";
import "features/auth/client_auth_screen.dart";
import "features/client/shell/client_shell.dart";
import "features/shell/app_header.dart";
import "features/trainer/auth/trainer_auth_screen.dart";
import "features/trainer/shell/trainer_shell.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  runApp(const ProviderScope(child: OneFitnessApp()));
}

/// Lets the Stripe-return check in _RootGate show a SnackBar without
/// needing a Scaffold ancestor at its own position in the tree (it sits
/// above every screen's own Scaffold) — the standard MaterialApp pattern
/// for exactly this.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class OneFitnessApp extends StatelessWidget {
  const OneFitnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "ONE Fitness",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: const _RootGate(),
    );
  }
}

/// Mirrors App.jsx's top-level structure: the Coach/Client pill toggle
/// (Header) above whichever shell is active, hidden once a client is signed
/// in. Each side's own auth screen gates its own shell independently.
///
/// Before any of that renders, this waits on [supabaseBootstrapProvider] —
/// the real Supabase session restore + roster/trainers/bookings fetch —
/// same as App.jsx awaiting its own bootstrap Promise.all before mounting.
class _RootGate extends ConsumerStatefulWidget {
  const _RootGate();

  @override
  ConsumerState<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<_RootGate> {
  bool _checkedStripeReturn = false;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    // Uri.base's own `?stripe=...` only exists on Flutter web (the browser
    // reloads this same "page"); on mobile the equivalent is Stripe's
    // browser handing off to the app's own "onefitness://checkout-return"
    // deep link instead — see membership_hub_screen.dart's returnUrl and
    // the matching intent-filter/CFBundleURLTypes entries.
    if (!kIsWeb) _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleDeepLink(initial);
    } catch (_) {
      // No initial link, or the platform channel isn't ready yet — either
      // way there's nothing to recover from here.
    }
    _linkSub = _appLinks.uriLinkStream.listen(_handleDeepLink, onError: (_) {});
  }

  void _handleDeepLink(Uri uri) {
    if (uri.scheme != "onefitness" || uri.host != "checkout-return") return;
    final stripeParam = uri.queryParameters["stripe"];
    if (stripeParam == null) return;
    _showStripeSnack(stripeParam);
    // A successful payment is only ever actually applied server-side by
    // stripe-webhook, often with a short delay — re-running the same
    // fetch+seed used at sign-in gives this landing its best shot at
    // showing the new membership without the client having to leave and
    // come back to this screen themselves.
    if (stripeParam == "success") loadAndSeedCoreData(ref);
  }

  /// One-time check for `?stripe=success`/`?stripe=cancel` on the URL —
  /// create-checkout-session's `success_url`/`cancel_url` land back on this
  /// same page on web (see membership_hub_screen.dart's `returnUrl`). The
  /// plan itself is only ever granted by stripe-webhook confirming payment
  /// (never here, and often not instantly), so this deliberately doesn't
  /// claim the purchase is done — just that Stripe took the payment and
  /// the membership will show up once the webhook's caught up.
  void _checkStripeReturn() {
    if (_checkedStripeReturn) return;
    _checkedStripeReturn = true;
    if (!kIsWeb) return;
    final stripeParam = Uri.base.queryParameters["stripe"];
    if (stripeParam == null) return;
    _showStripeSnack(stripeParam);
  }

  void _showStripeSnack(String stripeParam) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messenger = scaffoldMessengerKey.currentState;
      if (messenger == null) return;
      if (stripeParam == "success") {
        messenger.showSnackBar(const SnackBar(
          content: Text("Payment received — your membership will update shortly."),
          duration: Duration(seconds: 6),
        ));
      } else if (stripeParam == "cancel") {
        messenger.showSnackBar(const SnackBar(content: Text("Checkout was cancelled — nothing was charged.")));
      }
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(supabaseBootstrapProvider);

    return bootstrap.when(
      loading: () => const Scaffold(backgroundColor: AppColors.bg, body: Center(child: CircularProgressIndicator(color: AppColors.gold))),
      error: (err, st) => const _RootContent(), // fall back to mock/signed-out state rather than block the app
      data: (_) {
        _checkStripeReturn();
        return const _RootContent();
      },
    );
  }
}

class _RootContent extends ConsumerWidget {
  const _RootContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleProvider);
    final clientSignedIn = ref.watch(clientSignedInProvider);
    final clientSigningUp = ref.watch(clientSigningUpProvider);
    final trainerAuth = ref.watch(trainerAuthProvider);

    final staffSignedIn = role == "trainer" && trainerAuth != null;
    final showHeader = !((role == "client" && (clientSignedIn || clientSigningUp)) || staffSignedIn);
    final body = role == "trainer" ? (trainerAuth == null ? const TrainerAuthScreen() : const TrainerShell()) : (clientSignedIn ? const ClientShell() : const ClientAuthScreen());

    if (!showHeader) return body;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const AppHeader(),
          Expanded(child: body),
        ],
      ),
    );
  }
}
