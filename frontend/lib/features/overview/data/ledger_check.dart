/// The rule a recategorisation and its undo must keep: moving money between
/// categories never creates or destroys any. The overview's categories add up
/// to the feed, to the paise, before and after.
library;

import 'package:flutter/foundation.dart';

import '../../transactions/domain/transaction.dart';
import '../domain/month_summary.dart';
import 'aggregator.dart';

/// Why [summary] and [feed] disagree, or null when they balance.
///
/// [feed] must be the whole of [summary]'s month, unfiltered, with every page
/// loaded. "The sum of the feed" is its spend, `-sum(amountPaise)`, which is
/// what `byCategory` is denominated in; nothing is floored.
///
/// Totals first, then each category: a change that reached the feed but not
/// the server — or the other way round — still balances overall, and only
/// the per-category comparison catches it. The description names categories
/// and amounts, never a transaction.
String? ledgerMismatch(MonthSummary summary, List<Transaction> feed) {
  var categorySum = 0;
  for (final paise in summary.byCategory.values) {
    categorySum += paise;
  }

  if (categorySum != summary.totalPaise) {
    return 'byCategory sums to $categorySum paise but totalPaise is '
        '${summary.totalPaise}';
  }

  final feedSum = Aggregator.totalSpentPaise(feed);
  if (categorySum != feedSum) {
    return 'byCategory sums to $categorySum paise but the feed to $feedSum';
  }

  final fromFeed = Aggregator.byCategory(feed);
  final categories = {...summary.byCategory.keys, ...fromFeed.keys}.toList()
    ..sort();
  for (final category in categories) {
    final server = summary.byCategory[category] ?? 0;
    final local = fromFeed[category] ?? 0;
    if (server != local) {
      return '"$category" is $server paise in the summary but $local in the '
          'feed';
    }
  }
  return null;
}

/// Debug builds only: throws a [FlutterError] when [ledgerMismatch] finds a
/// difference. The whole check is inside an `assert`, so a release build
/// compiles it out.
void debugAssertLedgerBalanced(MonthSummary summary, List<Transaction> feed) {
  assert(() {
    final mismatch = ledgerMismatch(summary, feed);
    if (mismatch != null) {
      throw FlutterError('Ledger out of balance for ${summary.month}: '
          '$mismatch.');
    }
    return true;
  }());
}
