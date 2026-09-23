import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_format.dart';
import '../../../core/utils/money.dart';
import '../../categories/domain/category.dart';
import '../../categories/state/categories_provider.dart';
import '../domain/transaction_filter.dart';
import '../state/filter_provider.dart';

/// What the feed is narrowed by: one chip per filter, each with its own X.
///
/// An X writes to the app-wide filter, so the list, the badge and the search
/// field all follow it. Scrolls sideways rather than wrapping: at a large
/// text size, four chips on four lines would push the list off the screen.
/// Builds nothing when no filter is applied.
class ActiveFiltersRow extends ConsumerWidget {
  const ActiveFiltersRow({super.key, required this.filter});

  final TransactionFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    FilterNotifier filters() => ref.read(filterStateNotifier.notifier);

    final category = filter.category;
    final chips = <Widget>[
      if (category != null)
        _FilterChip(
          icon: Icons.category_outlined,
          label: categories.nameOf(category),
          removeTooltip: 'Show every category',
          onRemove: () => filters().setCategory(null),
        ),
      if (filter.hasQuery)
        _FilterChip(
          icon: Icons.search,
          label: '“${filter.query.trim()}”',
          removeTooltip: 'Remove search',
          onRemove: () => filters().setQuery(''),
        ),
      if (filter.hasAmountRange)
        _FilterChip(
          icon: Icons.currency_rupee,
          label: amountRangeLabel(filter.minPaise, filter.maxPaise),
          removeTooltip: 'Remove amount filter',
          onRemove: () => filters().setAmountRange(),
        ),
      if (filter.hasDateRange)
        _FilterChip(
          icon: Icons.date_range,
          label: dateRangeLabel(filter.from, filter.to),
          removeTooltip: 'Remove date filter',
          onRemove: () => filters().setDateRange(),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();

    return Semantics(
      container: true,
      label: 'Active filters',
      explicitChildNodes: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(
          children: [
            for (final chip in chips) ...[
              chip,
              const SizedBox(width: 8),
            ],
            if (chips.length > 1)
              TextButton(
                onPressed: () => filters().clear(),
                child: const Text('Clear all'),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.removeTooltip,
    required this.onRemove,
  });

  final IconData icon;
  final String label;

  /// Also the X's accessible name, so it says what the X takes away.
  final String removeTooltip;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: Icon(icon),
      label: Text(label),
      onDeleted: onRemove,
      deleteButtonTooltipMessage: removeTooltip,
    );
  }
}
