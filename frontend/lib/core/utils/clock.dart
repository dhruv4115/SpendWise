import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Now", as a seam.
///
/// Everything that asks what month it is, how long the app has been away, or
/// whether a cached copy is stale goes through here, so a test pins the
/// calendar instead of racing it.
final Provider<DateTime Function()> clockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);
