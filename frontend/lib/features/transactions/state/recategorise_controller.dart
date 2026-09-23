import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/utils/date_format.dart';
import '../../budgets/state/budgets_provider.dart';
import '../../merchants/state/merchants_provider.dart';
import '../../overview/state/summary_provider.dart';
import '../data/transaction_repository.dart';
import '../domain/transaction.dart';
import 'feed_provider.dart';
import 'transaction_provider.dart';

/// How long the Undo stays on offer after a recategorisation lands.
const Duration undoWindow = Duration(seconds: 5);

/// Distinguishes "leave the field alone" from "clear it" in the copyWiths.
const Object _unset = Object();

/// Returned instead of starting a second request while one is in flight.
const ConflictError _stillSaving = ConflictError(
  code: 'CHANGE_IN_PROGRESS',
  message: 'Your last change is still being saved. Try again in a moment.',
);

/// A recategorisation the server has accepted, and everything needed to take
/// it back.
@immutable
class AppliedRecategorisation {
  const AppliedRecategorisation({
    required this.transactionId,
    required this.category,
    required this.applyToMerchant,
    required this.changedIds,
    required this.previousCategories,
    required this.months,
    required this.undoToken,
  });

  /// The transaction the customer changed.
  final String transactionId;

  /// Where it went — and, with [applyToMerchant], its whole merchant.
  final String category;

  final bool applyToMerchant;

  /// Every id the server moved, in any month, loaded here or not.
  final List<String> changedIds;

  /// What each moved row that is loaded on this device showed before, keyed
  /// by id. Undo puts exactly these back. Unmodifiable.
  final Map<String, String> previousCategories;

  /// The months whose totals moved, as `YYYY-MM`. With [applyToMerchant] the
  /// change reaches months this device has never loaded, so every month is
  /// treated as affected and this set is not consulted.
  final Set<String> months;

  /// Never printed: it is a credential for reversing the change.
  final String undoToken;

  AppliedRecategorisation copyWith({
    String? transactionId,
    String? category,
    bool? applyToMerchant,
    List<String>? changedIds,
    Map<String, String>? previousCategories,
    Set<String>? months,
    String? undoToken,
  }) {
    return AppliedRecategorisation(
      transactionId: transactionId ?? this.transactionId,
      category: category ?? this.category,
      applyToMerchant: applyToMerchant ?? this.applyToMerchant,
      changedIds: changedIds ?? this.changedIds,
      previousCategories: previousCategories ?? this.previousCategories,
      months: months ?? this.months,
      undoToken: undoToken ?? this.undoToken,
    );
  }

  /// No ids and no token.
  @override
  String toString() => 'AppliedRecategorisation($category, '
      'merchant: $applyToMerchant, changed: ${changedIds.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppliedRecategorisation &&
          other.transactionId == transactionId &&
          other.category == category &&
          other.applyToMerchant == applyToMerchant &&
          other.undoToken == undoToken &&
          listEquals(other.changedIds, changedIds) &&
          mapEquals(other.previousCategories, previousCategories) &&
          setEquals(other.months, months);

  @override
  int get hashCode => Object.hash(
        transactionId,
        category,
        applyToMerchant,
        undoToken,
        Object.hashAll(changedIds),
        Object.hashAllUnordered(
          previousCategories.entries.map((e) => Object.hash(e.key, e.value)),
        ),
        Object.hashAllUnordered(months),
      );
}

/// The controller's settled state, between requests.
@immutable
class RecategoriseState {
  const RecategoriseState({this.idempotencyKey, this.applied});

  static const RecategoriseState idle = RecategoriseState();

  /// The key every attempt from the open category sheet carries. Set when the
  /// sheet opens, kept through failures and retries, cleared by a commit that
  /// lands.
  final String? idempotencyKey;

  /// The last change that landed, while it can still be undone.
  final AppliedRecategorisation? applied;

  RecategoriseState copyWith({
    Object? idempotencyKey = _unset,
    Object? applied = _unset,
  }) {
    return RecategoriseState(
      idempotencyKey: identical(idempotencyKey, _unset)
          ? this.idempotencyKey
          : idempotencyKey as String?,
      applied: identical(applied, _unset)
          ? this.applied
          : applied as AppliedRecategorisation?,
    );
  }

  @override
  String toString() => 'RecategoriseState(editing: ${idempotencyKey != null}, '
      'undoable: ${applied != null})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecategoriseState &&
          other.idempotencyKey == idempotencyKey &&
          other.applied == applied;

  @override
  int get hashCode => Object.hash(idempotencyKey, applied);
}

/// How a commit or an undo ended. A failure carries the [BankError] to show;
/// neither method throws one.
sealed class RecategoriseOutcome<T> {
  const RecategoriseOutcome();
}

final class RecategoriseSucceeded<T> extends RecategoriseOutcome<T> {
  const RecategoriseSucceeded(this.value);

  final T value;
}

final class RecategoriseFailed<T> extends RecategoriseOutcome<T> {
  const RecategoriseFailed(this.error);

  final BankError error;
}

/// Recategorises one transaction, optionally with its whole merchant, and
/// takes it back on request.
///
/// The change is optimistic: every loaded copy of every affected row moves on
/// the frame the customer taps, and moves back exactly if the server says no.
/// What it never does is reload the feed — rows are patched in place, so the
/// list under the customer's thumb does not jump.
///
/// Auto-disposed with the detail screen, but kept alive while a request is in
/// flight (a customer who backs out mid-request still gets their rollback)
/// and while the Undo is on offer (the SnackBar can outlive the screen).
class RecategoriseController
    extends AutoDisposeFamilyAsyncNotifier<RecategoriseState, String> {
  /// One key per sheet: survives a failed attempt, so a retry replays rather
  /// than re-applies; replaced only once a commit has landed.
  final IdempotencyKeyHolder _commitKey = IdempotencyKeyHolder();

  /// One key per undo, on the same terms.
  final IdempotencyKeyHolder _undoKey = IdempotencyKeyHolder();

  KeepAliveLink? _undoHold;
  AppliedRecategorisation? _heldFor;

  bool _busy = false;
  bool _disposed = false;

  @override
  RecategoriseState build(String transactionId) {
    ref.onDispose(() {
      _disposed = true;
      _undoHold = null;
      _heldFor = null;
    });
    return RecategoriseState.idle;
  }

  RecategoriseState get _value => state.valueOrNull ?? RecategoriseState.idle;

  /// The category sheet has opened. Fixes the key that every attempt from it
  /// will carry, and clears a failure left over from the last attempt.
  void beginEdit() {
    if (_busy || _disposed) return;
    state = AsyncData(_value.copyWith(idempotencyKey: _commitKey.key));
  }

  /// Moves [transaction] to [category], and with [applyToMerchant] every
  /// transaction sharing its merchant key.
  ///
  /// 1. Every loaded copy moves on this frame.
  /// 2. The PATCH goes out with this sheet's idempotency key.
  /// 3. On success the optimistic rows stand, the undo token is kept, and the
  ///    summary, budgets and merchants of the affected months are invalidated
  ///    — once each, and never the feed.
  /// 4. On failure every row goes back to exactly what it showed, and the
  ///    [BankError] is both the outcome and the state.
  Future<RecategoriseOutcome<AppliedRecategorisation>> commit({
    required Transaction transaction,
    required String category,
    required bool applyToMerchant,
  }) async {
    assert(transaction.id == arg, 'This controller is for another transaction');
    if (_disposed) return const RecategoriseFailed(_screenClosed);
    if (_busy) return const RecategoriseFailed(_stillSaving);
    _busy = true;

    final target = transaction;
    final key = _commitKey.key;
    final before = _value.copyWith(idempotencyKey: key);

    // A new change retires the Undo of the last one.
    _releaseHold();

    bool affected(Transaction txn) => applyToMerchant
        ? txn.merchantKey == target.merchantKey
        : txn.id == target.id;
    final optimistic = <String, String>{
      if (target.category != category) target.id: target.category,
      ..._applyEverywhere(category, where: affected),
    };
    _showOnDetail(target.id, category);
    state = const AsyncLoading<RecategoriseState>()
        .copyWithPrevious(AsyncData(before));
    final inFlight = ref.keepAlive();

    try {
      final result = await ref.read(transactionRepositoryProvider).recategorise(
            id: target.id,
            category: category,
            applyToMerchant: applyToMerchant,
            idempotencyKey: key,
          );
      if (_disposed) return const RecategoriseFailed(_screenClosed);

      // Rows the server moved that loaded while the request was out still
      // show their old category.
      final changed = result.changedIds.toSet();
      final lateArrivals = _applyEverywhere(
        result.updated.category,
        where: (txn) => changed.contains(txn.id),
      );
      final seen = {...lateArrivals, ...optimistic};

      final change = AppliedRecategorisation(
        transactionId: target.id,
        category: result.updated.category,
        applyToMerchant: applyToMerchant,
        changedIds: result.changedIds,
        // Only what the server says it moved: a row it left alone — already
        // in this category over there — is left alone by the undo too.
        previousCategories: Map.unmodifiable({
          for (final id in result.changedIds)
            if (seen[id] case final String previous) id: previous,
        }),
        months: {serverMonthKey(target.at)},
        undoToken: result.undoToken,
      );

      _commitKey.reset();
      _undoKey.reset();
      _invalidateDownstream(change);
      _holdForUndo(change);
      state = AsyncData(RecategoriseState(applied: change));
      return RecategoriseSucceeded(change);
    } on BankError catch (error, stackTrace) {
      if (_disposed) return RecategoriseFailed(error);

      _restoreEverywhere(optimistic, ifStill: category);
      _showOnDetail(target.id, target.category);
      // A 409 means this key already carried a different request that went
      // through. It can never carry another, so the next attempt needs a new
      // one rather than failing the same way for ever.
      if (error is ConflictError) _commitKey.reset();

      state = AsyncError<RecategoriseState>(error, stackTrace).copyWithPrevious(
        AsyncData(
          before.copyWith(idempotencyKey: _commitKey.hasKey ? key : null),
        ),
      );
      return RecategoriseFailed(error);
    } finally {
      inFlight.close();
      _busy = false;
    }
  }

  /// Takes back the change in [RecategoriseState.applied].
  ///
  /// Every row goes back on this frame; then the undo is sent. If the server
  /// refuses, the change is shown again — the server still has it.
  Future<RecategoriseOutcome<List<String>>> undo() async {
    if (_disposed) return const RecategoriseFailed(_screenClosed);
    if (_busy) return const RecategoriseFailed(_stillSaving);

    final before = _value;
    final change = before.applied;
    if (change == null) return const RecategoriseFailed(_nothingToUndo);
    _busy = true;

    _restoreEverywhere(change.previousCategories, ifStill: change.category);
    if (change.previousCategories[change.transactionId] case final previous?) {
      _showOnDetail(change.transactionId, previous);
    }
    state = const AsyncLoading<RecategoriseState>()
        .copyWithPrevious(AsyncData(before));
    final inFlight = ref.keepAlive();

    try {
      final restoredIds = await ref
          .read(transactionRepositoryProvider)
          .undo(change.undoToken, idempotencyKey: _undoKey.key);
      if (_disposed) return RecategoriseSucceeded(restoredIds);

      await _rereadUnseen(restoredIds, change);
      if (_disposed) return RecategoriseSucceeded(restoredIds);

      _undoKey.reset();
      _releaseHold();
      _invalidateDownstream(change);
      state = AsyncData(before.copyWith(applied: null));
      return RecategoriseSucceeded(restoredIds);
    } on BankError catch (error, stackTrace) {
      if (_disposed) return RecategoriseFailed(error);

      _applyEverywhere(
        change.category,
        where: (txn) => change.previousCategories.containsKey(txn.id),
      );
      _showOnDetail(change.transactionId, change.category);
      state = AsyncError<RecategoriseState>(error, stackTrace)
          .copyWithPrevious(AsyncData(before));
      return RecategoriseFailed(error);
    } finally {
      inFlight.close();
      _busy = false;
    }
  }

  /// The Undo for [change] is no longer on offer — its SnackBar has closed.
  /// Lets this controller go once nothing is watching it.
  ///
  /// Ignored for any change but the one currently held, so a late call from
  /// a SnackBar that a newer one replaced cannot drop the newer Undo.
  void releaseUndo(AppliedRecategorisation change) {
    if (identical(change, _heldFor)) _releaseHold();
  }

  void _holdForUndo(AppliedRecategorisation change) {
    _undoHold?.close();
    _undoHold = ref.keepAlive();
    _heldFor = change;
  }

  void _releaseHold() {
    _undoHold?.close();
    _undoHold = null;
    _heldFor = null;
  }

  List<FeedNotifier> get _liveFeeds => [
        for (final key in ref.read(feedRegistryProvider).liveKeys)
          ref.read(feedProvider(key).notifier),
      ];

  /// [FeedNotifier.applyCategory] on every live feed. Returns the previous
  /// category of every row it moved.
  Map<String, String> _applyEverywhere(
    String category, {
    required bool Function(Transaction txn) where,
  }) {
    final previous = <String, String>{};
    for (final feed in _liveFeeds) {
      previous.addAll(feed.applyCategory(category, where: where));
    }
    return previous;
  }

  void _restoreEverywhere(
    Map<String, String> previous, {
    required String ifStill,
  }) {
    for (final feed in _liveFeeds) {
      feed.restoreCategories(previous, ifStill: ifStill);
    }
  }

  /// Reaches a detail screen whose transaction did not come from a feed.
  void _showOnDetail(String id, String category) {
    final detail = transactionProvider(id);
    if (ref.exists(detail)) ref.read(detail.notifier).setCategory(category);
  }

  bool _isLoaded(String id) => ref
      .read(feedRegistryProvider)
      .liveKeys
      .any((key) => ref.read(feedProvider(key)).valueOrNull?.find(id) != null);

  /// The server put back rows this device loaded only after the change had
  /// landed — it never saw what they were before. Asks the server for each.
  ///
  /// A failure here leaves that row showing the change until the feed next
  /// refreshes; it never turns a successful undo into a failed one.
  Future<void> _rereadUnseen(
    List<String> restoredIds,
    AppliedRecategorisation change,
  ) async {
    final unseen = [
      for (final id in restoredIds)
        if (!change.previousCategories.containsKey(id) && _isLoaded(id)) id,
    ];
    if (unseen.isEmpty) return;

    final repository = ref.read(transactionRepositoryProvider);
    final fresh = await Future.wait([
      for (final id in unseen)
        repository
            .fetchOne(id)
            .then<Transaction?>((txn) => txn)
            .onError<BankError>((_, __) => null),
    ]);
    if (_disposed) return;

    for (final txn in fresh.whereType<Transaction>()) {
      _applyEverywhere(txn.category, where: (row) => row.id == txn.id);
    }
  }

  /// Everything whose figures depend on which category a transaction is in.
  ///
  /// A single transaction moves its own month's figures. A whole merchant
  /// moves every month it ever appeared in — most of which this device has
  /// never loaded — so each family is invalidated in full. Only instances
  /// that exist refetch, and only when something is watching them.
  void _invalidateDownstream(AppliedRecategorisation change) {
    if (change.changedIds.isEmpty) return;

    if (change.applyToMerchant) {
      ref
        ..invalidate(summaryProvider)
        ..invalidate(budgetsProvider)
        ..invalidate(merchantsProvider);
      return;
    }
    for (final month in change.months) {
      ref
        ..invalidate(summaryProvider(month))
        ..invalidate(budgetsProvider(month))
        ..invalidate(merchantsProvider(month));
    }
  }
}

const UnknownError _screenClosed = UnknownError(code: 'CONTROLLER_DISPOSED');

const NotFoundError _nothingToUndo = NotFoundError(
  code: 'NOTHING_TO_UNDO',
  message: 'There is no change to undo.',
);

final AutoDisposeAsyncNotifierProviderFamily<RecategoriseController,
        RecategoriseState, String> recategoriseControllerProvider =
    AsyncNotifierProvider.autoDispose
        .family<RecategoriseController, RecategoriseState, String>(
  RecategoriseController.new,
);
