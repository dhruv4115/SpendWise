import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The signed-in customer and their bearer token.
///
/// [toString] deliberately omits the token and the email: this object ends up
/// in error reports and provider dumps.
@immutable
class Session {
  const Session({
    required this.token,
    required this.userId,
    required this.userName,
    required this.email,
  });

  final String token;
  final String userId;
  final String userName;
  final String email;

  Session copyWith({
    String? token,
    String? userId,
    String? userName,
    String? email,
  }) {
    return Session(
      token: token ?? this.token,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      email: email ?? this.email,
    );
  }

  @override
  String toString() => 'Session(userName: $userName)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Session &&
          other.token == token &&
          other.userId == userId &&
          other.userName == userName &&
          other.email == email;

  @override
  int get hashCode => Object.hash(token, userId, userName, email);
}

/// Storage for the session. An interface so tests can substitute an in-memory
/// fake — the platform keystore is not available in a unit test.
abstract interface class SessionStore {
  Future<Session?> read();

  /// Just the bearer token, for the request interceptor.
  Future<String?> readToken();

  Future<void> write(Session session);

  Future<void> clear();
}

/// Keystore-backed implementation.
///
/// On Android the data is encrypted with AES-GCM under a key wrapped by the
/// Android KeyStore. flutter_secure_storage 11 removed the
/// `encryptedSharedPreferences` flag along with the plaintext fallback it used
/// to guard: encryption is now unconditional and stronger than the old
/// EncryptedSharedPreferences path. On iOS the items live in the keychain and
/// are readable only after the device has been unlocked once, and never sync
/// to another device.
class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                storageNamespace: _namespace,
                preferencesKeyPrefix: _namespace,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  static const String _namespace = 'spendwise';
  static const String _tokenKey = 'session.token';
  static const String _userIdKey = 'session.userId';
  static const String _userNameKey = 'session.userName';
  static const String _emailKey = 'session.email';

  final FlutterSecureStorage _storage;

  /// Every request asks for the token; the keystore is too slow to hit each
  /// time. Invalidated on every write and clear.
  Session? _cached;

  @override
  Future<Session?> read() async {
    final cached = _cached;
    if (cached != null) return cached;

    final token = await _storage.read(key: _tokenKey);
    if (token == null || token.isEmpty) return null;

    final session = Session(
      token: token,
      userId: await _storage.read(key: _userIdKey) ?? '',
      userName: await _storage.read(key: _userNameKey) ?? '',
      email: await _storage.read(key: _emailKey) ?? '',
    );
    _cached = session;
    return session;
  }

  @override
  Future<String?> readToken() async => (await read())?.token;

  @override
  Future<void> write(Session session) async {
    _cached = session;
    await _storage.write(key: _tokenKey, value: session.token);
    await _storage.write(key: _userIdKey, value: session.userId);
    await _storage.write(key: _userNameKey, value: session.userName);
    await _storage.write(key: _emailKey, value: session.email);
  }

  @override
  Future<void> clear() async {
    _cached = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _userNameKey);
    await _storage.delete(key: _emailKey);
  }
}

final Provider<SessionStore> sessionStoreProvider = Provider<SessionStore>(
  (ref) => SecureSessionStore(),
);

/// The session as the app sees it. The router guard watches this, so clearing
/// it is what sends a signed-out customer back to the sign-in screen.
class SessionNotifier extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() => ref.read(sessionStoreProvider).read();

  Future<void> signIn(Session session) async {
    await ref.read(sessionStoreProvider).write(session);
    state = AsyncData(session);
  }

  Future<void> signOut() => _forget();

  /// Called when the server rejects the token. Identical to signing out, but
  /// named for what happened so a caller can tell the two apart.
  Future<void> revoke() => _forget();

  Future<void> _forget() async {
    await ref.read(sessionStoreProvider).clear();
    state = const AsyncData(null);
  }
}

final AsyncNotifierProvider<SessionNotifier, Session?> sessionProvider =
    AsyncNotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);
