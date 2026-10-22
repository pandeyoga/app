import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';
import 'package:re_v/l10n/app_localizations.dart';
import 'core/providers/locale_provider.dart';
import 'core/utils/session_health.dart';
// G-03: PricingMatrix import removed — preload() deleted

void main() async {
  // 1. Ensure Flutter engine is fully initialized before async network bindings run
  WidgetsFlutterBinding.ensureInitialized();

  // URL strategy: HASH (Flutter web default) — deliberate.
  // GitHub Pages cannot rewrite unknown paths to index.html, so deep links
  // served 404.html with a 404 status and the app never booted. Hash URLs keep
  // every route inside '/', which GitHub Pages always serves as 200.
  // Revisit if/when the site moves to Cloudflare Pages (web/_redirects is
  // already prepared for that switch); at that point usePathUrlStrategy() may
  // be restored for clean URLs.

  // 2. Load environment variables securely from the local filesystem
  await dotenv.load(fileName: ".env");

  // 3. Initialize Supabase Connection mapping to the production schema via strict environment pointers
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // 4. G-03 fix: PricingMatrix.preload() removed — dead cache, every visitor paid 1 startup query.
  //    Pricing is now loaded on demand inside vision-estimation Edge Function only.

  // 5. Heal a stored session whose access token is dated in the future.
  //    PostgREST answers such a token with 401 / PGRST303 before any policy
  //    runs, which surfaced as partner staff being unable to open a job's
  //    stages. The token cannot expire its way out (iat and exp are both
  //    shifted forward, so the client thinks it is still valid), so a refresh
  //    on startup is what actually clears it. See core/utils/session_health.dart.
  watchSessionHealth(Supabase.instance.client);

  // 6. Run the App inside a ProviderScope (Required by Riverpod for State Management)
  runApp(
    const ProviderScope(
      child: ReVApp(),
    ),
  );
}

class ReVApp extends ConsumerWidget {
  const ReVApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final currentThemeMode = ref.watch(themeModeProvider);
    final currentLocale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 're-V.co.id | Automotive Body Repair Portal',
      debugShowCheckedModeBanner: false,

      // Localizations — EN / ID switchable at runtime
      locale: currentLocale,
      localizationsDelegates: AppL.localizationsDelegates,
      supportedLocales: supportedLocales,

      // Theme Configuration strictly mapped to re-V Brand Identity
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: currentThemeMode,

      // Enable Web Mouse Dragging for Carousels
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        },
      ),

      // Hook Flutter directly into our GoRouter instance
      routerConfig: router,

      // Text selection on every page. SelectionArea needs the
      // MaterialLocalizations that MaterialApp provides, so it sits inside
      // the app here instead of wrapping it (that threw in debug mode). It
      // also needs an Overlay ancestor for its handles and context menu, and
      // the Navigator's Overlay is below this point, so it brings its own.
      builder: (context, child) => Overlay.wrap(
        child: SelectionArea(child: child!),
      ),
    );
  }
}
