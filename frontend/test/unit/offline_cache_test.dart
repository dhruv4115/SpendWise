import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/cache/offline_cache.dart';

/// A month's summary, small enough to read at a glance in a failure message.
Map<String, Object?> _summary(String month) => {
      'month': month,
      'totalPaise': 123456,
      'byCategory': {'food': 123456},
    };

void main() {
  late Directory root;
  late Directory cacheDirectory;

  setUp(() {
    root = Directory.systemTemp.createTempSync('spendwise_cache_test');
    cacheDirectory = Directory('${root.path}/cache');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  FileOfflineCache cache() =>
      FileOfflineCache(directory: () async => cacheDirectory);

  File fileFor(String key) => File('${cacheDirectory.path}/$key.json');

  group('reading back what was written', () {
    test('a payload survives the round trip, with when it was saved', () async {
      final subject = cache();
      final before = DateTime.now();

      await subject.write(summaryCacheKey('2026-09'), _summary('2026-09'));
      final entry = await subject.read(summaryCacheKey('2026-09'));

      expect(entry, isNotNull);
      expect(entry!.payload, _summary('2026-09'));
      expect(
          entry.savedAt.isBefore(before.subtract(const Duration(seconds: 1))),
          isFalse);
      expect(entry.isFresh, isTrue);
      expect(entry.isFreshAt(entry.savedAt.add(const Duration(hours: 25))),
          isFalse);
    });

    test('a key nothing has been written under is simply a miss', () async {
      expect(await cache().read(transactionsCacheKey('2026-09')), isNull);
    });

    test('a second write replaces the first', () async {
      final subject = cache();

      await subject.write(summaryCacheKey('2026-09'), _summary('2026-09'));
      await subject.write(summaryCacheKey('2026-09'), const {'totalPaise': 1});

      final entry = await subject.read(summaryCacheKey('2026-09'));
      expect(entry!.payload, const {'totalPaise': 1});
    });

    test('nothing but a month of transactions or a summary can be stored',
        () async {
      final subject = cache();

      // There is no key shape a session could be written under, which is the
      // whole of the protection: the keystore keeps the token.
      await expectLater(
        subject.write('session', const {'token': 'tok_123'}),
        throwsA(isA<AssertionError>()),
      );
      expect(fileFor('session').existsSync(), isFalse);
      expect(await subject.read('session'), isNull);
      expect(monthOfCacheKey('session'), isNull);
    });
  });

  group('eviction', () {
    test('keeps exactly the three most recently written months', () async {
      final subject = cache();

      for (final month in ['2026-05', '2026-06', '2026-07', '2026-08']) {
        await subject.write(transactionsCacheKey(month), {'items': <Object>[]});
        await subject.write(summaryCacheKey(month), _summary(month));
      }

      expect(await subject.months(), ['2026-08', '2026-07', '2026-06']);

      // Both of the oldest month's files are gone, from disk as well as from
      // the index.
      expect(await subject.read(transactionsCacheKey('2026-05')), isNull);
      expect(await subject.read(summaryCacheKey('2026-05')), isNull);
      expect(fileFor(transactionsCacheKey('2026-05')).existsSync(), isFalse);
      expect(fileFor(summaryCacheKey('2026-05')).existsSync(), isFalse);

      // And the three that are left are whole.
      for (final month in ['2026-06', '2026-07', '2026-08']) {
        expect(await subject.read(summaryCacheKey(month)), isNotNull,
            reason: month);
        expect(await subject.read(transactionsCacheKey(month)), isNotNull,
            reason: month);
      }
    });

    test('rewriting a month makes it the newest again', () async {
      final subject = cache();
      for (final month in ['2026-06', '2026-07', '2026-08']) {
        await subject.write(summaryCacheKey(month), _summary(month));
      }

      // June is touched, so September pushes out July rather than June.
      await subject.write(summaryCacheKey('2026-06'), _summary('2026-06'));
      await subject.write(summaryCacheKey('2026-09'), _summary('2026-09'));

      expect(await subject.months(), ['2026-09', '2026-06', '2026-08']);
      expect(await subject.read(summaryCacheKey('2026-07')), isNull);
      expect(await subject.read(summaryCacheKey('2026-06')), isNotNull);
    });
  });

  group('a file that cannot be read', () {
    test('is discarded rather than thrown', () async {
      final subject = cache();
      await subject.write(summaryCacheKey('2026-09'), _summary('2026-09'));

      // Killed mid-write, or half-flushed by the platform.
      fileFor(summaryCacheKey('2026-09')).writeAsStringSync('{"savedAt":"20');

      expect(await subject.read(summaryCacheKey('2026-09')), isNull);
      expect(
        fileFor(summaryCacheKey('2026-09')).existsSync(),
        isFalse,
        reason: 'and is cleared away, so it cannot fail a second time',
      );
    });

    test('an entry in an older shape is a miss, not a crash', () async {
      final subject = cache();
      await subject.write(summaryCacheKey('2026-09'), _summary('2026-09'));
      fileFor(summaryCacheKey('2026-09'))
          .writeAsStringSync(jsonEncode({'payload': _summary('2026-09')}));

      expect(await subject.read(summaryCacheKey('2026-09')), isNull);
    });

    test('an unreadable index empties the cache rather than stranding it',
        () async {
      final subject = cache();
      await subject.write(summaryCacheKey('2026-09'), _summary('2026-09'));
      File('${cacheDirectory.path}/${FileOfflineCache.indexFile}')
          .writeAsStringSync('not json at all');

      expect(await subject.months(), isEmpty);
      // A cache that cannot be pruned would grow for ever, so it starts over.
      expect(await subject.read(summaryCacheKey('2026-09')), isNull);
    });
  });
}
