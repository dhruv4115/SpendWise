import 'package:spendwise/features/transactions/domain/transaction.dart';

/// A transaction as the domain holds it. [at] is local time, as every model
/// stores it; it defaults to midday on 22 Sep 2026.
Transaction txn({
  String id = 'txn_0001',
  String merchantName = 'Swiggy',
  String category = 'food',
  int amountPaise = -45250,
  DateTime? at,
  String mode = 'UPI',
}) {
  return Transaction(
    id: id,
    merchantRaw: '${merchantName.toUpperCase()}*1234',
    merchantName: merchantName,
    merchantKey: merchantName.toLowerCase(),
    category: category,
    amountPaise: amountPaise,
    at: at ?? DateTime(2026, 9, 22, 12),
    mode: mode,
  );
}

/// The same transaction as the server sends it: UTC on the wire.
Map<String, Object?> txnWire({
  String id = 'txn_0001',
  String merchantName = 'Swiggy',
  String category = 'food',
  int amountPaise = -45250,
  DateTime? at,
  String mode = 'UPI',
}) {
  return txn(
    id: id,
    merchantName: merchantName,
    category: category,
    amountPaise: amountPaise,
    at: at,
    mode: mode,
  ).toJson();
}

/// A `GET /transactions` body.
Map<String, Object?> pageWire(
  List<Map<String, Object?>> items, {
  String? nextCursor,
}) {
  return {'items': items, 'nextCursor': nextCursor};
}

/// [count] spends, newest first, [perDay] to a day counting back from
/// [newest]. Ids and merchant names are numbered from [startAt], so two
/// batches can be told apart.
List<Map<String, Object?>> spendsWire(
  int count, {
  int startAt = 0,
  int perDay = 5,
  DateTime? newest,
}) {
  final first = newest ?? DateTime(2026, 9, 23, 20);
  return [
    for (var i = startAt; i < startAt + count; i++)
      txnWire(
        id: 'txn_${i.toString().padLeft(4, '0')}',
        merchantName: 'Merchant $i',
        amountPaise: -(1000 + i),
        at: DateTime(
          first.year,
          first.month,
          first.day - i ~/ perDay,
          first.hour,
          first.minute - i % perDay,
        ),
      ),
  ];
}
