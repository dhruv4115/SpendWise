import 'package:flutter/material.dart';

import '../errors/bank_error.dart';

/// The error branch of `AsyncValue.when`: what went wrong in plain words, and
/// a way forward.
///
/// Renders [BankError.userMessage] and never the exception itself. The icon
/// changes with the kind of failure, but the words always carry the meaning on
/// their own. Scrolls rather than overflows at a 2.0 text scale.
class AsyncErrorView extends StatelessWidget {
  const AsyncErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.onSignInAgain,
    this.title = 'We could not load this',
  });

  final BankError error;

  /// Usually invalidates the provider that failed.
  final VoidCallback onRetry;

  /// Offered only when [error] is an [UnauthorisedError]; retrying with a
  /// dead session fails the same way every time.
  final VoidCallback? onSignInAgain;

  final String title;

  IconData get _icon => switch (error) {
        NetworkError() => Icons.wifi_off_rounded,
        UnauthorisedError() => Icons.lock_clock_outlined,
        RateLimitedError() => Icons.hourglass_bottom_rounded,
        ServerError() => Icons.cloud_off_outlined,
        _ => Icons.error_outline,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final signIn = onSignInAgain;
    final traceId = error.traceId;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Decorative: the title and message below say the same thing.
              Icon(_icon, size: 48, color: muted),
              const SizedBox(height: 16),
              // Announced as soon as it appears, so a screen reader user is not
              // left listening to silence after a failed load.
              Semantics(
                liveRegion: true,
                container: true,
                child: Column(
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.userMessage,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
              if (signIn != null && error is UnauthorisedError) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: signIn,
                  child: const Text('Sign in again'),
                ),
              ],
              // Identifies the failed request, not the customer, so support
              // can find it in the server log.
              if (traceId != null) ...[
                const SizedBox(height: 16),
                SelectableText(
                  'Reference: $traceId',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
