import 'package:flutter/foundation.dart';

/// Distinguishes "leave this field alone" from "clear this field" in
/// [TransactionFilter.copyWith]. Without it, `copyWith(category: null)` could
/// only ever mean "unchanged", and a filter could never be cleared.
const Object _unset = Object();

/// What the customer has narrowed the feed down to.
///
/// The month is deliberately *not* here: it is the page the feed is showing,
/// not a filter on it, and it belongs to the screen's own state. Filters live
/// in a sheet, so this object is also a provider-family key — which is why
/// [==] matters: two equal filters must hit the same cached request.
@immutable
class TransactionFilter {
  const TransactionFilter({
    this.category,
    this.query = '',
    this.minPaise,
    this.maxPaise,
    this.from,
    this.to,
  });

  /// The everything-included filter. `const`, so an unfiltered screen creates
  /// no garbage and always compares equal to itself.
  static const TransactionFilter none = TransactionFilter();

  /// A category id, or null for all categories.
  final String? category;

  /// Free text matched against the merchant name. Empty means no search.
  final String query;

  /// Amount bounds in paise, compared against the *magnitude* — the server
  /// matches spends and refunds alike, so 500 to 1000 finds a ₹7 refund too.
  final int? minPaise;
  final int? maxPaise;

  /// Inclusive date bounds, in local time. Serialised as UTC.
  final DateTime? from;
  final DateTime? to;

  /// Whether there is a search. Whitespace is not one.
  bool get hasQuery => query.trim().isNotEmpty;

  /// Whether either end of the amount range is set.
  bool get hasAmountRange => minPaise != null || maxPaise != null;

  /// Whether either end of the date range is set.
  bool get hasDateRange => from != null || to != null;

  /// Whether anything is actually narrowing the feed. Decides between the
  /// "no transactions" and "no results for these filters" empty states.
  bool get isActive =>
      category != null || hasQuery || hasAmountRange || hasDateRange;

  /// How many filters are applied — category, search, amount, dates — for
  /// the badge on the filter button and the chips above the list.
  ///
  /// A range counts once whichever of its ends are set: "₹500 to ₹1,000" is
  /// one filter to the customer, and one chip to remove.
  int get activeCount => [
        category != null,
        hasQuery,
        hasAmountRange,
        hasDateRange,
      ].where((applied) => applied).length;

  /// The query string for `GET /transactions`, with unset fields left out.
  ///
  /// Only the filter's own parameters: `month`, `cursor` and `limit` belong to
  /// the paging call and are added by the repository.
  Map<String, String> toQueryParameters() {
    final trimmed = query.trim();
    return {
      if (category != null) 'category': category!,
      if (trimmed.isNotEmpty) 'q': trimmed,
      if (minPaise != null) 'minPaise': '${minPaise!}',
      if (maxPaise != null) 'maxPaise': '${maxPaise!}',
      if (from != null) 'from': from!.toUtc().toIso8601String(),
      if (to != null) 'to': to!.toUtc().toIso8601String(),
    };
  }

  /// Pass a value to set it, `null` to clear it, or omit it to keep it.
  TransactionFilter copyWith({
    Object? category = _unset,
    String? query,
    Object? minPaise = _unset,
    Object? maxPaise = _unset,
    Object? from = _unset,
    Object? to = _unset,
  }) {
    return TransactionFilter(
      category:
          identical(category, _unset) ? this.category : category as String?,
      query: query ?? this.query,
      minPaise: identical(minPaise, _unset) ? this.minPaise : minPaise as int?,
      maxPaise: identical(maxPaise, _unset) ? this.maxPaise : maxPaise as int?,
      from: identical(from, _unset) ? this.from : from as DateTime?,
      to: identical(to, _unset) ? this.to : to as DateTime?,
    );
  }

  TransactionFilter cleared() => none;

  @override
  String toString() => 'TransactionFilter(active: $activeCount)';

  /// Instants are compared as instants.
  ///
  /// `DateTime.==` also requires both sides to agree on being UTC, so a filter
  /// built from a local date picker would never equal the same moment read
  /// back from a URL. Comparing epochs keeps the family key stable.
  static int? _instant(DateTime? value) => value?.microsecondsSinceEpoch;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionFilter &&
          other.category == category &&
          other.query == query &&
          other.minPaise == minPaise &&
          other.maxPaise == maxPaise &&
          _instant(other.from) == _instant(from) &&
          _instant(other.to) == _instant(to);

  @override
  int get hashCode => Object.hash(
        category,
        query,
        minPaise,
        maxPaise,
        _instant(from),
        _instant(to),
      );
}
