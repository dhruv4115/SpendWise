import 'package:flutter/material.dart';

import '../core/network/api_config.dart';
import 'theme.dart';

/// The root widget. Routing arrives in a later phase; for now the app boots
/// straight into a screen that proves the theme and the compile-time
/// configuration are wired up.
class SpendWiseApp extends StatelessWidget {
  const SpendWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpendWise',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const EnvironmentScreen(),
    );
  }
}

/// Placeholder home: shows which API the build is pointed at, and renders the
/// three budget-risk signals so it is obvious that each one carries an icon
/// and a word as well as a colour.
class EnvironmentScreen extends StatelessWidget {
  const EnvironmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final risk = theme.extension<BudgetRiskTheme>()!;

    return Scaffold(
      appBar: AppBar(title: const Text('SpendWise')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Build configuration',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _ConfigRow(label: 'Environment', value: ApiConfig.env),
                  const SizedBox(height: 8),
                  _ConfigRow(label: 'API base URL', value: ApiConfig.baseUrl),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Budget risk signals', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RiskChip(style: risk.safe),
              _RiskChip(style: risk.warning),
              _RiskChip(style: risk.over),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfigRow extends StatelessWidget {
  const _ConfigRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Wraps instead of sitting in a fixed-width row, so it survives a 2.0
    // text scale on a narrow screen.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _RiskChip extends StatelessWidget {
  const _RiskChip({required this.style});

  final RiskStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: style.containerColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 18, color: style.onContainerColor),
          const SizedBox(width: 6),
          // Flexible so a long label wraps inside the chip at large text
          // scales instead of overflowing the row.
          Flexible(
            child: Text(
              style.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: style.onContainerColor,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
