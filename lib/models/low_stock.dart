class LowStockItem {
  final int productId;
  final String sku;
  final String name;
  final int stockQuantity;

  const LowStockItem({
    required this.productId,
    required this.sku,
    required this.name,
    required this.stockQuantity,
  });

  factory LowStockItem.fromJson(Map<String, dynamic> json) {
    return LowStockItem(
      productId: json['product_id'] as int,
      sku: json['sku'] as String,
      name: json['name'] as String,
      stockQuantity: json['stock_quantity'] as int,
    );
  }
}