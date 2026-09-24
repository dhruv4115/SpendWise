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

    test('previous() stops at the oldest month the app offers', () {
      final c = container();
      readAndKeepAlive(c, monthProvider);

      // Six steps back is July 2026; the seventh has nowhere to go.
      for (var step = 0; step < 6; step++) {
        c.read(monthProvider.notifier).previous();
      }
      expect(c.read(monthProvider), '2026-07');

      c.read(monthProvider.notifier).previous();
      expect(c.read(monthProvider), '2026-07');
    });

    test('set() lands a month before the window on the oldest one', () {
      final c = container();
      readAndKeepAlive(c, monthProvider);

      c.read(monthProvider.notifier).set('2019-03');

      expect(c.read(monthProvider), '2026-07');
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

  group('the window', () {
    ProviderContainer container() => makeContainer(
          overrides: [
            clockProvider.overrideWithValue(() => DateTime(2027, 1, 3, 9)),
          ],
        );

    test('is seven months, oldest first, ending on this one', () {
      expect(container().read(monthWindowProvider), [
        '2026-07',
        '2026-08',
        '2026-09',
        '2026-10',
        '2026-11',
        '2026-12',
        '2027-01',
      ]);
    });

    test('its ends are the two caps', () {
      final c = container();

      expect(c.read(earliestMonthProvider), '2026-07');
      expect(c.read(latestMonthProvider), '2027-01');
      expect(c.read(monthWindowProvider).first, c.read(earliestMonthProvider));
      expect(c.read(monthWindowProvider).last, c.read(latestMonthProvider));
    });

    test('three months stay resident, and they cross the year too', () {
      expect(container().read(residentMonthsProvider), {
        '2027-01',
        '2026-12',
        '2026-11',
      });
    });
  });
}
