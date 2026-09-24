/// Keeps the app's own screens out of the recents thumbnail and out of
/// screenshots, on the screens that show somebody's money.
///
/// Android has a window flag for exactly this — `FLAG_SECURE` — reached here
/// through one method channel rather than a package, because the whole
/// implementation is two lines of Kotlin in `MainActivity`. iOS has no
/// equivalent flag, so there is no iOS handler and every call there is a
/// no-op: a missing implementation is swallowed, not surfaced.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The channel `MainActivity` listens on.
const MethodChannel secureFlagChannel = MethodChannel('spendwise/secure_flag');

/// The window flag, as its callers see it.
abstract interface class SecureFlag {
  /// Marks the window secure. Never throws.
  Future<void> enable();

  /// Clears the mark. Never throws.
  Future<void> disable();
}

/// The real one, over [secureFlagChannel].
class PlatformSecureFlag implements SecureFlag {
  const PlatformSecureFlag({MethodChannel channel = secureFlagChannel})
      : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<void> enable() => _invoke('enable');

  @override
  Future<void> disable() => _invoke('disable');

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // iOS, or a test: there is no such flag to set.
    } on PlatformException catch (error) {
      // The window was gone by the time the call landed. Worth knowing in
      // debug, never worth an error in front of a customer.
      assert(() {
        debugPrint('secure_flag: $method failed (${error.code})');
        return true;
      }());
    }
  }
}

/// Counts the screens that want the flag on.
///
/// Screens overlap: the transaction detail is pushed over the feed, and both
/// want the window secure. Without a count, the detail's [dispose] would clear
/// the flag while the feed is still on screen underneath it. So the flag is
/// set when the first screen asks and cleared when the last one lets go.
class SecureFlagController {
  SecureFlagController(this._flag);

  final SecureFlag _flag;

  int _holders = 0;

  /// How many screens currently want the window secure.
  @visibleForTesting
  int get holders => _holders;

  /// One more screen wants the window secure.
  void retain() {
    _holders += 1;
    if (_holders == 1) unawaited(_flag.enable());
  }

  /// One fewer. The flag is cleared only when the last screen has gone.
  void release() {
    if (_holders == 0) return;
    _holders -= 1;
    if (_holders == 0) unawaited(_flag.disable());
  }
}

final Provider<SecureFlag> secureFlagProvider =
    Provider<SecureFlag>((ref) => const PlatformSecureFlag());

final Provider<SecureFlagController> secureFlagControllerProvider =
    Provider<SecureFlagController>(
  (ref) => SecureFlagController(ref.watch(secureFlagProvider)),
);

/// Wraps a screen that shows money. The window is secure for as long as this
/// widget is in the tree.
///
/// Around the whole screen rather than around the figures: the recents
/// thumbnail is of the window, not of a subtree.
class SecureScreen extends ConsumerStatefulWidget {
  const SecureScreen({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends ConsumerState<SecureScreen> {
  /// Read once, and held: `dispose` runs after this widget has been taken out
  /// of the tree, which is too late to go looking for a provider.
  late final SecureFlagController _flag =
      ref.read(secureFlagControllerProvider);

  @override
  void initState() {
    super.initState();
    _flag.retain();
  }

  @override
  void dispose() {
    _flag.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
