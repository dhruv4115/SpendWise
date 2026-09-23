import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/transactions/state/month_provider.dart';

import '../helpers/container.dart';

void main() {
  group('monthProvider', () {
    // Early January, so stepping back crosses a year boundary.
    ProviderContainer container() => makeContainer(
          overrides: [
            clockProvider.overrideWithValue(() => DateTime(2027, 1, 3, 9)),
          ],
        );

    test('starts on the current month', () {
      expect(container().read(monthProvider), '2027-01');
    });

    test('previous() rolls back across the year', () {
      final c = container();
      readAndKeepAlive(c, monthProvider);

      c.read(monthProvider.notifier).previous();
      expect(c.read(monthProvider), '2026-12');
      c.read(monthProvider.notifier).previous();
      expect(c.read(monthProvider), '2026-11');
    });

    test('next() moves forward but never past the current month', () {
      final c = container();
      readAndKeepAlive(c, monthProvider);
      c.read(monthProvider.notifier).set('2026-11');

      c.read(monthProvider.notifier).next();
      expect(c.read(monthProvider), '2026-12');
      c.read(monthProvider.notifier).next();
      expect(c.read(monthProvider), '2027-01');
      c.read(monthProvider.notifier).next();
      expect(c.read(monthProvider), '2027-01');
    });

    test('set() lands a future month on the current one', () {
      final c = container();
      readAndKeepAlive(c, monthProvider);

      c.read(monthProvider.notifier).set('2030-06');

      expect(c.read(monthProvider), '2027-01');
    });

    test('set() rejects anything that is not YYYY-MM', () {
      final c = container();
      readAndKeepAlive(c, monthProvider);

      expect(() => c.read(monthProvider.notifier).set('2026-13'),
          throwsFormatException);
      expect(() => c.read(monthProvider.notifier).set('2026-9'),
          throwsFormatException);
      expect(c.read(monthProvider), '2027-01');
    });
  });
}
