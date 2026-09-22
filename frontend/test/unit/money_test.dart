import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/utils/money.dart';

void main() {
  group('formatPaise', () {
    test('formats whole rupees with two decimals', () {
      expect(formatPaise(0), '₹0.00');
      expect(formatPaise(100), '₹1.00');
      expect(formatPaise(123456), '₹1,234.56');
    });

    test('keeps sub-rupee amounts exact', () {
      expect(formatPaise(5), '₹0.05');
      expect(formatPaise(50), '₹0.50');
      expect(formatPaise(99), '₹0.99');
    });

    test('groups in the Indian style, not thousands', () {
      expect(formatPaise(12345678), '₹1,23,456.78');
      expect(formatPaise(100000000), '₹10,00,000.00');
    });

    test('puts the minus outside the rupee sign', () {
      expect(formatPaise(-123456), '-₹1,234.56');
      expect(formatPaise(-5), '-₹0.05');
    });
  });

  group('formatSignedPaise', () {
    test('marks a credit with a plus and a debit with a minus', () {
      expect(formatSignedPaise(45000), '+₹450.00');
      expect(formatSignedPaise(-45000), '-₹450.00');
    });

    test('leaves zero unsigned', () {
      expect(formatSignedPaise(0), '₹0.00');
    });
  });

  group('parseRupeesToPaise', () {
    test('accepts plain rupees', () {
      expect(parseRupeesToPaise('4500'), 450000);
      expect(parseRupeesToPaise('0'), 0);
    });

    test('accepts one or two decimals', () {
      expect(parseRupeesToPaise('0.5'), 50);
      expect(parseRupeesToPaise('0.05'), 5);
      expect(parseRupeesToPaise('4500.50'), 450050);
    });

    test('tolerates rupee signs, separators and padding', () {
      expect(parseRupeesToPaise('₹1,234.56'), 123456);
      expect(parseRupeesToPaise(' 12 '), 1200);
      expect(parseRupeesToPaise('1,23,456'), 12345600);
    });

    test('keeps a leading minus', () {
      expect(parseRupeesToPaise('-99'), -9900);
      expect(parseRupeesToPaise('-0.01'), -1);
    });

    test('rejects more than two decimals', () {
      expect(parseRupeesToPaise('12.345'), isNull);
      expect(parseRupeesToPaise('0.001'), isNull);
    });

    test('rejects anything that is not a plain number', () {
      expect(parseRupeesToPaise(null), isNull);
      expect(parseRupeesToPaise(''), isNull);
      expect(parseRupeesToPaise('   '), isNull);
      expect(parseRupeesToPaise('abc'), isNull);
      expect(parseRupeesToPaise('12abc'), isNull);
      expect(parseRupeesToPaise('1.2.3'), isNull);
      expect(parseRupeesToPaise('1e5'), isNull);
      expect(parseRupeesToPaise('--5'), isNull);
      expect(parseRupeesToPaise('.5'), isNull);
      expect(parseRupeesToPaise('12.'), isNull);
      expect(parseRupeesToPaise('+12'), isNull);
    });

    test('rejects a number too large to hold as int paise', () {
      expect(parseRupeesToPaise('99999999999999999999'), isNull);
    });

    test('round-trips through formatPaise', () {
      for (final paise in [0, 1, 99, 100, 123456, -123456, 12345678]) {
        expect(parseRupeesToPaise(formatPaise(paise)), paise);
      }
    });
  });

  group('abbreviate', () {
    test('shows exact rupees below one thousand', () {
      expect(abbreviate(0), '₹0');
      expect(abbreviate(99999), '₹999'); // 999.99 rupees truncates to 999
      expect(abbreviate(99900), '₹999');
    });

    test('switches to K at one thousand rupees', () {
      expect(abbreviate(100000), '₹1K');
      expect(abbreviate(1230000), '₹12.3K');
      expect(abbreviate(9999900), '₹99.9K'); // never rounds up to ₹100K
    });

    test('switches to L at one lakh rupees', () {
      expect(abbreviate(10000000), '₹1L');
      expect(abbreviate(12000000), '₹1.2L');
      expect(abbreviate(999999999), '₹99.9L');
    });

    test('switches to Cr at one crore rupees', () {
      expect(abbreviate(1000000000), '₹1Cr');
      expect(abbreviate(3450000000), '₹3.4Cr');
    });

    test('keeps the sign on refunds', () {
      expect(abbreviate(-1230000), '-₹12.3K');
      expect(abbreviate(-999), '-₹9'); // 9.99 rupees truncates to 9
    });
  });
}
