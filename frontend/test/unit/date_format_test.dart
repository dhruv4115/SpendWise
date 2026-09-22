import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/utils/date_format.dart';

void main() {
  group('monthKey', () {
    test('pads the month to two digits', () {
      expect(monthKey(DateTime(2026, 9, 22)), '2026-09');
      expect(monthKey(DateTime(2026, 12, 1)), '2026-12');
      expect(monthKey(DateTime(2026, 1, 31)), '2026-01');
    });
  });

  group('parseMonthKey', () {
    test('returns the first of the month at local midnight', () {
      expect(parseMonthKey('2026-09'), DateTime(2026, 9, 1));
      expect(parseMonthKey('2025-12'), DateTime(2025, 12, 1));
    });

    test('rejects anything that is not YYYY-MM', () {
      for (final bad in [
        '2026-9',
        '26-09',
        '2026/09',
        '2026-09-01',
        'abc',
        ''
      ]) {
        expect(
          () => parseMonthKey(bad),
          throwsFormatException,
          reason: 'should reject "$bad"',
        );
      }
    });

    test('rejects an out-of-range month', () {
      expect(() => parseMonthKey('2026-00'), throwsFormatException);
      expect(() => parseMonthKey('2026-13'), throwsFormatException);
    });

    test('round-trips with monthKey', () {
      expect(monthKey(parseMonthKey('2026-09')), '2026-09');
    });
  });

  group('addMonths', () {
    test('moves within a year', () {
      expect(addMonths('2026-09', 1), '2026-10');
      expect(addMonths('2026-09', -1), '2026-08');
      expect(addMonths('2026-09', 0), '2026-09');
    });

    test('rolls backwards across a year boundary', () {
      expect(addMonths('2026-01', -1), '2025-12');
      expect(addMonths('2026-03', -15), '2024-12');
      expect(addMonths('2026-01', -12), '2025-01');
    });

    test('rolls forwards across a year boundary', () {
      expect(addMonths('2026-12', 1), '2027-01');
      expect(addMonths('2025-12', 13), '2027-01');
      expect(addMonths('2026-11', 25), '2028-12');
    });

    test('rejects a malformed key', () {
      expect(() => addMonths('2026-9', 1), throwsFormatException);
    });
  });

  group('monthKeyLabel', () {
    test('reads as a human month', () {
      expect(monthKeyLabel('2026-09'), 'September 2026');
      expect(monthKeyLabel('2025-01'), 'January 2025');
    });
  });

  group('dayHeaderLabel', () {
    final now = DateTime(2026, 9, 22, 14, 30);

    test('names today and yesterday', () {
      expect(dayHeaderLabel(DateTime(2026, 9, 22, 6), now: now), 'Today');
      expect(dayHeaderLabel(DateTime(2026, 9, 22, 23, 59), now: now), 'Today');
      expect(dayHeaderLabel(DateTime(2026, 9, 21, 1), now: now), 'Yesterday');
    });

    test('drops the year within the current year', () {
      expect(dayHeaderLabel(DateTime(2026, 9, 12), now: now), '12 Sep');
      expect(dayHeaderLabel(DateTime(2026, 1, 3), now: now), '3 Jan');
    });

    test('keeps the year for other years', () {
      expect(dayHeaderLabel(DateTime(2025, 9, 12), now: now), '12 Sep 2025');
      expect(dayHeaderLabel(DateTime(2027, 2, 1), now: now), '1 Feb 2027');
    });

    test('defaults to the real clock', () {
      expect(dayHeaderLabel(DateTime.now()), 'Today');
    });
  });

  group('isoUtcToLocal', () {
    test('converts to local time exactly once', () {
      final local = isoUtcToLocal('2026-09-22T18:30:00Z');

      expect(local.isUtc, isFalse);
      expect(local.toUtc(), DateTime.utc(2026, 9, 22, 18, 30));

      // The wall-clock reading is shifted by this machine's offset, whatever
      // that offset happens to be on the runner.
      final wallClock = DateTime.utc(
        local.year,
        local.month,
        local.day,
        local.hour,
        local.minute,
      );
      expect(
        wallClock,
        DateTime.utc(2026, 9, 22, 18, 30).add(local.timeZoneOffset),
      );
    });

    test('keeps milliseconds', () {
      final local = isoUtcToLocal('2026-09-22T18:30:00.250Z');
      expect(local.toUtc(), DateTime.utc(2026, 9, 22, 18, 30, 0, 250));
    });

    test('reads a missing zone designator as UTC, per the wire contract', () {
      expect(
        isoUtcToLocal('2026-09-22T18:30:00'),
        isoUtcToLocal('2026-09-22T18:30:00Z'),
      );
    });

    test('rejects a string that is not a timestamp', () {
      expect(() => isoUtcToLocal('yesterday'), throwsFormatException);
    });
  });
}
