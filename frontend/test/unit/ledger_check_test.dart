import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/overview/data/aggregator.dart';
import 'package:spendwise/features/overview/data/ledger_check.dart';

import '../helpers/transactions.dart';

void main() {
  final rows = [
    txn(id: 'txn_1', amountPaise: -45250),
    txn(
        id: 'txn_2',
        merchantName: 'Uber',
        category: 'transport',
        amountPaise: -18900),
    // A refund pulls its category down rather than being floored away.
    txn(
        id: 'txn_3',
        merchantName: 'Amazon',
        category: 'shopping',
        amountPaise: 20000),
  ];

  test('a summary built from the feed balances', () {
    final summary = Aggregator.summarise(rows, '2026-09');

    expect(ledgerMismatch(summary, rows), isNull);
    expect(() => debugAssertLedgerBalanced(summary, rows), returnsNormally);
  });

  test(
      'a recategorised feed against a stale summary balances in total but '
      'not by category', () {
    final stale = Aggregator.summarise(rows, '2026-09');
    final moved = [rows.first.copyWith(category: 'travel'), ...rows.skip(1)];

    final mismatch = ledgerMismatch(stale, moved);

    expect(mismatch, contains('"food"'));
    expect(mismatch, isNot(contains('txn_')),
        reason: 'a description never names a transaction');
    expect(
      () => debugAssertLedgerBalanced(stale, moved),
      throwsA(isA<FlutterError>()),
    );
  });

  test('a row missing from the feed is a total mismatch', () {
    final summary = Aggregator.summarise(rows, '2026-09');

    expect(
      ledgerMismatch(summary, rows.skip(1).toList()),
      contains('the feed to'),
    );
  });

  test('byCategory that does not add up to totalPaise is caught', () {
    final summary = Aggregator.summarise(rows, '2026-09');
    final broken = summary.copyWith(totalPaise: summary.totalPaise + 1);

    expect(ledgerMismatch(broken, rows), contains('totalPaise'));
  });
}
