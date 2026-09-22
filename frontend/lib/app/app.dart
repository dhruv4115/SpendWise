import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

/// The root widget: theme plus router, and nothing else.
///
/// There is no `home` and no navigation logic here. Which screen the app opens
/// on is decided by the router's redirect, from the session state alone.
class SpendWiseApp extends ConsumerWidget {
  const SpendWiseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'SpendWise',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
