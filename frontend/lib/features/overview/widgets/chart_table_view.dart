import 'package:flutter/material.dart';

import '../../../core/utils/money.dart';
import '../domain/overview_data.dart';

/// A chart's numbers as a table: the accessible alternative to every chart
/// on the Overview, and the only place a value is never gated behind a
/// touch.
///
/// Takes plain data and no providers. Scrolls sideways rather than
/// overflowing at large text sizes.
class ChartTableView extends StatelessWidget {
  const ChartTableView({
    super.key,
    required this.caption,
    required this.labelHeading,
    required this.rows,
    this.totalLabel,
  });

  /// Read out before the table, and shown above it.
  final String caption;

  /// The first column's heading: "Category", "Day".
  final String labelHeading;

  final List<ChartTableRow> rows;

  /// When set, a closing row adds the amounts up under this label.
  final String? totalLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showShare = rows.any((row) => row.sharePercent != null);
    final numbers = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final total = totalLabel;
    final strong = numbers?.copyWith(fontWeight: FontWeight.w600);

    var sum = 0;
    var shareSum = 0;
    for (final row in rows) {
      sum += row.paise;
      shareSum += row.sharePercent ?? 0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(caption, style: theme.textTheme.titleSmall),
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: MediaQuery.textScalerOf(context).scale(48),
            dataRowMinHeight: 48,
            // Rows grow with the text instead of clipping it.
            dataRowMaxHeight: double.infinity,
            columnSpacing: 24,
            horizontalMargin: 8,
            columns: [
              DataColumn(label: Text(labelHeading)),
              const DataColumn(label: Text('Spent'), numeric: true),
              if (showShare)
                const DataColumn(label: Text('Share'), numeric: true),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  cells: [
                    DataCell(Text(row.label)),
                    DataCell(Text(formatPaise(row.paise), style: numbers)),
                    if (showShare)
                      DataCell(
                        Text('${row.sharePercent ?? 0}%', style: numbers),
                      ),
                  ],
                ),
              if (total != null)
                DataRow(
                  cells: [
                    DataCell(Text(total, style: strong)),
                    DataCell(Text(formatPaise(sum), style: strong)),
                    if (showShare) DataCell(Text('$shareSum%', style: strong)),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
