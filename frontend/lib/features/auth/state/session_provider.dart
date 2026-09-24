import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/offline_cache.dart';
import '../data/auth_repository.dart';
import '../domain/session.dart';

/// Where the customer stands with the app, as one closed set of cases.
///
/// A sealed union rather than a nullable [Session]: "we have not looked in the
/// keystore yet" and "there is nothing in the keystore" must not collapse into
/// the same null, or the router would bounce a returning customer to sign-in
/// for the frame it takes to read storage.
@immutable
sealed class SessionState {
  const SessionState();

  /// The session behind this state, when there is one. Null for the two states
  /// that have no customer attached.
  Session? get session => null;
}

/// Boot: the keystore has not answered yet. The splash screen is showing.
final class SessionUnknown extends SessionState {
  const SessionUnknown();

  @override
  bool operator ==(Object other) => other is SessionUnknown;

  @override
  int get hashCode => (SessionUnknown).hashCode;
}

/// No session, either because there never was one or because it was cleared.
final class SessionSignedOut extends SessionState {
  const SessionSignedOut();

  @override
  bool operator ==(Object other) => other is SessionSignedOut;

  @override
  int get hashCode => (SessionSignedOut).hashCode;
}

/// Signed in and usable.
final class SessionSignedIn extends SessionState {
  const SessionSignedIn(this.session);

  @override
  final Session session;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionSignedIn && other.session == session;

  @override
  int get hashCode => Object.hash(SessionSignedIn, session);
}

/// Signed in, but the app is behind the lock screen. The token is still valid;
/// the customer just has to prove they are the one holding the phone.
final class SessionLocked extends SessionState {
  const SessionLocked(this.session);

  @override
  final Session session;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionLocked && other.session == session;

  @override
  int get hashCode => Object.hash(SessionLocked, session);
}

/// The single source of truth for sign-in.
///
/// The router watches this and nothing else, which is what makes logout a
/// one-liner: change the state, and the guard does the navigating.
class SessionNotifier extends Notifier<SessionState> {
  /// Riverpod throws if [state] is assigned after the notifier is gone, and
  /// every mutation here finishes after an await.
  bool _disposed = false;

  @override
  SessionState build() {
    ref.onDispose(() => _disposed = true);
    // Boot reads the keystore. It starts here rather than in a widget so that
    // it happens exactly once, before the first frame asks where to go.
    unawaited(restore());
    return const SessionUnknown();
  }

  /// Reads the remembered session. Leaves [SessionUnknown] behind either way.
  Future<void> restore() async {
    final session = await ref.read(authRepositoryProvider).currentSession();
    _set(session == null ? const SessionSignedOut() : SessionSignedIn(session));
  }

  /// Called after the repository has already stored the session.
  void signIn(Session session) => _set(SessionSignedIn(session));

  /// The customer asked to leave. No navigation happens here — the router's
  /// redirect reacts to the state change.
  Future<void> signOut() => _forget();

  /// The server rejected the token. Identical to signing out, but named for
  /// what happened so a caller can tell the two apart.
  Future<void> revoke() => _forget();

  /// Holds on to the session while the app is locked.
  void lock() {
    final session = state.session;
    if (session != null) _set(SessionLocked(session));
  }

  void unlock() {
    final session = state.session;
    if (session != null) _set(SessionSignedIn(session));
  }

  Future<void> _forget() async {
    await ref.read(authRepositoryProvider).logout();
    // The saved months go with the session. They are one customer's
    // statements, and the next person to sign in on this phone must not be
    // handed them from the cache while their own are still loading.
    await ref.read(offlineCacheProvider).clear();
    _set(const SessionSignedOut());
  }

  void _set(SessionState next) {
    if (_disposed) return;
    state = next;
  }
}

final NotifierProvider<SessionNotifier, SessionState> sessionProvider =
    NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

/// Derived: true only in [SessionSignedIn]. A locked app is not signed in as
/// far as a screen is concerned — it must not show balances behind the lock.
final Provider<bool> isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(sessionProvider) is SessionSignedIn,
);
