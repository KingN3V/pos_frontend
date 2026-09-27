class Product {
  final int id;
  final String sku;
  final String name;
  final String? description;
  final int? categoryId;
  final double price;
  final double? costPrice;
  final int stockQuantity;
  final bool isActive;

  const Product({
    required this.id,
    required this.sku,
    required this.name,
    this.description,
    this.categoryId,
    required this.price,
    this.costPrice,
    required this.stockQuantity,
    required this.isActive,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      sku: json['sku'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      categoryId: json['category_id'] as int?,
      price: (json['price'] as num).toDouble(),
      costPrice: (json['cost_price'] as num?)?.toDouble(),
      stockQuantity: json['stock_quantity'] as int,
      isActive: json['is_active'] as bool,
    );
  }
}