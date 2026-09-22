import 'package:flutter/foundation.dart';

import '../../../core/utils/json_read.dart';

/// How loudly an insight should be shown.
///
/// Severity chooses an icon and a word as well as a colour — never a colour on
/// its own.
enum InsightSeverity {
  info('info'),
  warning('warning'),
  critical('critical');

  const InsightSeverity(this.wireName);

  final String wireName;

  /// Unknown values degrade to [info] rather than throwing: a server that
  /// starts sending a new severity should make the card quieter, not break
  /// the Overview screen.
  static InsightSeverity fromWire(String value) {
    for (final severity in InsightSeverity.values) {
      if (severity.wireName == value) return severity;
    }
    return InsightSeverity.info;
  }
}

/// A single sentence of advice on the Overview screen.
@immutable
class InsightCard {
  const InsightCard({
    required this.id,
    required this.title,
    required this.body,
    required this.severity,
    required this.dismissible,
  });

  factory InsightCard.fromJson(Map<String, dynamic> json) {
    return InsightCard(
      id: readString(json, 'id'),
      title: readString(json, 'title'),
      body: readString(json, 'body'),
      severity: InsightSeverity.fromWire(readString(json, 'severity')),
      dismissible: readBoolOr(json, 'dismissible', true),
    );
  }

  /// Stable per month and kind, e.g. `trend_2026-09`, so dismissing one card
  /// does not dismiss next month's.
  final String id;

  final String title;
  final String body;
  final InsightSeverity severity;

  /// False for a card the customer should not be able to wave away, such as a
  /// breached budget.
  final bool dismissible;

  InsightCard copyWith({
    String? id,
    String? title,
    String? body,
    InsightSeverity? severity,
    bool? dismissible,
  }) {
    return InsightCard(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      severity: severity ?? this.severity,
      dismissible: dismissible ?? this.dismissible,
    );
  }

  @override
  String toString() => 'InsightCard($id, ${severity.wireName})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InsightCard &&
          other.id == id &&
          other.title == title &&
          other.body == body &&
          other.severity == severity &&
          other.dismissible == dismissible;

  @override
  int get hashCode => Object.hash(id, title, body, severity, dismissible);
}
