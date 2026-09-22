import 'package:spendwise/core/security/secure_session_store.dart';
import 'package:spendwise/features/auth/domain/session.dart';

/// The customer every test signs in as.
const Session testSession = Session(
  token: 'tok_abcdef0123456789',
  user: AuthUser(
    id: 'usr_123456789abc',
    name: 'Asha Rao',
    email: 'asha@example.com',
  ),
);

/// What `POST /auth/login` returns for [testSession].
const Map<String, Object?> testLoginResponse = {
  'token': 'tok_abcdef0123456789',
  'user': {
    'id': 'usr_123456789abc',
    'name': 'Asha Rao',
    'email': 'asha@example.com',
  },
};

/// In-memory stand-in for the keystore, which does not exist in a unit test.
///
/// Counts its writes and clears so a test can assert that signing out really
/// reached storage and did not just change a field in memory.
class FakeSessionStore implements SessionStore {
  FakeSessionStore({Session? session}) : _session = session;

  Session? _session;
  int clearCount = 0;
  int writeCount = 0;

  Session? get stored => _session;

  @override
  Future<Session?> read() async => _session;

  @override
  Future<String?> readToken() async => _session?.token;

  @override
  Future<void> write(Session session) async {
    writeCount += 1;
    _session = session;
  }

  @override
  Future<void> clear() async {
    clearCount += 1;
    _session = null;
  }
}
