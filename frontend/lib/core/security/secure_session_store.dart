import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/domain/session.dart';

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
  static const String _nameKey = 'session.name';
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
      user: AuthUser(
        id: await _storage.read(key: _userIdKey) ?? '',
        name: await _storage.read(key: _nameKey) ?? '',
        email: await _storage.read(key: _emailKey) ?? '',
      ),
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
    await _storage.write(key: _nameKey, value: session.name);
    await _storage.write(key: _emailKey, value: session.email);
  }

  @override
  Future<void> clear() async {
    _cached = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _nameKey);
    await _storage.delete(key: _emailKey);
  }
}

final Provider<SessionStore> sessionStoreProvider = Provider<SessionStore>(
  (ref) => SecureSessionStore(),
);
