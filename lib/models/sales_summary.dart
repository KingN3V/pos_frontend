/// The backend saves times as UTC but sends them without a time zone
/// (e.g. "2026-09-22T10:15:00.123456"). Dart would read that as local time
/// and show times 3 hours early in Kenya, so mark it as UTC first, then
/// convert to the phone's local time.
DateTime _parseServerTime(String value) {
  final hasZone = RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value);
  return DateTime.parse(hasZone ? value : '${value}Z').toLocal();
}

class SalesSummary {
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final int orderCount;
  final double totalRevenue;
  final double totalProfit;
  final int unitsMissingCost;
  final Map<String, double> revenueByMethod;

  const SalesSummary({
    required this.rangeStart,
    required this.rangeEnd,
    required this.orderCount,
    required this.totalRevenue,
    required this.totalProfit,
    required this.unitsMissingCost,
    required this.revenueByMethod,
  });

  factory SalesSummary.fromJson(Map<String, dynamic> json) {
    final rawByMethod = json['revenue_by_method'] as Map<String, dynamic>? ?? {};

    return SalesSummary(
      rangeStart: _parseServerTime(json['range_start'] as String),
      rangeEnd: _parseServerTime(json['range_end'] as String),
      orderCount: json['order_count'] as int,
      totalRevenue: (json['total_revenue'] as num).toDouble(),
      totalProfit: (json['total_profit'] as num).toDouble(),
      unitsMissingCost: json['units_missing_cost'] as int,
      revenueByMethod: rawByMethod.map(
        (method, amount) => MapEntry(method, (amount as num).toDouble()),
      ),
    );
  }
}