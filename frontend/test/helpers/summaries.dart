/// A `GET /summary` body as the server sends it: `byCategory` in whatever
/// order it was built, and `byDay` listing only the days something happened
/// on. `totalPaise` is the sum of [byCategory], as it is on the server.
Map<String, Object?> summaryWire({
  String month = '2026-09',
  Map<String, int> byCategory = const {},
  int prevTotalPaise = 0,
  Map<String, int> byDay = const {},
}) {
  var total = 0;
  for (final paise in byCategory.values) {
    total += paise;
  }
  return {
    'month': month,
    'totalPaise': total,
    'prevTotalPaise': prevTotalPaise,
    'byCategory': byCategory,
    'byDay': [
      for (final MapEntry(key: date, value: paise) in byDay.entries)
        {'date': date, 'paise': paise},
    ],
  };
}

/// September 2026 across eight categories plus the server's own "other":
/// ₹10,900.00 spent, against ₹10,000.00 in August.
Map<String, Object?> septemberWire() => summaryWire(
      byCategory: const {
        'travel': 15000,
        'food': 450000,
        'other': 5000,
        'groceries': 300000,
        'health': 20000,
        'transport': 120000,
        'entertainment': 30000,
        'shopping': 90000,
        'bills': 60000,
      },
      prevTotalPaise: 1000000,
      byDay: const {
        '2026-09-02': 250000,
        '2026-09-09': 400000,
        '2026-09-15': 190000,
        '2026-09-21': 250000,
      },
    );
