import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/transaction_repository.dart';
import '../domain/transaction.dart';
import 'feed_provider.dart';

/// One transaction, for its detail screen.
///
/// Taken from a loaded feed whenever one has it: no request, no skeleton, and
/// it follows every change the feed makes to that row, optimistic ones
/// included. Only a miss — a deep link, or a row from a month that is not
/// loaded — goes to the network.
class TransactionNotifier
    extends AutoDisposeFamilyAsyncNotifier<Transaction, String> {
  @override
  FutureOr<Transaction> build(String id) {
    for (final key in ref.watch(feedRegistryProvider).liveKeys) {
      final cached = ref.watch(
        feedProvider(key).select((feed) => feed.valueOrNull?.find(id)),
      );
      // Returned synchronously, so the screen never shows a loading frame
      // for a row that is already on the device.
      if (cached != null) return cached;
    }
    return ref.watch(transactionRepositoryProvider).fetchOne(id);
  }

  /// Shows [category] on a transaction that did not come from a feed, so the
  /// detail screen follows an optimistic change — and its rollback — even
  /// when there is no feed row for the change to land in.
  void setCategory(String category) {
    final current = state.valueOrNull;
    if (current == null || current.category == category) return;
    state = AsyncData(current.copyWith(category: category));
  }
}

final AutoDisposeAsyncNotifierProviderFamily<TransactionNotifier, Transaction,
        String> transactionProvider =
    AsyncNotifierProvider.autoDispose
        .family<TransactionNotifier, Transaction, String>(
  TransactionNotifier.new,
);
