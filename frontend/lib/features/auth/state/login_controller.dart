import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../../core/network/idempotency.dart';
import '../data/auth_repository.dart';
import 'session_provider.dart';

/// What the sign-in form is doing right now.
@immutable
class LoginState {
  const LoginState({this.submitting = false, this.error});

  static const LoginState idle = LoginState();

  final bool submitting;

  /// The last failure, or null. Widgets render [BankError.userMessage].
  final BankError? error;

  LoginState copyWith({bool? submitting, BankError? error}) {
    return LoginState(
      submitting: submitting ?? this.submitting,
      error: error ?? this.error,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoginState &&
          other.submitting == submitting &&
          other.error == error;

  @override
  int get hashCode => Object.hash(submitting, error);
}

/// Drives one sign-in attempt.
///
/// Owns the idempotency key for the attempt (rule 8): one key per set of
/// credentials, reused by every retry of those credentials, replaced only when
/// the customer changes what they typed — which is a genuinely different
/// request, and which the server would otherwise reject with a 409.
class LoginController extends Notifier<LoginState> {
  final IdempotencyKeyHolder _idempotency = IdempotencyKeyHolder();

  /// Identifies the credentials the current key belongs to. A hash, not the
  /// credentials: nothing here should be able to print a password.
  int? _attempt;

  bool _disposed = false;

  @override
  LoginState build() {
    ref.onDispose(() => _disposed = true);
    return LoginState.idle;
  }

  /// Returns true when the session was established. Navigation is not this
  /// controller's business — the router's redirect follows the session state.
  Future<bool> submit({
    required String email,
    required String password,
  }) async {
    if (state.submitting) return false;

    final attempt = Object.hash(email, password);
    if (_attempt != attempt) {
      _idempotency.reset();
      _attempt = attempt;
    }

    _set(const LoginState(submitting: true));

    try {
      final session = await ref.read(authRepositoryProvider).login(
            email: email,
            password: password,
            idempotencyKey: _idempotency.key,
          );
      ref.read(sessionProvider.notifier).signIn(session);
      _set(LoginState.idle);
      return true;
    } on BankError catch (error) {
      _set(LoginState(error: error));
      return false;
    }
  }

  /// Clears the banner when the customer starts editing again, so a stale
  /// failure does not sit under a form they are already fixing.
  void dismissError() {
    if (state.error != null) _set(LoginState.idle);
  }

  void _set(LoginState next) {
    if (_disposed) return;
    state = next;
  }
}

final NotifierProvider<LoginController, LoginState> loginControllerProvider =
    NotifierProvider<LoginController, LoginState>(LoginController.new);
