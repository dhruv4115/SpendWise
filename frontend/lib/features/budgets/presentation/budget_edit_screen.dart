import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/errors/bank_error.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_error_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/skeleton.dart';
import '../../auth/state/session_provider.dart';
import '../../categories/domain/category.dart';
import '../../categories/state/categories_provider.dart';
import '../../transactions/state/month_provider.dart';
import '../state/budget_edit_controller.dart';
import '../state/budgets_provider.dart';
import '../widgets/risk_badge.dart';

/// `/budgets/:category`: set one category's limit for the month on screen.
///
/// Pops the budget it saved, so the list behind it can confirm the change.
/// Dismissing without saving pops nothing and changes nothing.
class BudgetEditScreen extends ConsumerWidget {
  const BudgetEditScreen({super.key, required this.category});

  /// From the route's path parameter.
  final String category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An empty category would ask for `/budgets/`, which is the list.
    if (category.isEmpty) {
      return const _Frame(title: 'Budget', child: _NotFound());
    }

    final month = ref.watch(monthProvider);
    final target = BudgetTarget(month: month, category: category);
    final draft = ref.watch(budgetDraftProvider(target));
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    // Watched here rather than deeper in the tree, so the idempotency key is
    // fixed when the screen opens rather than when the form first appears.
    final busy = ref.watch(
      budgetEditControllerProvider(target).select((state) => state.isLoading),
    );

    return _Frame(
      title: categories.nameOf(category),
      child: draft.when(
        loading: () => const _EditSkeleton(),
        error: (error, _) => AsyncErrorView(
          error: asBankError(error),
          title: 'We could not load this budget',
          onRetry: () => ref.read(budgetsProvider(month).notifier).refresh(),
          onSignInAgain: () => ref.read(sessionProvider.notifier).signOut(),
        ),
        data: (budget) => _BudgetForm(
          target: target,
          draft: budget,
          categoryName: categories.nameOf(category),
          busy: busy,
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}

/// The empty state for a budget that cannot exist: the address had no
/// category in it.
class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      icon: Icons.search_off_rounded,
      title: 'We could not find that budget',
      message: 'The link may be out of date. Your budgets are unaffected.',
      action: FilledButton(
        onPressed: () => context.go(Routes.budgetsPath),
        child: const Text('Back to Budgets'),
      ),
    );
  }
}

/// The amount field, what it would mean, and Save.
class _BudgetForm extends ConsumerStatefulWidget {
  const _BudgetForm({
    required this.target,
    required this.draft,
    required this.categoryName,
    required this.busy,
  });

  final BudgetTarget target;

  /// The budget as it stands: this month's limit, or a blank one carrying
  /// what has already been spent in the category this month.
  final BudgetView draft;

  final String categoryName;
  final bool busy;

  @override
  ConsumerState<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends ConsumerState<_BudgetForm> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();

  /// Starts at the limit being edited. A budget that does not exist yet
  /// starts empty rather than at "0", which would be a limit of nothing.
  late final TextEditingController _amount = TextEditingController(
    text: widget.draft.limitPaise > 0
        ? paiseToInput(widget.draft.limitPaise)
        : '',
  );

  /// Errors appear once Save has been tried, then follow every keystroke —
  /// not while the first digit is still being typed.
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// The client's rules first, then the server's last word on this very
  /// amount — which goes as soon as a different one is typed.
  String? _validateAmount(String? value) {
    final own = budgetAmountValidator(value);
    if (own != null) return own;

    final edit =
        ref.read(budgetEditControllerProvider(widget.target)).valueOrNull;
    final rejected = edit?.rejectedLimitPaise;
    if (edit != null && rejected != null) {
      if (parseRupeesToPaise(value) == rejected) return edit.limitError;
    }
    return null;
  }

  Future<void> _save() async {
    final form = _form.currentState;
    if (form == null || !form.validate()) {
      setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      return;
    }
    final limitPaise = parseRupeesToPaise(_amount.text);
    // Unreachable past the validator; a return is cheaper than an assertion
    // that could fire in a customer's hands.
    if (limitPaise == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final outcome = await ref
        .read(budgetEditControllerProvider(widget.target).notifier)
        .save(limitPaise);
    if (!mounted) return;

    switch (outcome) {
      case BudgetSaved(:final budget):
        // The list is what confirms it, on the screen the customer lands on.
        context.pop(budget);

      case BudgetSaveFailed(:final error):
        setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
        // A field the server named belongs under that field, not in a
        // banner the customer has to map back onto the form themselves.
        final onField = error is ValidationError &&
            error.fieldErrors.containsKey(budgetLimitField);
        _form.currentState?.validate();
        if (onField) return;

        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Budget not saved. ${error.userMessage}'),
              duration: const Duration(seconds: 8),
              action: error.isRetryable
                  ? SnackBarAction(label: 'Retry', onPressed: _save)
                  : null,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final monthLabel = monthKeyLabel(widget.target.month);
    final draft = widget.draft;

    return Form(
      key: _form,
      autovalidateMode: _autovalidate,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'A limit covers the whole of $monthLabel, including what has '
            'already gone out of ${widget.categoryName} this month.',
            style: muted,
          ),
          const SizedBox(height: 8),
          Text(
            'Spent so far: ${formatPaise(draft.displaySpentPaise)}',
            style: theme.textTheme.titleMedium,
          ),
          if (draft.isRolledOver) ...[
            const SizedBox(height: 12),
            _CarriedOverNote(from: draft.rolledOverFrom!),
          ],
          const SizedBox(height: 24),
          TextFormField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              labelText: 'Monthly limit',
              hintText: '5,000',
              prefixText: '$rupeeSign ',
              helperText: 'Applies to this month and carries on to the next.',
              helperMaxLines: 2,
              errorMaxLines: 3,
            ),
            validator: _validateAmount,
          ),
          const SizedBox(height: 24),
          // Redraws as the amount is typed, without rebuilding the field
          // under the cursor.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _amount,
            builder: (context, value, _) => _Preview(
              budget: draft,
              limitPaise: parseRupeesToPaise(value.text),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: widget.busy ? null : _save,
            icon: const Icon(Icons.check),
            label: Text(widget.busy ? 'Saving…' : 'Save budget'),
          ),
        ],
      ),
    );
  }
}

/// What this month would look like at the amount being typed.
class _Preview extends StatelessWidget {
  const _Preview({required this.budget, required this.limitPaise});

  final BudgetView budget;

  /// Null while the field is empty or holds something that is not an amount.
  final int? limitPaise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final typed = limitPaise;

    if (typed == null || typed < 0) {
      return Text(
        'Enter an amount to see how this month is tracking against it.',
        style: muted,
      );
    }

    final preview = budget.copyWith(limitPaise: typed);
    final balance = preview.isOverLimit
        ? '${formatPaise(preview.remainingPaise.abs())} over this limit'
        : '${formatPaise(preview.remainingPaise)} left this month';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text('At this limit', style: theme.textTheme.titleSmall),
            ),
            const SizedBox(height: 12),
            BudgetRiskBar(ratio: preview.ratio, risk: preview.risk),
            const SizedBox(height: 12),
            // Announced as one phrase whenever it changes, so a screen
            // reader user hears the consequence of what they typed.
            Semantics(
              liveRegion: true,
              container: true,
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  BudgetRiskBadge(risk: preview.risk),
                  Text(
                    '${formatPaise(preview.displaySpentPaise)} of '
                    '${formatPaise(typed)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(balance, style: muted),
          ],
        ),
      ),
    );
  }
}

/// Says where a carried-over limit came from, and what saving it does.
class _CarriedOverNote extends StatelessWidget {
  const _CarriedOverNote({required this.from});

  /// `YYYY-MM`.
  final String from;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.history_rounded,
              size: MediaQuery.textScalerOf(context).scale(18),
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Carried over from ${monthKeyLabel(from)}. Saving makes it '
                'this month’s own limit.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditSkeleton extends StatelessWidget {
  const _EditSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading budget',
      liveRegion: true,
      container: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          Skeleton(height: 14),
          SizedBox(height: 8),
          Skeleton(width: 220, height: 14),
          SizedBox(height: 24),
          Skeleton(width: 160, height: 20),
          SizedBox(height: 32),
          Skeleton(height: 56, borderRadius: 4),
          SizedBox(height: 32),
          Skeleton(height: 120, borderRadius: 16),
        ],
      ),
    );
  }
}
