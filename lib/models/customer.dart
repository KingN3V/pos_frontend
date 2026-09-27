class Customer {
  final int id;
  final String name;
  final String? phoneNumber;

  const Customer({
    required this.id,
    required this.name,
    this.phoneNumber,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as int,
      name: json['name'] as String,
      phoneNumber: json['phone_number'] as String?,
    );
  }
}