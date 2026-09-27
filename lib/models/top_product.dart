class TopProduct {
  final int productId;
  final String name;
  final int quantitySold;
  final double revenue;
  final double profit;
  final int unitsMissingCost;

  const TopProduct({
    required this.productId,
    required this.name,
    required this.quantitySold,
    required this.revenue,
    required this.profit,
    required this.unitsMissingCost,
  });

  factory TopProduct.fromJson(Map<String, dynamic> json) {
    return TopProduct(
      productId: json['product_id'] as int,
      name: json['name'] as String,
      quantitySold: json['quantity_sold'] as int,
      revenue: (json['revenue'] as num).toDouble(),
      profit: (json['profit'] as num).toDouble(),
      unitsMissingCost: json['units_missing_cost'] as int,
    );
  }
}