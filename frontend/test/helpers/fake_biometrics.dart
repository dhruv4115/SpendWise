import 'package:spendwise/core/security/biometric_service.dart';

/// The device's authentication, without a device.
///
/// Answers each call with the next outcome in [outcomes], or with [outcome]
/// once that queue is empty — so a test can say "refuse the first time, then
/// let them in" without any timing games.
class FakeBiometricService implements BiometricService {
  FakeBiometricService({
    this.outcome = UnlockOutcome.unlocked,
    List<UnlockOutcome> outcomes = const [],
    this.hasBiometrics = true,
    this.supported = true,
  }) : _queued = [...outcomes];

  /// What every call answers once [_queued] runs out.
  final UnlockOutcome outcome;

  final bool hasBiometrics;
  final bool supported;

  final List<UnlockOutcome> _queued;

  /// The reason shown with each prompt, in order. Its length is how many
  /// times the customer was asked.
  final List<String> prompts = [];

  int get promptCount => prompts.length;

  @override
  Future<bool> canCheckBiometrics() async => hasBiometrics;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<UnlockOutcome> authenticate({required String reason}) async {
    prompts.add(reason);
    return _queued.isEmpty ? outcome : _queued.removeAt(0);
  }
}
