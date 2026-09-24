import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../state/summary_provider.dart';

/// Indian digit grouping, so 5,203 reads the way a customer writes it.
final NumberFormat _grouped = NumberFormat.decimalPattern('en_IN');

/// Says that a big month is being added up in the background.
///
/// The aggregation itself runs in an isolate, so this is a note about work
/// happening elsewhere rather than a spinner over a frozen screen — the
/// figures underneath stay live, and are the server's until the device's own
/// arrive. Renders nothing when there is nothing being folded.
class CrunchingIndicator extends ConsumerWidget {
  const CrunchingIndicator({super.key, required this.month});

  /// `YYYY-MM`.
  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(crunchingProvider(month));
    if (rows == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = MediaQuery.textScalerOf(context).scale(14);

    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Row(
            children: [
              SizedBox.square(
                dimension: size,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Crunching ${_grouped.format(rows)} transactions…',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
