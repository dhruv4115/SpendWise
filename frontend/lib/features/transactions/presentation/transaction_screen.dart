import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/errors/bank_error.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/async_error_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/skeleton.dart';
import '../../auth/state/session_provider.dart';
import '../../categories/domain/category.dart';
import '../../categories/state/categories_provider.dart';
import '../domain/transaction.dart';
import '../state/recategorise_controller.dart';
import '../state/transaction_provider.dart';
import '../widgets/category_sheet.dart';
import '../widgets/transaction_tile.dart';
import 'recategorise_flow.dart';

/// `/transactions/:id`: one transaction in full, and the two-tap way to put
/// it in a different category.
class TransactionScreen extends ConsumerWidget {
  const TransactionScreen({super.key, required this.id});

  /// From the route's path parameter.
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An empty id would ask for `/transactions/`, which is the feed.
    if (id.isEmpty) return const _Frame(child: _NotFound());

    final transaction = ref.watch(transactionProvider(id));

    return _Frame(
      child: transaction.when(
        loading: () => const _DetailSkeleton(),
        error: (error, _) => switch (asBankError(error)) {
          NotFoundError() => const _NotFound(),
          final bankError => AsyncErrorView(
              error: bankError,
              title: 'We could not load this transaction',
              onRetry: () => ref.invalidate(transactionProvider(id)),
              onSignInAgain: () => ref.read(sessionProvider.notifier).signOut(),
            ),
        },
        data: (txn) => _Details(transaction: txn),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction')),
      body: child,
    );
  }
}

/// The empty state for a detail screen: there is no such transaction.
class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      icon: Icons.search_off_rounded,
      title: 'We could not find that transaction',
      message: 'It may be from a month that is no longer available, or the '
          'link may be out of date.',
      action: FilledButton(
        onPressed: () => context.go(Routes.transactionsPath),
        child: const Text('Back to Spending'),
      ),
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details({required this.transaction});

  final Transaction transaction;

  Future<void> _changeCategory(BuildContext context, WidgetRef ref) async {
    ref
        .read(recategoriseControllerProvider(transaction.id).notifier)
        .beginEdit();

    final choice = await CategorySheet.show(context, transaction);
    if (choice == null || !context.mounted) return;

    await RecategoriseFlow.capture(context, ref, transaction).commit(choice);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    // Watching also keeps the controller alive for as long as the screen is.
    final busy = ref.watch(
      recategoriseControllerProvider(transaction.id)
          .select((state) => state.isLoading),
    );
    final categoryName = categories.nameOf(transaction.category);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _Headline(transaction: transaction),
        const SizedBox(height: 24),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              _Field(label: 'Merchant', value: transaction.merchantName),
              const Divider(),
              // The raw descriptor next to the cleaned name, so a customer
              // can match the row to a line on their bank statement.
              _Field(
                label: 'On your statement',
                value: transaction.merchantRaw,
              ),
              const Divider(),
              _Field(label: 'Date', value: dateTimeLabel(transaction.at)),
              const Divider(),
              _Field(label: 'Paid by', value: modeLabel(transaction.mode)),
              const Divider(),
              _Field(
                label: 'Category',
                value: categoryName,
                icon: categoryIcon(transaction.category),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.tonalIcon(
          onPressed: busy ? null : () => _changeCategory(context, ref),
          icon: const Icon(Icons.edit_outlined),
          label: Text(busy ? 'Saving…' : 'Change category'),
        ),
      ],
    );
  }
}

/// Merchant, amount and whether it was a refund, large and centred.
class _Headline extends StatelessWidget {
  const _Headline({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isRefund = transaction.isRefund;
    final magnitude = formatPaise(transaction.amountPaise.abs());

    return Column(
      children: [
        SizedBox.square(
          dimension: 64,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              categoryIcon(transaction.category),
              size: 32,
              color: scheme.onSecondaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          transaction.merchantName,
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Semantics(
          label: isRefund ? 'Refund of $magnitude' : 'Spent $magnitude',
          excludeSemantics: true,
          // Scaled down rather than wrapped or cut: an amount must be read
          // whole.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatSignedPaise(transaction.amountPaise),
              maxLines: 1,
              style: theme.textTheme.displaySmall?.copyWith(
                color: isRefund ? scheme.primary : scheme.onSurface,
              ),
            ),
          ),
        ),
        if (isRefund) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.undo_rounded,
                size: MediaQuery.textScalerOf(context).scale(16),
                color: scheme.primary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Refund',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: scheme.primary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A label above its value, read as one phrase. Stacked rather than side by
/// side, so a long value wraps instead of squeezing its label at 2.0 text.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final leading = icon;

    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  const SizedBox(height: 2),
                  Text(value, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
            if (leading != null) ...[
              const SizedBox(width: 12),
              // Decorative: the value says the same in words.
              ExcludeSemantics(child: Icon(leading, size: 24, color: muted)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading transaction',
      liveRegion: true,
      container: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const Center(
              child: Skeleton(width: 64, height: 64, borderRadius: 32)),
          const SizedBox(height: 16),
          const Center(child: Skeleton(width: 140, height: 20)),
          const SizedBox(height: 12),
          const Center(child: Skeleton(width: 200, height: 36)),
          const SizedBox(height: 32),
          for (var row = 0; row < 5; row++) ...[
            const Skeleton(width: 96, height: 12),
            const SizedBox(height: 8),
            const Skeleton(height: 18),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}
