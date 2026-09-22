/// Compile-time configuration. The base URL is never written in a screen — it
/// arrives through `--dart-define` and is read only from here.
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000 \
///               --dart-define=APP_ENV=dev
///
/// The default targets the Android emulator, where 10.0.2.2 is the host's
/// localhost. Override it for a simulator, desktop or a physical device.
class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static const String env = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );

  /// Tripped in debug and profile builds if someone passes an empty define,
  /// which would otherwise fail much later as an opaque connection error.
  static bool get isConfigured {
    assert(baseUrl.isNotEmpty, 'API_BASE_URL must not be empty.');
    assert(env.isNotEmpty, 'APP_ENV must not be empty.');
    return baseUrl.isNotEmpty && env.isNotEmpty;
  }
}
