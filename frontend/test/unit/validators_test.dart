import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/utils/validators.dart';

void main() {
  group('emailValidator', () {
    test('accepts an ordinary address', () {
      expect(emailValidator('asha@example.com'), isNull);
      expect(emailValidator('asha.rao+bank@example.co.in'), isNull);
    });

    test('trims before judging', () {
      expect(emailValidator('  asha@example.com  '), isNull);
    });

    test('asks for an address when the field is empty', () {
      expect(emailValidator(null), 'Enter your email address.');
      expect(emailValidator(''), 'Enter your email address.');
      expect(emailValidator('   '), 'Enter your email address.');
    });

    test('rejects an address that cannot be one', () {
      for (final bad in [
        'asha',
        'asha@',
        '@example.com',
        'asha@example',
        'a b@c.com'
      ]) {
        expect(
          emailValidator(bad),
          'That does not look like an email address.',
          reason: 'should reject "$bad"',
        );
      }
    });
  });

  group('passwordValidator', () {
    test('accepts at least the minimum length', () {
      expect(passwordValidator('password123'), isNull);
      expect(passwordValidator('12345678'), isNull);
    });

    test('asks for a password when the field is empty', () {
      expect(passwordValidator(null), 'Enter your password.');
      expect(passwordValidator(''), 'Enter your password.');
    });

    test('rejects anything shorter than the minimum', () {
      expect(passwordValidator('1234567'), 'Use at least 8 characters.');
      expect(passwordValidator(' '), 'Use at least 8 characters.');
    });
  });

  group('budgetAmountValidator', () {
    test('accepts amounts a person would type', () {
      expect(budgetAmountValidator('4500'), isNull);
      expect(budgetAmountValidator('4,500'), isNull);
      expect(budgetAmountValidator('4500.50'), isNull);
      expect(budgetAmountValidator('₹12,000'), isNull);
    });

    test('accepts zero — a planned spend of nothing is a valid budget', () {
      expect(budgetAmountValidator('0'), isNull);
    });

    test('asks for an amount when the field is empty', () {
      expect(budgetAmountValidator(null), 'Enter an amount.');
      expect(budgetAmountValidator(''), 'Enter an amount.');
      expect(budgetAmountValidator('  '), 'Enter an amount.');
    });

    test('rejects input that is not an amount', () {
      const message =
          'Enter an amount in rupees, for example 4,500 or 4500.50.';
      expect(budgetAmountValidator('abc'), message);
      expect(budgetAmountValidator('12.345'), message);
      expect(budgetAmountValidator('1.2.3'), message);
    });

    test('rejects a negative budget', () {
      expect(budgetAmountValidator('-1'), 'A budget cannot be negative.');
      expect(budgetAmountValidator('-0.01'), 'A budget cannot be negative.');
    });

    test('rejects an implausibly large budget', () {
      expect(budgetAmountValidator('10000000'), isNull); // exactly one crore
      expect(
        budgetAmountValidator('10000000.01'),
        'That is higher than the ₹1,00,00,000.00 maximum.',
      );
    });
  });
}
