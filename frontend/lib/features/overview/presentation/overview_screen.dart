import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/errors/bank_error.dart';
import '../../../core/security/secure_flag.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_error_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/stale_banner.dart';
import '../../auth/state/session_provider.dart';
import '../../transactions/presentation/month_switcher.dart';
import '../../transactions/state/month_provider.dart';
import '../domain/overview_data.dart';
import '../state/overview_provider.dart';
import '../state/summary_provider.dart';
import '../widgets/chart_table_view.dart';
import '../widgets/crunching_indicator.dart';
import '../widgets/daily_spend_line.dart';
import '../widgets/spend_donut.dart';
import '../widgets/summary_header_card.dart';

/// The month at a glance: the total against last month, where it went, and
/// how it was spread across the days.
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(monthProvider);
    final monthLabel = monthKeyLabel(month);

    return SecureScreen(
      // Money on screen: kept out of the recents thumbnail and screenshots.
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Overview'),
          actions: const [ProfileMenuButton()],
        ),
        body: Column(
          children: [
            // The month, the two notices about it, and then the month itself.
            const MonthSwitcher(warmSummary: true),
            StaleDataBanner(
              month: month,
              onRetry: () =>
                  ref.read(summaryProvider(month).notifier).refresh(),
            ),
            CrunchingIndicator(month: month),
            Expanded(child: _MonthBody(month: month, monthLabel: monthLabel)),
          ],
        ),
      ),
    );
  }
}

/// One month's charts, with its three states.
class _MonthBody extends ConsumerWidget {
  const _MonthBody({required this.month, required this.monthLabel});

  final String month;
  final String monthLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(overviewProvider(month));

    return RefreshIndicator(
      onRefresh: () => ref.read(summaryProvider(month).notifier).refresh(),
      child: overview.when(
        loading: () => const _OverviewSkeleton(),
        error: (error, _) => AsyncErrorView(
          error: asBankError(error),
          title: 'We could not load your overview',
          onRetry: () => ref.invalidate(summaryProvider(month)),
          onSignInAgain: () => ref.read(sessionProvider.notifier).signOut(),
        ),
        data: (data) => data.isEmpty
            ? EmptyView(
                icon: Icons.insights_outlined,
                title: 'Nothing spent in $monthLabel',
                message: 'Once payments or refunds land in this month, '
                    'where the money went will show up here.',
                action: OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(summaryProvider(month).notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              )
            : _OverviewBody(data: data, monthLabel: monthLabel),
      ),
    );
  }
}

class _OverviewBody extends ConsumerWidget {
  const _OverviewBody({required this.data, required this.monthLabel});

  final OverviewData data;
  final String monthLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showTables = ref.watch(chartTablesProvider);
    final summary = data.summary;
    final refunded = data.refundedCategories;

    return ListView(
      // Pull-to-refresh works however short the page is.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        SummaryHeaderCard(
          monthLabel: monthLabel,
          totalPaise: summary.totalPaise,
          deltaPaise: summary.deltaPaise,
          deltaPercent: summary.deltaPercent,
        ),
        const SizedBox(height: 8),
        // Above both charts, since it changes both.
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text('View as table'),
          subtitle: const Text('Each chart as rows of numbers'),
          value: showTables,
          onChanged: (value) =>
              ref.read(chartTablesProvider.notifier).set(showTables: value),
        ),
        const SizedBox(height: 8),
        _ChartSection(
          title: 'Where it went',
          footnote: refunded.isEmpty
              ? null
              : 'Not charted, because refunds outweighed spending: '
                  '${refunded.join(', ')}.',
          child: switch ((data.slices.isEmpty, showTables)) {
            (true, _) => const _SectionNote(
                'Refunds outweighed spending in every category this month, '
                'so there is no spending to chart.',
              ),
            (false, true) => ChartTableView(
                caption: 'Amounts by category',
                labelHeading: 'Category',
                rows: data.categoryRows,
                totalLabel: 'Total',
              ),
            (false, false) => SpendDonut(
                month: data.summary.month,
                slices: data.slices,
                // Pushed, so Back returns here. The feed seeds its filter
                // from the category in the address.
                onSliceTap: (slice) => context.push(
                  Routes.transactionsInCategory(slice.category!),
                ),
              ),
          },
        ),
        const SizedBox(height: 16),
        _ChartSection(
          title: 'Day by day',
          child: showTables
              ? ChartTableView(
                  caption: 'Amounts by day',
                  labelHeading: 'Day',
                  rows: data.dayRows,
                  totalLabel: 'Total',
                )
              : DailySpendLine(days: data.days),
        ),
      ],
    );
  }
}

class _ChartSection extends StatelessWidget {
  const _ChartSection({
    required this.title,
    required this.child,
    this.footnote,
  });

  final String title;
  final Widget child;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = footnote;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: 16),
            child,
            if (note != null) ...[
              const SizedBox(height: 8),
              _SectionNote(note),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionNote extends StatelessWidget {
  const _SectionNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// The shape of the page to come: a header card, a ring, a plot.
class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading overview',
      liveRegion: true,
      container: true,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: const [
          _SkeletonCard(
            children: [
              Skeleton(width: 140, height: 14),
              SizedBox(height: 12),
              Skeleton(width: 200, height: 36),
              SizedBox(height: 16),
              Skeleton(width: 240, height: 14),
            ],
          ),
          // Where the table switch will sit.
          SizedBox(height: 72),
          _SkeletonCard(
            children: [
              Skeleton(width: 120, height: 16),
              SizedBox(height: 24),
              Center(
                child: Skeleton(
                  width: SpendDonut.diameter,
                  height: SpendDonut.diameter,
                  borderRadius: SpendDonut.diameter / 2,
                ),
              ),
              SizedBox(height: 24),
              Skeleton(width: 180, height: 14),
              SizedBox(height: 16),
              Skeleton(width: 150, height: 14),
            ],
          ),
          SizedBox(height: 16),
          _SkeletonCard(
            children: [
              Skeleton(width: 100, height: 16),
              SizedBox(height: 24),
              Skeleton(height: DailySpendLine.plotHeight),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

/// The profile entry point, until a profile screen replaces it: what
/// matters is that signing out is reachable from the first screen.
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
