import 'package:flutter/foundation.dart';

/// The signed-in customer, as `POST /auth/login` describes them.
@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
  });

  /// Parses `{ "id", "name", "email" }`.
  ///
  /// The `dynamic` that `jsonDecode` hands back stops here: every value is
  /// narrowed to a `String` before it leaves this factory, so nothing above
  /// the model layer ever handles an untyped value.
  factory AuthUser.fromJson(Map<String, Object?> json) {
    return AuthUser(
      id: _requireString(json['id'], 'id'),
      name: _requireString(json['name'], 'name'),
      email: _requireString(json['email'], 'email'),
    );
  }

  final String id;
  final String name;
  final String email;

  AuthUser copyWith({String? id, String? name, String? email}) {
    return AuthUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
    );
  }

  /// The id and the email are deliberately absent: this object reaches crash
  /// reports and provider dumps, and neither belongs in a log line.
  @override
  String toString() => 'AuthUser(name: $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          other.id == id &&
          other.name == name &&
          other.email == email;

  @override
  int get hashCode => Object.hash(id, name, email);
}

/// A bearer token and the customer it belongs to.
///
/// [userId], [name] and [email] are read straight off [user]; they exist so a
/// caller that only wants one field does not have to reach through it.
@immutable
class Session {
  const Session({required this.token, required this.user});

  /// Parses the sign-in envelope, `{ "token", "user": { … } }`.
  factory Session.fromJson(Map<String, Object?> json) {
    final Object? user = json['user'];
    if (user is! Map) {
      throw const FormatException('Sign-in response has no user object.');
    }
    return Session(
      token: _requireString(json['token'], 'token'),
      user: AuthUser.fromJson(Map<String, Object?>.from(user)),
    );
  }

  final String token;
  final AuthUser user;

  String get userId => user.id;
  String get name => user.name;
  String get email => user.email;

  Session copyWith({String? token, AuthUser? user}) {
    return Session(token: token ?? this.token, user: user ?? this.user);
  }

  /// Never prints the token. Rule 13 is not a matter of remembering to redact
  /// at each call site; the object simply cannot say it.
  @override
  String toString() => 'Session(user: $user)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Session && other.token == token && other.user == user;

  @override
  int get hashCode => Object.hash(token, user);
}

String _requireString(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Sign-in response is missing "$field".');
}
