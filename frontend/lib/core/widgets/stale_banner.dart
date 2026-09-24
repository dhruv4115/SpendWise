import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cache/stale_data.dart';
import '../utils/date_format.dart';

/// Says, at the top of a screen, that the figures below came out of the cache
/// because the bank could not be reached — and offers to try again.
///
/// Renders nothing at all when the month's data is the server's, so a screen
/// can place it unconditionally.
class StaleDataBanner extends ConsumerWidget {
  const StaleDataBanner({
    super.key,
    required this.month,
    required this.onRetry,
  });

  /// `YYYY-MM`.
  final String month;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedAt = ref.watch(
      staleDataProvider(month).select((stale) => stale.savedAt),
    );
    if (savedAt == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Paired with the words, never standing in for them.
              Icon(
                Icons.cloud_off_outlined,
                size: MediaQuery.textScalerOf(context).scale(18),
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Showing saved data from ${savedAtLabel(savedAt)}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSecondaryContainer),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
