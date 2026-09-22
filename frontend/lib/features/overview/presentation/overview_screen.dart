import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/session_provider.dart';

/// Placeholder. The month summary, chart and insight cards land here in a
/// later phase; for now it only proves the shell, the guard and sign-out.
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).session;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
        actions: const [ProfileMenuButton()],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            session == null ? 'Overview' : 'Signed in as ${session.name}',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// The temporary profile entry point. A real profile screen replaces it; what
/// matters now is that signing out is reachable from the first screen.
class ProfileMenuButton extends ConsumerWidget {
  const ProfileMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).session;

    return PopupMenuButton<String>(
      // Icon-only, so it says out loud what it is.
      tooltip: 'Profile and sign out',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (_) {
        // Sign-out is a state change and nothing else: the router's redirect
        // does the navigating.
        ref.read(sessionProvider.notifier).signOut();
      },
      itemBuilder: (context) => [
        if (session != null)
          PopupMenuItem<String>(
            enabled: false,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(session.name),
              subtitle: Text(session.email),
            ),
          ),
        const PopupMenuItem<String>(
          value: 'signOut',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Sign out'),
          ),
        ),
      ],
    );
  }
}
