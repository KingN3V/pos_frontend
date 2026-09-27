/// The backend saves times as UTC but sends them without a time zone
/// (e.g. "2026-09-22T10:15:00.123456"). Dart would read that as local time
/// and show every sale 3 hours early in Kenya, so mark it as UTC first,
/// then convert to the phone's local time.
DateTime _parseServerTime(String value) {
  final hasZone = RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value);
  return DateTime.parse(hasZone ? value : '${value}Z').toLocal();
}

class OrderItem {
  final int id;
  final int productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double subtotal;

  const OrderItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'] as int,
      productId: json['product_id'] as int,
      productName: json['product_name'] as String,
      quantity: json['quantity'] as int,
      unitPrice: (json['unit_price'] as num).toDouble(),
      subtotal: (json['subtotal'] as num).toDouble(),
    );
  }
}

class Order {
  final int id;
  final String orderNumber;
  final int? customerId;
  final String? customerName;
  final String? customerPhone;

  /// 'open', 'completed' or 'cancelled'.
  final String status;
  final double total;
  final double balanceDue;
  final DateTime createdAt;
  final DateTime? completedAt;
  final List<OrderItem> items;

  const Order({
    required this.id,
    required this.orderNumber,
    this.customerId,
    this.customerName,
    this.customerPhone,
    required this.status,
    required this.total,
    required this.balanceDue,
    required this.createdAt,
    this.completedAt,
    required this.items,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List<dynamic>? ?? []);
    final completedAt = json['completed_at'] as String?;

    return Order(
      id: json['id'] as int,
      orderNumber: json['order_number'] as String,
      customerId: json['customer_id'] as int?,
      customerName: json['customer_name'] as String?,
      customerPhone: json['customer_phone'] as String?,
      status: json['status'] as String,
      total: (json['total'] as num).toDouble(),
      balanceDue: (json['balance_due'] as num).toDouble(),
      createdAt: _parseServerTime(json['created_at'] as String),
      completedAt: completedAt == null ? null : _parseServerTime(completedAt),
      items: rawItems
          .map((item) => OrderItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  bool get isOpen => status == 'open';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  /// Total number of units on the order.
  int get unitCount => items.fold(0, (sum, item) => sum + item.quantity);

  /// How much has been paid so far.
  double get amountPaid => total - balanceDue;
}