import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file in this directory tree.
///
/// Goldens are generated on a developer's Mac and checked on CI's Linux.
/// Text is already platform-neutral in tests (the test font draws boxes),
/// but anti-aliasing along a curve — the edge of a donut slice — can differ
/// by a handful of pixels between the two rasterisers. This accepts a
/// difference of up to half a percent of the image: far below what a wrong
/// colour, a missing slice or a moved label would cost, far above edge
/// noise.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final comparator = goldenFileComparator;
  if (comparator is LocalFileComparator) {
    goldenFileComparator = _TolerantComparator(
      comparator.basedir.resolve('flutter_test_config.dart'),
      tolerance: 0.005,
    );
  }
  await testMain();
}

class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile, {required this.tolerance});

  /// A fraction of the image's pixels: 0.005 is half a percent.
  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }

    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
