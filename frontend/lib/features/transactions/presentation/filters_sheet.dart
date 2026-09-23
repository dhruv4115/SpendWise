import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/skeleton.dart';
import '../../categories/domain/category.dart';
import '../../categories/state/categories_provider.dart';
import '../domain/transaction_filter.dart';
import '../state/month_provider.dart';

/// Category, amount and dates for the Spending tab.
///
/// The sheet edits a draft and never the app-wide filter. It starts from a
/// copy of the filter it is given and hands the result back through
/// `Navigator.pop`; what happens to it is the caller's decision. Dismissing
/// the sheet returns null and changes nothing. The search is not shown here
/// and passes through untouched.
class FiltersSheet extends ConsumerStatefulWidget {
  const FiltersSheet({super.key, required this.initial, required this.month});

  final TransactionFilter initial;

  /// `YYYY-MM`: the month the feed is showing. It bounds the date picker,
  /// because a date outside it could only ever match nothing.
  final String month;

  /// Completes with the filter to apply, or null when the sheet is dismissed.
  static Future<TransactionFilter?> show(
    BuildContext context, {
    required TransactionFilter initial,
    required String month,
  }) {
    return showModalBottomSheet<TransactionFilter>(
      context: context,
      // Over the navigation bar too: this is a decision, not part of the tab.
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      sheetAnimationStyle: MediaQuery.of(context).disableAnimations
          ? AnimationStyle.noAnimation
          : null,
      builder: (_) => FiltersSheet(initial: initial, month: month),
    );
  }

  @override
  ConsumerState<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends ConsumerState<FiltersSheet> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();

  late final TextEditingController _min =
      TextEditingController(text: _amountText(widget.initial.minPaise));
  late final TextEditingController _max =
      TextEditingController(text: _amountText(widget.initial.maxPaise));

  late String? _category = widget.initial.category;

  /// Whole days, as the picker deals in them. The filter's end-of-day upper
  /// bound comes back here as its date, and goes out again the same way, so
  /// reopening the sheet and tapping Apply returns an equal filter.
  late DateTime? _from = _day(widget.initial.from);
  late DateTime? _to = _day(widget.initial.to);

  /// Errors appear once Apply has been tried, then follow every keystroke —
  /// not while the first amount is still half typed.
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;

  /// A second tap on Apply while the sheet animates away would pop the
  /// screen under it as well.
  bool _closing = false;

  static String _amountText(int? paise) =>
      paise == null ? '' : paiseToInput(paise);

  static DateTime? _day(DateTime? at) => at == null ? null : dateOnly(at);

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  /// Resets the draft only. Nothing is applied until Apply.
  void _clearAll() {
    setState(() {
      _category = null;
      _from = null;
      _to = null;
    });
    _min.clear();
    _max.clear();
  }

  void _clearDates() => setState(() {
        _from = null;
        _to = null;
      });

  Future<void> _pickDates() async {
    final first = parseMonthKey(widget.month);
    final monthEnd = DateTime(first.year, first.month + 1, 0);
    final today = dateOnly(ref.read(clockProvider)());
    // Nothing can have happened after today, so the picker stops there.
    final last =
        today.isBefore(monthEnd) && !today.isBefore(first) ? today : monthEnd;

    final from = _from;
    final to = _to;
    // The picker insists its starting range lies inside its bounds; a range
    // left over from another month simply starts afresh.
    final initial = from != null &&
            to != null &&
            !from.isBefore(first) &&
            !to.isAfter(last) &&
            !to.isBefore(from)
        ? DateTimeRange(start: from, end: to)
        : null;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      currentDate: today,
      initialDateRange: initial,
      helpText: 'Choose dates',
      saveText: 'Done',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = picked.start;
      _to = picked.end;
    });
  }

  void _apply() {
    if (_closing) return;
    final form = _form.currentState;
    if (form == null || !form.validate()) {
      setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      return;
    }
    _closing = true;
    Navigator.of(context).pop(_result());
  }

  TransactionFilter _result() {
    final to = _to;
    return widget.initial.copyWith(
      category: _category,
      minPaise: parseRupeesToPaise(_min.text),
      maxPaise: parseRupeesToPaise(_max.text),
      from: _from,
      // Inclusive: the whole of the last day, not just its first instant.
      to: to == null ? null : endOfDay(to),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      // Keeps the amount fields above the keyboard.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        child: Form(
          key: _form,
          autovalidateMode: _autovalidate,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Semantics(
                  header: true,
                  child: Text('Filters', style: theme.textTheme.titleLarge),
                ),
              ),
              // Only the middle scrolls: Apply stays in reach however large
              // the text is.
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _SectionHeading('Category'),
                      const SizedBox(height: 8),
                      _CategoryChoices(
                        selected: _category,
                        onSelected: (id) => setState(() => _category = id),
                      ),
                      const SizedBox(height: 24),
                      const _SectionHeading('Amount'),
                      const SizedBox(height: 4),
                      Text(
                        'Matches spends and refunds of this size.',
                        style: muted,
                      ),
                      const SizedBox(height: 12),
                      _AmountFields(min: _min, max: _max),
                      const SizedBox(height: 24),
                      const _SectionHeading('Dates'),
                      const SizedBox(height: 8),
                      _DateRangeField(
                        from: _from,
                        to: _to,
                        onPick: _pickDates,
                        onClear: _clearDates,
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                // Side by side while they fit, stacked once they do not.
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _clearAll,
                      child: const Text('Clear all'),
                    ),
                    FilledButton(
                      onPressed: _apply,
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

/// One chip per category plus "All categories". One can be chosen: the API
/// filters by a single category. The chosen chip carries a tick as well as
/// its colour.
class _CategoryChoices extends ConsumerWidget {
  const _CategoryChoices({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final theme = Theme.of(context);

    return categories.when(
      loading: () => Semantics(
        label: 'Loading categories',
        liveRegion: true,
        container: true,
        child: const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Skeleton(width: 120, height: 32),
            Skeleton(width: 88, height: 32),
            Skeleton(width: 104, height: 32),
            Skeleton(width: 72, height: 32),
            Skeleton(width: 96, height: 32),
          ],
        ),
      ),
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              'We could not load the categories. '
              '${asBankError(error).userMessage}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () => ref.invalidate(categoriesProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
      data: (items) {
        final chosen = selected;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All categories'),
                  selected: chosen == null,
                  onSelected: (_) => onSelected(null),
                ),
                for (final category in items)
                  ChoiceChip(
                    label: Text(category.name),
                    selected: chosen == category.id,
                    onSelected: (on) => onSelected(on ? category.id : null),
                  ),
                // A category the list does not have still shows as chosen,
                // so Apply does not quietly drop it.
                if (chosen != null && items.byId(chosen) == null)
                  ChoiceChip(
                    label: Text(fallbackCategoryName(chosen)),
                    selected: true,
                    onSelected: (_) => onSelected(null),
                  ),
              ],
            ),
            if (items.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Your bank has not sent any categories yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Minimum and maximum, in rupees. Either can be left empty.
class _AmountFields extends StatelessWidget {
  const _AmountFields({required this.min, required this.max});

  final TextEditingController min;
  final TextEditingController max;

  static const TextInputType _keyboard =
      TextInputType.numberWithOptions(decimal: true);

  @override
  Widget build(BuildContext context) {
    final minField = TextFormField(
      controller: min,
      keyboardType: _keyboard,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'Minimum',
        hintText: 'Any',
        prefixText: '$rupeeSign ',
        errorMaxLines: 3,
      ),
      validator: optionalAmountValidator,
    );
    final maxField = TextFormField(
      controller: max,
      keyboardType: _keyboard,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        labelText: 'Maximum',
        hintText: 'Any',
        prefixText: '$rupeeSign ',
        errorMaxLines: 3,
      ),
      validator: (value) => maxAmountValidator(value, min: min.text),
    );

    // Side by side reads as a range; stacked once large text would squeeze
    // each field down to a few characters.
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [minField, const SizedBox(height: 16), maxField],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: minField),
        const SizedBox(width: 16),
        Expanded(child: maxField),
      ],
    );
  }
}

class _DateRangeField extends StatelessWidget {
  const _DateRangeField({
    required this.from,
    required this.to,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? from;
  final DateTime? to;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPick,
            style: OutlinedButton.styleFrom(
              alignment: AlignmentDirectional.centerStart,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            icon: const Icon(Icons.date_range),
            label: Text(dateRangeLabel(from, to)),
          ),
        ),
        if (from != null || to != null)
          IconButton(
            tooltip: 'Clear dates',
            icon: const Icon(Icons.close),
            onPressed: onClear,
          ),
      ],
    );
  }
}
