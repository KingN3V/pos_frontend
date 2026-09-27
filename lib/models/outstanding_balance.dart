class OutstandingBalance {
  final int customerId;
  final String customerName;
  final String? phoneNumber;
  final double totalBalanceDue;
  final int openOrderCount;

  const OutstandingBalance({
    required this.customerId,
    required this.customerName,
    this.phoneNumber,
    required this.totalBalanceDue,
    required this.openOrderCount,
  });

  factory OutstandingBalance.fromJson(Map<String, dynamic> json) {
    return OutstandingBalance(
      customerId: json['customer_id'] as int,
      customerName: json['customer_name'] as String,
      phoneNumber: json['phone_number'] as String?,
      totalBalanceDue: (json['total_balance_due'] as num).toDouble(),
      openOrderCount: json['open_order_count'] as int,
    );
  }
}