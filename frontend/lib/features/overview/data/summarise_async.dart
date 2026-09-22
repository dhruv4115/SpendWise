import 'package:flutter/foundation.dart';

import '../../transactions/domain/transaction.dart';
import '../domain/month_summary.dart';
import 'aggregator.dart';

/// Above this many rows, summarising moves to a background isolate.
///
/// The stress month in the seed data is 5,200 transactions. Folding that many
/// on the main isolate is a handful of milliseconds — not a freeze, but enough
/// to clip a frame during the animation into the Overview screen. Below the
/// threshold the hop costs more than the work: an isolate has to be spawned
/// and every row copied through JSON both ways.
const int isolateThresholdRows = 2000;

/// [Aggregator.summarise], off the main isolate when the month is large.
///
/// The result is identical either way — same integers, same ordering — so the
/// caller never has to care which path ran.
Future<MonthSummary> summariseAsync(
  List<Transaction> txns,
  String month, {
  int prevTotalPaise = 0,
}) async {
  if (txns.length <= isolateThresholdRows) {
    return Aggregator.summarise(txns, month, prevTotalPaise: prevTotalPaise);
  }

  final summary = await compute(
    summariseIsolateEntry,
    <String, Object?>{
      'month': month,
      'prevTotalPaise': prevTotalPaise,
      'items': [for (final txn in txns) txn.toJson()],
    },
  );
  return MonthSummary.fromJson(summary);
}

/// The isolate entry point.
///
/// Top-level and taking a single JSON-encodable argument, because that is all
/// an isolate boundary can be relied on to carry: no closures, no captured
/// state, nothing that holds a reference back to the UI isolate. It returns
/// JSON for the same reason.
///
/// Rebuilding [Transaction]s here re-runs the UTC-to-local conversion in the
/// background isolate, which shares the device's time zone, so the day
/// buckets come out the same as they would have on the main isolate.
Map<String, Object?> summariseIsolateEntry(Map<String, Object?> payload) {
  final month = payload['month']! as String;
  final prevTotalPaise = payload['prevTotalPaise']! as int;
  final rows = payload['items']! as List<Object?>;

  final txns = [
    for (final row in rows)
      Transaction.fromJson(Map<String, Object?>.from(row! as Map)),
  ];

  return Aggregator.summarise(
    txns,
    month,
    prevTotalPaise: prevTotalPaise,
  ).toJson();
}
