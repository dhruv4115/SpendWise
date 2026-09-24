import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/state/session_provider.dart';
import '../features/budgets/presentation/budget_edit_screen.dart';
import '../features/budgets/presentation/budgets_screen.dart';
import '../features/merchants/presentation/merchant_screen.dart';
import '../features/merchants/presentation/merchants_screen.dart';
import '../features/overview/presentation/overview_screen.dart';
import '../features/transactions/presentation/feed_screen.dart';
import '../features/transactions/presentation/transaction_screen.dart';
import 'routes.dart';

/// Where the app opens. Overridable so a test can start at a deep link, and
/// so the platform's launch URL still wins on web and from an app link.
final Provider<String> initialLocationProvider = Provider<String>(
  (ref) => Routes.splashPath,
);

/// The router, rebuilt never: it is created once per [ProviderContainer] and
/// reacts to sign-in through [refreshListenable] instead.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  // Built here rather than at the top level so two containers — an app and a
  // widget test, or two tests — never share one GlobalKey.
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  final overviewKey = GlobalKey<NavigatorState>(debugLabel: 'overview');
  final transactionsKey = GlobalKey<NavigatorState>(debugLabel: 'transactions');
  final budgetsKey = GlobalKey<NavigatorState>(debugLabel: 'budgets');
  final merchantsKey = GlobalKey<NavigatorState>(debugLabel: 'merchants');

  final refresh = _SessionRefresh();
  ref.listen<SessionState>(sessionProvider, (_, __) => refresh.refresh());
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: ref.watch(initialLocationProvider),
    refreshListenable: refresh,
    redirect: (context, state) => _guard(ref, state),
    errorBuilder: (context, state) => RouteNotFoundScreen(uri: state.uri),
    routes: [
      GoRoute(
        path: Routes.splashPath,
        name: Routes.splashName,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.loginPath,
        name: Routes.loginName,
        builder: (context, state) => const LoginScreen(),
      ),
      // One IndexedStack, four navigators: switching tabs keeps each tab's
      // scroll position and its pushed detail pages, and a detail route opens
      // inside its tab rather than covering the bottom bar.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: overviewKey,
            routes: [
              GoRoute(
                path: Routes.overviewPath,
                name: Routes.overviewName,
                builder: (context, state) => const OverviewScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: transactionsKey,
            routes: [
              GoRoute(
                path: Routes.transactionsPath,
                name: Routes.transactionsName,
                builder: (context, state) => FeedScreen(
                  category:
                      state.uri.queryParameters[Routes.categoryQueryParam],
                ),
                routes: [
                  GoRoute(
                    path: Routes.idSegment,
                    name: Routes.transactionDetailName,
                    builder: (context, state) => TransactionScreen(
                      id: state.pathParameters[Routes.idParam] ?? '',
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: budgetsKey,
            routes: [
              GoRoute(
                path: Routes.budgetsPath,
                name: Routes.budgetsName,
                builder: (context, state) => const BudgetsScreen(),
                routes: [
                  GoRoute(
                    path: Routes.categorySegment,
                    name: Routes.budgetDetailName,
                    builder: (context, state) => BudgetEditScreen(
                      category:
                          state.pathParameters[Routes.categoryParam] ?? '',
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: merchantsKey,
            routes: [
              GoRoute(
                path: Routes.merchantsPath,
                name: Routes.merchantsName,
                builder: (context, state) => const MerchantsScreen(),
                routes: [
                  GoRoute(
                    path: Routes.idSegment,
                    name: Routes.merchantDetailName,
                    builder: (context, state) => MerchantScreen(
                      merchantKey: state.pathParameters[Routes.idParam] ?? '',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});

/// The one place that decides who may see what.
///
/// Returning null means "the requested location is fine". Every other answer
/// carries the attempted location along in [Routes.fromQueryParam], so the
/// trip through splash and sign-in does not lose where the customer was going.
String? _guard(Ref ref, GoRouterState state) {
  final session = ref.read(sessionProvider);
  final matched = state.matchedLocation;
  final target = _attemptedLocation(state);

  switch (session) {
    case SessionUnknown():
      // Still reading the keystore. Hold on the splash screen; the refresh
      // listenable brings us straight back here when the answer arrives.
      if (matched == Routes.splashPath) return null;
      return _locationWithFrom(Routes.splashPath, target);

    case SessionSignedOut():
      if (matched == Routes.loginPath) return null;
      return _locationWithFrom(Routes.loginPath, target);

    case SessionSignedIn():
    case SessionLocked():
      if (matched == Routes.loginPath || matched == Routes.splashPath) {
        return target ?? Routes.overviewPath;
      }
      return null;
  }
}

/// The location the customer is actually trying to reach.
///
/// On a real screen that is the current location. On splash or sign-in it is
/// whatever `from` they were sent there with, which is how the deep link
/// survives two redirects.
String? _attemptedLocation(GoRouterState state) {
  final matched = state.matchedLocation;
  if (matched == Routes.loginPath || matched == Routes.splashPath) {
    return _safeFrom(state.uri.queryParameters[Routes.fromQueryParam]);
  }
  final location = state.uri.toString();
  return location == Routes.overviewPath ? null : location;
}

/// Only in-app paths come back from a query parameter: anything with a scheme
/// or an authority would turn the sign-in screen into an open redirect, and a
/// `from` pointing at splash or sign-in would loop.
String? _safeFrom(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (!raw.startsWith('/') || raw.startsWith('//')) return null;

  final uri = Uri.tryParse(raw);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  if (uri.path == Routes.loginPath || uri.path == Routes.splashPath) {
    return null;
  }

  return raw;
}

String _locationWithFrom(String path, String? from) {
  if (from == null) return path;
  return Uri(
    path: path,
    queryParameters: {Routes.fromQueryParam: from},
  ).toString();
}

/// Turns session changes into the [Listenable] go_router understands.
class _SessionRefresh extends ChangeNotifier {
  // notifyListeners is protected; this is the public door onto it.
  void refresh() => notifyListeners();
}

/// The signed-in frame: an IndexedStack of the four branches under a bottom
/// navigation bar.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<NavigationDestination> _destinations = [
    NavigationDestination(
      icon: Icon(Icons.pie_chart_outline),
      selectedIcon: Icon(Icons.pie_chart),
      label: 'Overview',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: 'Spending',
    ),
    NavigationDestination(
      icon: Icon(Icons.savings_outlined),
      selectedIcon: Icon(Icons.savings),
      label: 'Budgets',
    ),
    NavigationDestination(
      icon: Icon(Icons.storefront_outlined),
      selectedIcon: Icon(Icons.storefront),
      label: 'Merchants',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        // Labels are always visible: the icon alone is not the signal.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: _destinations,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          // Tapping the tab you are already on returns it to its root, which
          // is what every other banking app does.
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

/// A link that goes nowhere. Says so in plain words and offers a way out.
class RouteNotFoundScreen extends StatelessWidget {
  const RouteNotFoundScreen({super.key, required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.explore_off_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'We could not find that page',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  'The link may be out of date. Your money and your data are '
                  'unaffected.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.go(Routes.overviewPath),
                child: const Text('Go to Overview'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
