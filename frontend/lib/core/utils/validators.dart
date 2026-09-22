/// Form validators. Each takes the raw field value and returns null when it is
/// acceptable, or a plain-language message to show under the field.
library;

import 'money.dart';

/// Deliberately permissive: the server is the authority on whether an account
/// exists. This only catches obvious typos before a pointless round trip.
final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

const int minPasswordLength = 8;

/// One crore. Larger than any believable monthly budget, small enough that a
/// mistyped amount is caught before it reaches the server.
const int maxBudgetPaise = 1000000000;

String? emailValidator(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Enter your email address.';
  if (!_emailPattern.hasMatch(email)) {
    return 'That does not look like an email address.';
  }
  return null;
}

String? passwordValidator(String? value) {
  final password = value ?? '';
  if (password.isEmpty) return 'Enter your password.';
  if (password.length < minPasswordLength) {
    return 'Use at least $minPasswordLength characters.';
  }
  return null;
}

/// Validates a budget limit typed in rupees.
String? budgetAmountValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Enter an amount.';

  final paise = parseRupeesToPaise(text);
  if (paise == null) {
    return 'Enter an amount in rupees, for example 4,500 or 4500.50.';
  }
  if (paise < 0) return 'A budget cannot be negative.';
  if (paise > maxBudgetPaise) {
    return 'That is higher than the ${formatPaise(maxBudgetPaise)} maximum.';
  }
  return null;
}
