import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../../core/network/idempotency.dart';
import '../data/budget_repository.dart';
import '../domain/budget.dart';
import 'budgets_provider.dart';

/// The field the server names when it rejects a limit, and the field the form
/// binds that message to.
const String budgetLimitField = 'limitPaise';

/// Distinguishes "leave the field alone" from "clear it" in the copyWith.
const Object _unset = Object();

/// Returned instead of starting a second save while one is in flight.
const ConflictError _stillSaving = ConflictError(
  code: 'SAVE_IN_PROGRESS',
  message: 'Your last change is still being saved. Try again in a moment.',
);

const UnknownError _screenClosed = UnknownError(code: 'CONTROLLER_DISPOSED');

/// What the open edit screen knows between attempts.
@immutable
class BudgetEditState {
  const BudgetEditState({
    required this.idempotencyKey,
    this.fieldErrors = const {},
    this.rejectedLimitPaise,
  });

  /// The key every attempt at this save carries — the first one and every
  /// retry of it. Fixed when the screen opens, replaced only once a save has
  /// landed, so a retry after a lost response replays rather than re-applies.
  final String idempotencyKey;

  /// What the server said was wrong, by field name. Empty until it says so.
  final Map<String, String> fieldErrors;

  /// The limit the server refused, so the form can drop the message the
  /// moment the customer types a different amount instead of leaving a stale
  /// complaint under the field.
  final int? rejectedLimitPaise;

  /// The message to show under the amount field, if any.
  String? get limitError => fieldErrors[budgetLimitField];

  BudgetEditState copyWith({
    String? idempotencyKey,
    Map<String, String>? fieldErrors,
    Object? rejectedLimitPaise = _unset,
  }) {
    return BudgetEditState(
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      fieldErrors: fieldErrors ?? this.fieldErrors,
      rejectedLimitPaise: identical(rejectedLimitPaise, _unset)
          ? this.rejectedLimitPaise
          : rejectedLimitPaise as int?,
    );
  }

  /// No key: it is a credential for replaying a change.
  @override
  String toString() => 'BudgetEditState(rejected: ${fieldErrors.keys})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BudgetEditState &&
          other.idempotencyKey == idempotencyKey &&
          other.rejectedLimitPaise == rejectedLimitPaise &&
          mapEquals(other.fieldErrors, fieldErrors);

  @override
  int get hashCode => Object.hash(
        idempotencyKey,
        rejectedLimitPaise,
        Object.hashAllUnordered(
          fieldErrors.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );
}

/// How a save ended. A failure carries the [BankError] to show; [
/// BudgetEditController.save] never throws one.
sealed class BudgetSaveOutcome {
  const BudgetSaveOutcome();
}

final class BudgetSaved extends BudgetSaveOutcome {
  const BudgetSaved(this.budget);

  final Budget budget;
}

final class BudgetSaveFailed extends BudgetSaveOutcome {
  const BudgetSaveFailed(this.error);

  final BankError error;
}

/// Saves one budget, for one category in one month.
///
/// Auto-disposed with the edit screen, and kept alive while a request is in
/// flight so a customer who backs out mid-save still has their change applied
/// and the month's rows refreshed.
class BudgetEditController
    extends AutoDisposeFamilyAsyncNotifier<BudgetEditState, BudgetTarget> {
  /// One key per open screen: survives a failed attempt, so pressing Save
  /// again replays the first request rather than sending a second one.
  final IdempotencyKeyHolder _key = IdempotencyKeyHolder();

  bool _busy = false;
  bool _disposed = false;

  @override
  BudgetEditState build(BudgetTarget target) {
    ref.onDispose(() => _disposed = true);
    // Generated now, when the screen opens — not when Save is first pressed,
    // and never again per attempt.
    return BudgetEditState(idempotencyKey: _key.key);
  }

  BudgetEditState get _value =>
      state.valueOrNull ?? BudgetEditState(idempotencyKey: _key.key);

  /// Sets this budget's limit to [limitPaise].
  ///
  /// On success the month's rows are invalidated, so the list behind this
  /// screen shows the new limit — and, for a limit that was carried over, now
  /// shows it as this month's own.
  ///
  /// A 422 lands in [BudgetEditState.fieldErrors] as well as in the outcome,
  /// so the form can show it under the field the server named.
  Future<BudgetSaveOutcome> save(int limitPaise) async {
    if (_disposed) return const BudgetSaveFailed(_screenClosed);
    if (_busy) return const BudgetSaveFailed(_stillSaving);
    _busy = true;

    final key = _key.key;
    final before = _value.copyWith(idempotencyKey: key);
    // The previous attempt's complaint goes the moment a new one starts.
    state = const AsyncLoading<BudgetEditState>().copyWithPrevious(
      AsyncData(
        before.copyWith(fieldErrors: const {}, rejectedLimitPaise: null),
      ),
    );
    final inFlight = ref.keepAlive();

    try {
      final saved = await ref.read(budgetRepositoryProvider).upsertBudget(
            category: arg.category,
            month: arg.month,
            limitPaise: limitPaise,
            idempotencyKey: key,
          );
      if (_disposed) return BudgetSaved(saved);

      ref.invalidate(budgetsProvider(arg.month));
      // This intent is finished. A further edit is a new one, and reusing
      // this key for a different amount would only earn a 409.
      _key.reset();
      state = AsyncData(BudgetEditState(idempotencyKey: _key.key));
      return BudgetSaved(saved);
    } on BankError catch (error, stackTrace) {
      if (_disposed) return BudgetSaveFailed(error);

      // A 409 means this key already carried a different request that went
      // through. It can never carry another, so the next attempt needs a new
      // one rather than failing the same way for ever.
      if (error is ConflictError) _key.reset();

      final after = before.copyWith(
        idempotencyKey: _key.key,
        fieldErrors: error is ValidationError ? error.fieldErrors : const {},
        rejectedLimitPaise: error is ValidationError ? limitPaise : null,
      );
      // Two assignments, on purpose. The provider re-applies
      // `copyWithPrevious` with its own previous state when an error is set,
      // so an error keeps whatever the state held a moment ago rather than
      // whatever the setter is handed. Putting the complaint in as data first
      // is what makes it survive the error that carries it.
      state = AsyncData(after);
      state = AsyncError<BudgetEditState>(error, stackTrace);
      return BudgetSaveFailed(error);
    } finally {
      inFlight.close();
      _busy = false;
    }
  }
}

final AutoDisposeAsyncNotifierProviderFamily<BudgetEditController,
        BudgetEditState, BudgetTarget> budgetEditControllerProvider =
    AsyncNotifierProvider.autoDispose
        .family<BudgetEditController, BudgetEditState, BudgetTarget>(
  BudgetEditController.new,
);
