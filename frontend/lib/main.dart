import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/network/api_config.dart';

void main() {
  // Fails fast in debug if the build was given an empty --dart-define.
  assert(ApiConfig.isConfigured);

  runApp(const ProviderScope(child: SpendWiseApp()));
}
