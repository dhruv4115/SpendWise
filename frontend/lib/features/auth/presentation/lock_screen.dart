import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/app_lock.dart';
import '../../../core/security/biometric_service.dart';
import '../../../core/security/secure_flag.dart';

/// `/lock`: the app, locked, and the two ways out of it.
///
/// It shows nothing about the account behind it — no name, no balance, no
/// last transaction. A locked screen that still says "Asha Rao · ₹42,000" has
/// given away most of what the lock was for.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  @override
  void initState() {
    super.initState();
    // Asked for as soon as the screen appears: someone coming back to the app
    // came back to use it, not to press one more button first. After the
    // frame, so the prompt rises over a screen that is already drawn.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_unlock());
    });
  }

  Future<void> _unlock() => ref.read(appLockProvider.notifier).unlock();

  Future<void> _signOut() => ref.read(appLockProvider.notifier).signOut();

  /// What to say about the last attempt. Plain language, and never the
  /// plugin's own words.
  static String _message(UnlockOutcome? outcome) => switch (outcome) {
        null => 'Use your fingerprint, face or screen lock to continue.',
        UnlockOutcome.unlocked => 'Unlocked.',
        UnlockOutcome.refused =>
          'We could not confirm it was you. Try again, or log out and sign '
              'in with your password.',
        UnlockOutcome.notAvailable =>
          'This device cannot check who you are just now. Log out and sign '
              'in with your password to carry on.',
        UnlockOutcome.notEnrolled =>
          'This device has no fingerprint, face or screen lock set up, so we '
              'cannot check it is you. Log out and sign in with your '
              'password to carry on.',
        UnlockOutcome.lockedOut =>
          'Your device has paused unlocking after too many attempts. Log out '
              'and sign in with your password to carry on.',
        UnlockOutcome.failed =>
          'Something went wrong while checking. Try again, or log out and '
              'sign in with your password.',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lock = ref.watch(appLockProvider);
    final outcome = lock.lastOutcome;
    final tried = outcome != null && !outcome.isUnlocked;

    return SecureScreen(
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 88,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        // Decorative: the heading below says it in words.
                        child: ExcludeSemantics(
                          child: Icon(
                            Icons.lock_outline_rounded,
                            size: 40,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      header: true,
                      child: Text(
                        'Unlock SpendWise',
                        style: theme.textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Announced as it changes, so a screen reader user hears
                    // why the prompt closed without opening the app.
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _message(outcome),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tried ? scheme.error : scheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: lock.isAuthenticating ? null : _unlock,
                      icon: const Icon(Icons.fingerprint),
                      label: Text(
                        switch ((lock.isAuthenticating, tried)) {
                          (true, _) => 'Checking…',
                          (false, true) => 'Try again',
                          (false, false) => 'Unlock',
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: lock.isAuthenticating ? null : _signOut,
                      child: const Text('Log out instead'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
