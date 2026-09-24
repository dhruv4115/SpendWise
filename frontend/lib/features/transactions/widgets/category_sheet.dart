import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/async_error_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/skeleton.dart';
import '../../categories/domain/category.dart';
import '../../categories/state/categories_provider.dart';
import '../domain/transaction.dart';
import 'transaction_tile.dart';

/// What the customer picked in the [CategorySheet].
@immutable
class CategoryChoice {
  const CategoryChoice({required this.category, required this.applyToMerchant});

  final String category;
  final bool applyToMerchant;

  CategoryChoice copyWith({String? category, bool? applyToMerchant}) {
    return CategoryChoice(
      category: category ?? this.category,
      applyToMerchant: applyToMerchant ?? this.applyToMerchant,
    );
  }

  @override
  String toString() => 'CategoryChoice($category, merchant: $applyToMerchant)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryChoice &&
          other.category == category &&
          other.applyToMerchant == applyToMerchant;

  @override
  int get hashCode => Object.hash(category, applyToMerchant);
}

/// The category picker: every category as a large tile, two to a row.
///
/// Tapping a tile *is* the commit — there is no Save button, which is what
/// keeps a recategorisation to two taps. So the "whole merchant" switch sits
/// above the tiles, where it is read before the choice rather than after.
///
/// With [lockToMerchant] the switch is not offered: the sheet was opened from
/// the merchant's own screen, where changing one payment of theirs is not
/// what was asked for. The line above the tiles says so instead.
class CategorySheet extends ConsumerStatefulWidget {
  const CategorySheet({
    super.key,
    required this.transaction,
    this.lockToMerchant = false,
  });

  /// The transaction being recategorised. With [lockToMerchant] it stands for
  /// its whole merchant, and is the row the request is addressed to.
  final Transaction transaction;

  /// Whether the choice always applies to every transaction of this
  /// merchant.
  final bool lockToMerchant;

  /// Completes with the choice, or null when the sheet is dismissed or the
  /// pick would change nothing.
  static Future<CategoryChoice?> show(
    BuildContext context,
    Transaction transaction, {
    bool lockToMerchant = false,
  }) {
    return showModalBottomSheet<CategoryChoice>(
      context: context,
      // Over the navigation bar too: this is a decision, not part of the tab.
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => CategorySheet(
        transaction: transaction,
        lockToMerchant: lockToMerchant,
      ),
    );
  }

  @override
  ConsumerState<CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<CategorySheet> {
  bool _applyToMerchant = false;

  /// A second tap while the sheet animates away would pop the screen under
  /// it as well.
  bool _picked = false;

  bool get _merchantWide => widget.lockToMerchant || _applyToMerchant;

  void _pick(String category) {
    if (_picked) return;
    _picked = true;

    final unchanged = category == widget.transaction.category && !_merchantWide;
    Navigator.of(context).pop(
      unchanged
          ? null
          : CategoryChoice(
              category: category,
              applyToMerchant: _merchantWide,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final txn = widget.transaction;
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Change category',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    // One payment's amount would misdescribe a change that
                    // moves every payment this merchant has ever taken.
                    widget.lockToMerchant
                        ? txn.merchantName
                        : '${txn.merchantName} · '
                            '${formatSignedPaise(txn.amountPaise)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (widget.lockToMerchant)
              // Not a switch that happens to be on: there is no choice to
              // make here, and a disabled control would only invite one.
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: const Icon(Icons.storefront_outlined),
                title: Text('Applies to all ${txn.merchantName} transactions'),
                subtitle:
                    const Text('Past ones now, and new ones as they arrive.'),
              )
            else
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                value: _applyToMerchant,
                onChanged: (value) => setState(() => _applyToMerchant = value),
                title:
                    Text('Also apply to all ${txn.merchantName} transactions'),
                subtitle:
                    const Text('Past ones now, and new ones as they arrive.'),
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: categories.when(
                loading: () => const _GridSkeleton(),
                error: (error, _) => AsyncErrorView(
                  error: asBankError(error),
                  title: 'We could not load the categories',
                  onRetry: () => ref.invalidate(categoriesProvider),
                ),
                data: (items) => items.isEmpty
                    ? EmptyView(
                        icon: Icons.category_outlined,
                        title: 'No categories to choose from',
                        message: 'Your bank has not sent any categories yet. '
                            'Try again in a moment.',
                        action: OutlinedButton.icon(
                          onPressed: () => ref.invalidate(categoriesProvider),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                      )
                    : _CategoryGrid(
                        categories: items,
                        current: txn.category,
                        onPick: _pick,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two columns while a category name fits on a tile at the customer's text
/// size; one column once it would have to break mid-word.
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.categories,
    required this.current,
    required this.onPick,
  });

  final List<Category> categories;
  final String current;
  final ValueChanged<String> onPick;

  /// Narrowest a tile can be at 1.0 text scale and still fit "Entertainment".
  static const double minTileWidth = 132;
  static const double gap = 12;

  @override
  Widget build(BuildContext context) {
    final minWidth = MediaQuery.textScalerOf(context).scale(minTileWidth);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= minWidth * 2 + gap ? 2 : 1;

        final rows = <Widget>[];
        for (var start = 0; start < categories.length; start += columns) {
          if (start > 0) rows.add(const SizedBox(height: gap));
          rows.add(
            // Every tile in a row is as tall as the tallest, so a name that
            // wraps does not leave its neighbour looking shorter.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) const SizedBox(width: gap),
                    Expanded(
                      child: start + column < categories.length
                          ? _CategoryTile(
                              category: categories[start + column],
                              isCurrent:
                                  categories[start + column].id == current,
                              onTap: () =>
                                  onPick(categories[start + column].id),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}

/// One large tap target. The current category is marked with a tick and the
/// word "Current", not only with a different colour.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.isCurrent,
    required this.onTap,
  });

  final Category category;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground =
        isCurrent ? scheme.onSecondaryContainer : scheme.onSurface;

    return Semantics(
      button: true,
      selected: isCurrent,
      label: isCurrent ? '${category.name}, current category' : category.name,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color:
            isCurrent ? scheme.secondaryContainer : scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isCurrent ? scheme.secondary : scheme.outlineVariant,
            width: isCurrent ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(categoryIcon(category.id), size: 28, color: foreground),
                  const SizedBox(height: 8),
                  Text(
                    category.name,
                    textAlign: TextAlign.center,
                    style:
                        theme.textTheme.labelLarge?.copyWith(color: foreground),
                  ),
                  if (isCurrent) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_rounded,
                          size: MediaQuery.textScalerOf(context).scale(14),
                          color: foreground,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Current',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: foreground),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading categories',
      liveRegion: true,
      container: true,
      child: Column(
        children: [
          for (var row = 0; row < 3; row++) ...[
            if (row > 0) const SizedBox(height: _CategoryGrid.gap),
            const Row(
              children: [
                Expanded(child: Skeleton(height: 88, borderRadius: 16)),
                SizedBox(width: _CategoryGrid.gap),
                Expanded(child: Skeleton(height: 88, borderRadius: 16)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
