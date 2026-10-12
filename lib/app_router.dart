import 'package:re_v/core/utils/error_mapper.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/rev_app_bar.dart';
import 'core/utils/auth_url.dart';
import 'core/utils/guest_session.dart';
import 'features/ops_mobile/ops_access.dart';
import 'core/l10n/app_localizations_extension.dart';

// --- IMPORTING ESTABLISHED FEATURE MODULES ---
import 'features/partner_dashboard/presentation/partner_profile_screen.dart';
import 'features/customer_app/home/presentation/customer_landing_screen.dart';
import 'features/customer_app/estimator/presentation/estimator_screen.dart';
import 'features/customer_app/order/presentation/booking_scheduling_screen.dart';
import 'features/customer_app/order/presentation/checkout_payment_screen.dart';
import 'features/customer_app/tracking/presentation/live_stepper_timeline.dart';
import 'features/customer_app/profile/presentation/customer_profile_screen.dart';
import 'features/customer_app/notifications/presentation/customer_notifications_screen.dart';
import 'features/customer_app/notifications/presentation/notification_preferences_screen.dart';
import 'features/customer_app/profile/presentation/update_password_screen.dart';
import 'features/admin_central/presentation/master_admin_desktop.dart';
import 'features/admin_central/presentation/admin_partner_profile_screen.dart';
import 'features/admin_central/presentation/admin_partner_assessment_screen.dart';
import 'features/partner_dashboard/presentation/partner_dashboard_desktop.dart';
import 'features/partner_dashboard/presentation/partner_registration_screen.dart';
import 'features/partner_dashboard/presentation/partner_application_status_screen.dart';
import 'features/partner_dashboard/presentation/schedule_config_screen.dart';
import 'features/partner_dashboard/presentation/panel_duration_config_screen.dart';
import 'features/partner_dashboard/settings/presentation/partner_settings_screen.dart';
import 'features/partner_dashboard/presentation/partner_commlink_screen.dart';
import 'features/partner_dashboard/presentation/partner_shell_screen.dart';
import 'features/partner_dashboard/presentation/partner_staff_management_screen.dart';

// --- IMPORTING OPS MOBILE PAGES ---
import 'features/ops_mobile/presentation/ops_shell_screen.dart';
import 'features/ops_mobile/presentation/ops_floor_screen.dart';
import 'features/ops_mobile/presentation/ops_logistics_screen.dart';
import 'features/ops_mobile/presentation/ops_settings_screen.dart';
import 'features/ops_mobile/presentation/ops_intake_photo_screen.dart';
import 'features/ops_mobile/presentation/ops_milestones_screen.dart';
import 'features/ops_mobile/presentation/ops_stage_photo_screen.dart';


// --- IMPORTING CMS SCREENS ---
import 'features/cms/presentation/ai_damage_model_studio_screen.dart';
import 'features/cms/presentation/customer_concierge_nlp_studio_screen.dart';
import 'features/cms/presentation/digital_asset_manager_screen.dart';
import 'features/cms/presentation/frontend_content_studio_screen.dart';
import 'features/cms/presentation/commission_settlement_engine_screen.dart';
import 'features/cms/presentation/pricing_rules_screen.dart';

// --- IMPORTING PUBLIC CONTENT PAGES ---
import 'features/customer_app/faq/presentation/faq_screen.dart';
import 'features/customer_app/about/presentation/about_us_screen.dart';
import 'features/customer_app/legal/presentation/privacy_policy_screen.dart';
import 'features/admin_central/presentation/admin_user_accounts_screen.dart';
import 'features/admin_central/presentation/admin_invoice_review_screen.dart';
import 'features/customer_app/order/presentation/customer_invoice_screen.dart';

// --- RECOVERY STATE PROVIDER ---
final passwordRecoveryProvider = StateProvider<bool>((ref) => false);

// --- SUPABASE AUTH STATE LISTENER FOR GOROUTER ---
class SupabaseAuthRefreshNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _subscription;

  SupabaseAuthRefreshNotifier(Ref ref) {
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        ref.read(passwordRecoveryProvider.notifier).state = true;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

// --- ROUTER GLOBAL STATE ---
// SEC-16/PERF-10 fix: in-memory cache replaces _globalReturnToPath mutable global
// Avoids SharedPreferences I/O on every navigation and cross-session leakage.
String? _cachedReturnTo;

// SEC-16 fix: whitelist of allowed returnTo destinations
const _allowedReturnPaths = {
  '/estimator', '/booking', '/tracking', '/login', '/register',
  '/faq', '/profile', '/notifications', '/partner-dashboard',
  '/admin', '/', '/partner/application-status',
};

// INT-10 FIX: Sanitize returnTo to prevent open redirect attacks.
// Only allow relative paths starting with '/' and matching whitelist prefix.
String? _sanitizeReturnTo(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final trimmed = raw.trim();
  if (!trimmed.startsWith('/') || trimmed.startsWith('//')) return null;
  // SEC-16: must start with an allowed path prefix
  final allowed = _allowedReturnPaths.any((p) => trimmed == p || trimmed.startsWith('$p/'));
  return allowed ? trimmed : null;
}

// Builds the OAuth / password-recovery redirect target.
// The hash URL strategy keeps the router path in the fragment, so the callback
// must be '/#/auth/callback'. A bare '/auth/callback' would ask GitHub Pages for
// a file that does not exist and get a 404 instead of the app.
String _authCallbackUrl(String? returnTo) {
  final queryParam =
      returnTo != null ? '?returnTo=${Uri.encodeComponent(returnTo)}' : '';
  return '${Uri.base.origin}/#/auth/callback$queryParam';
}

// --- RIVERPOD ROUTER PROVIDER ---
final appRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier = SupabaseAuthRefreshNotifier(ref);
  
  ref.onDispose(() {
    authNotifier.dispose();
  });

  return GoRouter(
    initialLocation: '/',
    refreshListenable: authNotifier,
    
    // Role-based routing guards & ROUTING INTERCEPTOR
    redirect: (context, state) async {
      final session = Supabase.instance.client.auth.currentSession;
      final isLoggingIn = state.uri.path == '/login';
      final path = state.uri.path;

      // Implicit flow: magic link lands at / with #access_token=...&type=magiclink
      // Exchange the token and route to partner status page.
      if (session == null) {
        final fragment = Uri.base.fragment;
        if (fragment.contains('access_token=') && fragment.contains('type=magiclink')) {
          try {
            final params = Uri.splitQueryString(fragment);
            final accessToken = params['access_token'] ?? '';
            final refreshToken = params['refresh_token'] ?? '';
            if (accessToken.isNotEmpty) {
              final refresh = params['refresh_token'] ?? '';
              await Supabase.instance.client.auth.setSession(accessToken);
              if (refresh.isNotEmpty) {
                await Supabase.instance.client.auth.refreshSession();
              }
            }
          } catch (_) {}
          return '/partner/application-status';
        }
      }

      // Unauthenticated Guard
      if (session == null) {
        final publicPaths = ['/', '/estimator', '/diagram-test', '/auth/callback', '/partner/register', '/faq', '/about', '/privacy', '/partner/application-status'];
        if (publicPaths.contains(path) || path.startsWith('/auth/')) return null;
        if (!isLoggingIn) {
          // PERF-10/SEC-16 fix: in-memory only, no SharedPreferences I/O
          _cachedReturnTo = _sanitizeReturnTo(state.uri.toString());
          final returnTo = Uri.encodeComponent(state.uri.toString());
          return '/login?returnTo=$returnTo';
        }
        return null;
      }

      // Guest Guard — an anonymous session IS a session as far as Supabase is
      // concerned, so without this a visitor who estimated anonymously would be
      // waved straight through to the authenticated screens. Guests keep the
      // public path only; anything else sends them to sign in, which does not
      // cost them the estimate (it rides in customer_intakeProvider, which is
      // backed by SharedPreferences and survives the round trip).
      if (GuestSession.isGuest(session.user)) {
        final publicPaths = ['/', '/estimator', '/diagram-test', '/auth/callback', '/partner/register', '/faq', '/about', '/privacy', '/partner/application-status'];
        if (publicPaths.contains(path) || path.startsWith('/auth/') || isLoggingIn) {
          return null;
        }
        final returnTo = Uri.encodeComponent(state.uri.toString());
        // PERF-10/SEC-16 fix: in-memory cache, no SharedPreferences
        _cachedReturnTo = _sanitizeReturnTo(state.uri.toString());
        return '/login?returnTo=$returnTo';
      }

      // Recovery Guard
      final isRecovering = ref.read(passwordRecoveryProvider);
      if (isRecovering && path != '/update-password') {
        return '/update-password';
      }

      // Read Profile Role — ONLY from appMetadata (admin-only, secure).
      // SEC-02 FIX: user_metadata is self-writable by the account owner
      // and MUST NOT be used for authorization decisions.
      final role = (session.user.appMetadata['role'] as String?) ?? 'customer';

      // Authenticated Login/Callback Redirect Logic
      if (isLoggingIn || path == '/auth/callback') {
        final queryParamReturnTo = state.uri.queryParameters['returnTo'];
        final decodedQueryParam = queryParamReturnTo != null ? Uri.decodeComponent(queryParamReturnTo) : null;
        
        // INT-10 FIX: Sanitize all returnTo sources to block open redirects
        // PERF-10/SEC-16 fix: use in-memory cache, decode query param once
        String? targetPath = _sanitizeReturnTo(decodedQueryParam) ?? _cachedReturnTo;
        _cachedReturnTo = null; // consume it
        
        if (role == 'master_admin') return targetPath ?? '/admin-central';
        if (role == 'partner_mechanic') return targetPath ?? '/partner-dashboard';
        if (role == 'partner_staff' || role == 'partner_driver') return targetPath ?? '/ops';
        return targetPath ?? '/'; 
      } else {
        // Consume cached returnTo if present after non-callback login
        final trappedPath = _cachedReturnTo;
        _cachedReturnTo = null;
        if (trappedPath != null) return trappedPath;
      }

      // 1. MASTER ADMIN DOMAIN GUARD
      if (path.startsWith('/admin-central') && role != 'master_admin') {
        return '/'; // Access Denied Intercept
      }

      // 2. PARTNER DOMAIN GUARD
      if (path.startsWith('/partner-dashboard')) {
        if (role != 'partner_mechanic') {
          return '/'; // Access Denied Intercept
        }
        
        // SEC-02 FIX: Strict Tenant Verification Guard — read partner_id from app_metadata ONLY
        final partnerId = session.user.appMetadata['partner_id'];
        if (partnerId == null || partnerId.toString().isEmpty) {
          debugPrint('FATAL: Partner account missing isolated tenant ID in app_metadata.');
          return '/login'; 
        }
      }

      // 3. OPS / MOBILE DOMAIN GUARD
      if (path.startsWith('/ops')) {
        if (role != 'partner_staff' && role != 'partner_driver' && role != 'partner_mechanic' && role != 'master_admin') {
          return '/'; // Access Denied Intercept
        }
        if (role != 'master_admin') {
          // SEC-02 FIX: Read partner_id from app_metadata ONLY
          final partnerId = session.user.appMetadata['partner_id'];
          if (partnerId == null || partnerId.toString().isEmpty) {
            return '/login';
          }
        }
      }

      return null; // Route permitted
    },

    // 404 FALLBACK ERROR ARCHITECTURE
    // UX-03 FIX: Use theme-aware colors instead of hardcoded dark-on-dark
    errorBuilder: (context, state) {
      final cs = Theme.of(context).colorScheme;
      final l = context.l10n;
      return Scaffold(
        backgroundColor: cs.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image, size: 80, color: cs.onSurfaceVariant),
              const SizedBox(height: 24),
              Text(l.error404Title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: cs.onSurface)),
              const SizedBox(height: 16),
              Text('The route "${state.uri.path}" is unavailable or restricted.', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => context.go('/'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.fireRed),
                child: Text(l.error404ReturnButton, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    },

    routes: [
      // --- AUTHENTICATION GATE ---
      GoRoute(
        path: '/login',
        builder: (context, state) => const _GlobalAuthGate(),
      ),

      // --- OAUTH CALLBACK HANDLER ---
      // Supabase redirects here after Google login with ?code= parameter.
      // This screen exchanges the code for a session and redirects to the dashboard.
      GoRoute(
        path: '/auth/callback',
        builder: (context, state) => const _AuthCallbackScreen(),
      ),

      // --- PASSWORD RECOVERY ---
      GoRoute(
        path: '/update-password',
        builder: (context, state) => const UpdatePasswordScreen(),
      ),

      // --- CUSTOMER DOMAIN ---
      GoRoute(
        path: '/',
        builder: (context, state) => const CustomerLandingScreen(), // Public Home Landing
      ),
      GoRoute(
        path: '/partner/register',
        builder: (context, state) => const PartnerRegistrationScreen(),
      ),
      GoRoute(
        path: '/partner/application-status',
        builder: (context, state) => const PartnerApplicationStatusScreen(),
      ),
      GoRoute(
        path: '/estimator',
        builder: (context, state) => const EstimatorScreen(), // Move estimator here
      ),
      GoRoute(
        path: '/booking/schedule/:jobId',
        builder: (context, state) {
          final jobId = state.pathParameters['jobId']!;
          return BookingSchedulingScreen(jobId: jobId);
        },
      ),
      // Alias: /booking/:jobId — used by tracker/landing "Continue Booking" button
      GoRoute(
        path: '/booking/:jobId',
        builder: (context, state) {
          final jobId = state.pathParameters['jobId']!;
          return BookingSchedulingScreen(jobId: jobId);
        },
      ),
      GoRoute(
        path: '/checkout/:jobId',
        builder: (context, state) {
          final jobId = state.pathParameters['jobId']!;
          final partnerId = state.uri.queryParameters['partnerId'] ?? '';
          final paymentOnly = state.uri.queryParameters['paymentOnly'] == 'true';
          return CheckoutPaymentScreen(
            jobId: jobId,
            partnerId: partnerId,
            paymentOnly: paymentOnly,
          );
        },
      ),
      GoRoute(
        path: '/track/:jobId',
        builder: (context, state) {
          final jobId = state.pathParameters['jobId']!;
          return LiveStepperTimeline(jobId: jobId);
        },
      ),
      GoRoute(
        // The customer reviews and approves/declines the final invoice here.
        // Separate from /checkout because payment follows approval rather than
        // starting it — the amount is only known once the workshop has priced
        // the real damage.
        path: '/invoice/:jobId',
        builder: (context, state) {
          final jobId = state.pathParameters['jobId']!;
          return CustomerInvoiceScreen(jobId: jobId);
        },
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const CustomerProfileScreen(),
      ),
      GoRoute(
        path: '/support',
        redirect: (_, __) => '/faq', // merged into /faq
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const CustomerNotificationsScreen(),
      ),
      GoRoute(
        path: '/notification-settings',
        builder: (context, state) => const NotificationPreferencesScreen(),
      ),

      // --- PUBLIC CONTENT PAGES ---
      GoRoute(
        path: '/faq',
        builder: (context, state) => const FaqScreen(),
      ),
      GoRoute(
        path: '/about',
        builder: (context, state) => const AboutUsScreen(),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const PrivacyPolicyScreen(),
      ),

      GoRoute(
        path: '/admin-central',
        builder: (context, state) => const MasterAdminDesktop(),
      ),
      GoRoute(
        path: '/admin-central/partners',
        builder: (context, state) => const AdminPartnerAssessmentScreen(),
      ),
      GoRoute(
        // Assign Jobs Hub is now inline in MasterAdminDesktop — redirect back
        path: '/admin-central/assign',
        redirect: (context, state) => '/admin-central',
      ),
      GoRoute(
        path: '/admin-central/users',
        builder: (context, state) => const AdminUserAccountsScreen(),
      ),
      GoRoute(
        // Invoice check/release and Case-1 vehicle admission. Both are the same
        // admin's queue at the same point in the flow, so they share one screen.
        path: '/admin-central/invoices',
        builder: (context, state) => const AdminInvoiceReviewScreen(),
      ),
      GoRoute(
        path: '/admin-central/frontend-settings',
        builder: (context, state) => const FrontendContentStudioScreen(),
      ),
      GoRoute(
        path: '/admin-central/partner/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return AdminPartnerProfileScreen(partnerId: id);
        },
      ),
      GoRoute(
        path: '/admin-central/cms/ai-damage-model-pricing-rules',
        builder: (context, state) => const AiDamageModelStudioScreen(),
      ),
      GoRoute(
        path: '/admin-central/cms/customer-concierge-nlp',
        builder: (context, state) => const CustomerConciergeNlpStudioScreen(),
      ),
      GoRoute(
        path: '/admin-central/cms/digital-asset-manager',
        builder: (context, state) => const DigitalAssetManagerScreen(),
      ),
      GoRoute(
        path: '/admin-central/cms/frontend-content-studio',
        builder: (context, state) => const FrontendContentStudioScreen(),
      ),
      GoRoute(
        path: '/admin-central/cms/commission-settlement-engine',
        builder: (context, state) => const CommissionSettlementEngineScreen(),
      ),
      GoRoute(
        path: '/admin-central/cms/pricing-rules',
        builder: (context, state) => const PricingRulesScreen(),
      ),

      // --- PARTNER WORKSHOP DOMAIN ---
      GoRoute(
        path: '/ops',
        redirect: (context, state) async {
           // SEC-02 FIX: Read role from appMetadata only
           final role = Supabase.instance.client.auth.currentUser?.appMetadata['role'] as String?;
           // Await the workshop's mode so a driver deep-linking to /ops under the
           // strict mode lands on logistics rather than a tab they do not have.
           final mode = await ref.read(opsViewModeProvider.future);
           return opsHomeRouteFor(mode, role);
        },
      ),
      GoRoute(
        path: '/ops/floor',
        builder: (context, state) => const OpsShellScreen(
          activeRoute: '/ops/floor',
          child: OpsFloorScreen(),
        ),
        routes: [
          GoRoute(
            // jobId — milestones screen fetches customer_id internally
            path: 'milestones/:jobId',
            builder: (context, state) => OpsMilestonesScreen(
              jobId: state.pathParameters['jobId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/ops/logistics',
        builder: (context, state) => const OpsShellScreen(
          activeRoute: '/ops/logistics',
          child: OpsLogisticsScreen(),
        ),
        routes: [
          GoRoute(
            // jobId + customerId — intake screen needs both for RPC + notification
            path: 'intake/:jobId/:customerId',
            builder: (context, state) => OpsIntakePhotoScreen(
              jobId: state.pathParameters['jobId']!,
              customerId: state.pathParameters['customerId']!,
            ),
          ),
        ],
      ),
      // Generic stage photo route — used by OpsMilestonesScreen for all stages
      // Path: /ops/stage-photo/:jobId/:customerId/:stageKey
      GoRoute(
        path: '/ops/stage-photo/:jobId/:customerId/:stageKey',
        builder: (context, state) => OpsStagePhotoScreen(
          jobId: state.pathParameters['jobId']!,
          customerId: state.pathParameters['customerId']!,
          stageKey: state.pathParameters['stageKey']!,
        ),
      ),
      GoRoute(
        path: '/ops/settings',
        builder: (context, state) => const OpsShellScreen(
          activeRoute: '/ops/settings',
          child: OpsSettingsScreen(),
        ),
      ),
      GoRoute(
        path: '/partner-dashboard',
        builder: (context, state) => const PartnerDashboardDesktop(),
      ),
      GoRoute(
        path: '/partner-dashboard/profile',
        // PartnerProfileScreen now embeds PartnerShellScreen internally
        builder: (context, state) => const PartnerProfileScreen(),
      ),
      GoRoute(
        path: '/partner-dashboard/settings',
        // PartnerSettingsScreen now embeds PartnerShellScreen internally
        builder: (context, state) => const PartnerSettingsScreen(),
      ),
      GoRoute(
        path: '/partner-dashboard/staff',
        builder: (context, state) => const PartnerShellScreen(
          activeRoute: '/partner-dashboard/staff',
          pageTitle: 'Staff Management',
          child: PartnerStaffManagementScreen(),
        ),
      ),
      GoRoute(
        path: '/partner-dashboard/schedule',
        // ScheduleConfigScreen is a pure body widget — wrap it with the shell
        builder: (context, state) => const PartnerShellScreen(
          activeRoute: '/partner-dashboard/schedule',
          pageTitle: 'Schedule Config',
          child: ScheduleConfigScreen(),
        ),
      ),
      GoRoute(
        path: '/partner-dashboard/quota',
        // PanelDurationConfigScreen is a pure body widget — wrap with shell
        builder: (context, state) => const PartnerShellScreen(
          activeRoute: '/partner-dashboard/quota',
          pageTitle: 'Quota & Panel Durations',
          child: PanelDurationConfigScreen(),
        ),
      ),
      GoRoute(
        path: '/partner-dashboard/commlink',
        // PartnerCommLinkScreen now embeds PartnerShellScreen internally
        builder: (context, state) => const PartnerCommLinkScreen(),
      ),

    ],
  );
});

// --- OAUTH CALLBACK SCREEN ---
// Handles Supabase PKCE redirect. Exchanges ?code= for a live session then routes user.
class _AuthCallbackScreen extends StatefulWidget {
  const _AuthCallbackScreen();
  @override
  State<_AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends State<_AuthCallbackScreen> {
  @override
  void initState() {
    super.initState();
    _handleCallback();
  }

  Future<void> _handleCallback() async {
    final uri = Uri.base;
    final code = readAuthCode(uri);
    if (code != null) {
      try {
        await Supabase.instance.client.auth.exchangeCodeForSession(code);
      } catch (e) {
        debugPrint('OAuth callback error: $e');
      }
    }
    if (mounted) {
      // PERF-10/SEC-16 fix: read from query param or in-memory cache (no SharedPreferences)
      final rawReturnTo = GoRouterState.of(context).uri.queryParameters['returnTo'] ?? _cachedReturnTo;
      _cachedReturnTo = null;
      String? returnTo = _sanitizeReturnTo(
        rawReturnTo != null ? Uri.decodeComponent(rawReturnTo) : null,
      );
      if (returnTo != null) {
        context.go(returnTo);
      } else {
        context.go('/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.sleekBlack,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.fireRed),
            SizedBox(height: 16),
            Text('Authenticating...', style: TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}

// --- FULLY FUNCTIONAL PRODUCTION AUTH SCREEN (No Dummy Placeholders) ---
class _GlobalAuthGate extends StatefulWidget {
  const _GlobalAuthGate();

  @override
  State<_GlobalAuthGate> createState() => _GlobalAuthGateState();
}

class _GlobalAuthGateState extends State<_GlobalAuthGate> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isRegistering = false;
  bool _isResettingPassword = false;
  bool _obscurePassword = true;
  bool _registrationSuccess = false;
  bool _resetSuccess = false;
  String? _errorMessage;

  Future<void> _executeResetPassword() async {
    setState(() { _isLoading = true; _errorMessage = null; _resetSuccess = false; });
    try {
      final returnTo = GoRouterState.of(context).uri.queryParameters['returnTo'];
      final redirectTo = _authCallbackUrl(returnTo);

      await Supabase.instance.client.auth.resetPasswordForEmail(
        _emailController.text.trim(),
        redirectTo: redirectTo,
      );
      setState(() => _resetSuccess = true);
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = mapRawErrorToUserMessage(e));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _executeAuth() async {
    setState(() { _isLoading = true; _errorMessage = null; _registrationSuccess = false; _resetSuccess = false; });
    try {
      if (_isRegistering) {
        // Pass redirectTo in sign up for email confirmation redirect
        final returnTo = GoRouterState.of(context).uri.queryParameters['returnTo'];
        final emailRedirectTo = _authCallbackUrl(returnTo);

        await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          emailRedirectTo: emailRedirectTo,
        );
        setState(() => _registrationSuccess = true);
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      // GoRouter redirect interceptor handles login transition automatically
    } on AuthException catch (e) {
      // SEC-13 fix: friendly error messages, no internal details
      setState(() => _errorMessage = _mapAuthError(e.message));
    } catch (e) {
      // SEC-13 fix: never expose raw exception to user
      debugPrint('[Auth] Login error: $e');
      setState(() => _errorMessage = 'Login gagal. Periksa koneksi dan coba lagi.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mapAuthError(String raw) {
    if (raw.contains('Invalid login credentials') || raw.contains('invalid_credentials')) {
      return 'Email atau password salah';
    }
    if (raw.contains('Email not confirmed')) return 'Konfirmasi email Anda terlebih dahulu';
    if (raw.contains('User already registered')) return 'Akun dengan email ini sudah terdaftar';
    if (raw.contains('rate limit') || raw.contains('too many')) return 'Terlalu banyak percobaan, coba lagi nanti';
    if (raw.contains('network') || raw.contains('connection')) return 'Periksa koneksi internet Anda';
    return 'Login gagal. Coba lagi.';
  }

  Future<void> _executeGoogleLogin() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final returnTo = GoRouterState.of(context).uri.queryParameters['returnTo'];
      final redirectTo = _authCallbackUrl(returnTo);

      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
      );
    } on AuthException catch (e) {
      if (mounted) setState(() { _errorMessage = _mapAuthError(e.message); _isLoading = false; });
    } catch (e) {
      debugPrint('[Auth] Google auth error: $e');
      if (mounted) setState(() { _errorMessage = 'Login Google gagal. Coba lagi.'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final bgColor = theme.colorScheme.surface;
    final surfaceColor = theme.colorScheme.surfaceContainerHighest;

    return Consumer(builder: (context, ref, child) {
      final l = context.l10n;
      return Scaffold(
        backgroundColor: bgColor,
        appBar: const ReVAppBar(),
        body: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(32),
              margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: theme.colorScheme.shadow, blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => context.go('/'),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/revive_logo.png',
                          height: 40,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          're-V',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 32,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Integrated Automotive Digital Platform', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(_isRegistering ? l.loginHeadingRegister : l.loginHeadingLogin, style: const TextStyle(color: AppColors.daysGray)),
                  const SizedBox(height: 32),
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      color: Colors.red.withValues(alpha: 0.1),
                      child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ),
                  if (_registrationSuccess)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      color: Colors.green.withValues(alpha: 0.1),
                      child: Text(l.loginRegistrationSuccess, style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ),
                  if (_resetSuccess)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      color: Colors.green.withValues(alpha: 0.1),
                      child: Text(l.loginResetSent, style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ),
                  TextField(
                    controller: _emailController,
                    style: TextStyle(color: textColor),
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l.loginEmailLabel,
                      labelStyle: const TextStyle(color: AppColors.daysGray),
                      border: const OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.daysGray.withValues(alpha: 0.5)))
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  if (!_isResettingPassword) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      style: TextStyle(color: textColor),
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (!_isLoading) _executeAuth();
                      },
                      decoration: InputDecoration(
                        labelText: l.loginPasswordLabel, 
                        labelStyle: const TextStyle(color: AppColors.daysGray),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.daysGray.withValues(alpha: 0.5))),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: AppColors.daysGray),
                          onPressed: () {
                            setState(() => _obscurePassword = !_obscurePassword);
                          },
                        ),
                      ),
                      obscureText: _obscurePassword,
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : (_isResettingPassword ? _executeResetPassword : _executeAuth),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.fireRed),
                      child: _isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(_isResettingPassword ? l.loginSendResetLink : (_isRegistering ? l.loginRegisterButton : l.loginButton), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_isResettingPassword) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isResettingPassword = true;
                              _isRegistering = false;
                              _errorMessage = null;
                              _registrationSuccess = false;
                            });
                          },
                          child: Text(l.loginForgotPassword, style: TextStyle(color: textColor.withValues(alpha: 0.7))),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isRegistering = !_isRegistering;
                              _errorMessage = null;
                              _registrationSuccess = false;
                            });
                          },
                          child: Text(
                            _isRegistering ? l.loginSwitchToLogin : l.loginSwitchToRegister,
                            style: TextStyle(color: textColor.withValues(alpha: 0.9), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isResettingPassword = false;
                          _errorMessage = null;
                          _resetSuccess = false;
                        });
                      },
                      child: Text(l.loginBackToLogin, style: TextStyle(color: textColor.withValues(alpha: 0.8))),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(l.loginOr, style: const TextStyle(color: AppColors.daysGray, fontWeight: FontWeight.bold)),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _executeGoogleLogin,
                      icon: Image.asset('assets/images/google_logo.png', height: 24),
                      label: Text(l.loginContinueGoogle, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: theme.colorScheme.outline, width: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        backgroundColor: surfaceColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

