import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/category.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/customer.dart';
import '../models/outstanding_balance.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/sales_summary.dart';
import '../models/top_product.dart';
import '../models/low_stock.dart';

class ApiService {
 
  static const String baseUrl = 'https://pointofsale-api.onrender.com';

  final _storage = const FlutterSecureStorage();

  // ---------- Auth ----------

  /// Logs in against /auth/token and stores the JWT on success.
  /// Returns true on success, false on invalid credentials.
  /// Throws an exception for network/server errors.
  Future<bool> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'username': username,
        'password': password,
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _storage.write(key: 'access_token', value: data['access_token']);
      await _storage.write(key: 'username', value: data['username']);
      await _storage.write(key: 'role', value: data['role']);
      return true;
    } else if (response.statusCode == 401) {
      return false;
    } else {
      throw Exception('Login failed: ${response.statusCode} ${response.body}');
    }
  }

  Future<String?> getToken() async {
    return _storage.read(key: 'access_token');
  }

  Future<void> logout() async {
    await _storage.deleteAll();
  }

   /// Calls /auth/register. Returns null on success, or an error message
  /// to show the user. Throws an exception for network/server errors.
  Future<String?> register({
    required String email,
    required String username,
    required String firstName,
    required String lastName,
    required String password,
    String? phoneNumber,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'username': username,
        'first_name': firstName,
        'last_name': lastName,
        'password': password,
        'role': 'admin',
        if (phoneNumber != null && phoneNumber.isNotEmpty)
          'phone_number': phoneNumber,
      }),
    );

    if (response.statusCode == 201) {
      return null;
    } else if (response.statusCode == 400) {
      final data = jsonDecode(response.body);
      return data['detail'] as String;
    } else if (response.statusCode == 422) {
      return 'Please check your details (is the email valid?)';
    } else {
      throw Exception('Registration failed: ${response.statusCode} ${response.body}');
    }
  }

  /// Calls /auth/forgot-password. Always returns null on a 200 (the backend
  /// gives the same generic response whether or not the email exists, so a
  /// null return here just means "the request went through", not that the
  /// email is definitely registered). Returns an error message only if the
  /// backend actually failed to send (e.g. SMTP misconfigured). Throws for
  /// network/server errors.
  Future<String?> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    if (response.statusCode == 200) {
      return null;
    } else if (response.statusCode == 400 || response.statusCode == 500) {
      final data = jsonDecode(response.body);
      return data['detail'] as String;
    } else {
      throw Exception(
          'Failed to request password reset: ${response.statusCode} ${response.body}');
    }
  }

  /// Calls /auth/reset-password. Returns null on success, or an error
  /// message to show the user (e.g. invalid/expired code). Throws for
  /// network/server errors.
  Future<String?> resetPassword({
    required String resetCode,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'reset_token': resetCode,
        'new_password': newPassword,
      }),
    );

    if (response.statusCode == 200) {
      return null;
    } else if (response.statusCode == 400) {
      final data = jsonDecode(response.body);
      return data['detail'] as String;
    } else {
      throw Exception('Failed to reset password: ${response.statusCode} ${response.body}');
    }
  }

    // ---------- Authenticated requests ----------

  /// Headers for any endpoint that requires a logged-in user.
  Future<Map<String, String>> _authHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ---------- Categories ----------

  Future<List<Category>> getCategories() async {
    final response = await http.get(
      Uri.parse('$baseUrl/products/categories'),
      headers: await _authHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Category.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load categories: ${response.statusCode} ${response.body}');
    }
  }

  /// Returns null on success, or an error message to show the user
  /// (e.g. duplicate name). Throws for network/server errors.
  Future<String?> createCategory(String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/products/categories'),
      headers: await _authHeaders(),
      body: jsonEncode({'name': name}),
    );

    if (response.statusCode == 201) {
      return null;
    } else if (response.statusCode == 400) {
      final data = jsonDecode(response.body);
      return data['detail'] as String;
    } else {
      throw Exception('Failed to create category: ${response.statusCode} ${response.body}');
    }
  }
    // ---------- Products ----------

    /// [onlyHidden] loads only hidden products instead of the normal
    /// (active) list; there is no way to load both together from here,
    /// since nothing in the app needs that combined view.
    Future<List<Product>> getProducts({
    int? categoryId,
    bool onlyHidden = false,
  }) async {
    final uri = Uri.parse('$baseUrl/products/').replace(
      queryParameters: {
        'category_id': ?categoryId?.toString(),
        if (onlyHidden) 'visibility': 'hidden',
      },
    );

    final response = await http.get(
      uri,
      headers: await _authHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Product.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load products: ${response.statusCode} ${response.body}');
    }
  }

    /// Returns null on success, or an error message to show the user
  /// (e.g. duplicate SKU). Throws for network/server errors.
  Future<String?> createProduct({
    required String sku,
    required String name,
    String? description,
    int? categoryId,
    required double price,
    double? costPrice,
    int stockQuantity = 0,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/products/'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'sku': sku,
        'name': name,
        if (description != null && description.isNotEmpty)
          'description': description,
        'category_id': categoryId,
        'price': price,
        'cost_price': costPrice,
        'stock_quantity': stockQuantity,
      }),
    );

    if (response.statusCode == 201) {
      return null;
    } else if (response.statusCode == 400) {
      final data = jsonDecode(response.body);
      return data['detail'] as String;
    } else if (response.statusCode == 422) {
      return 'Please check the product details';
    } else {
      throw Exception('Failed to create product: ${response.statusCode} ${response.body}');
    }
  }
    // ---------- Sales ----------

    /// Rings up a sale: creates the order, then records a payment for
  /// [amountPaid] if it's more than 0 (a pure credit sale skips the
  /// payment call entirely and leaves the order open with the full
  /// balance due). Pass [customerId] to attach a customer for credit;
  /// leave it null for a walk-in sale (always paid in full by the caller).
  /// `items` is a list of {'product_id': ..., 'quantity': ...}.
  /// Returns null on success, or an error message to show the user.
  /// Throws for network/server errors.
  Future<String?> completeSale({
    required List<Map<String, int>> items,
    required String method,
    int? customerId,
    required double amountPaid,
  }) async {
    final orderResponse = await http.post(
      Uri.parse('$baseUrl/orders/'),
      headers: await _authHeaders(),
      body: jsonEncode({'customer_id': customerId, 'items': items}),
    );

    if (orderResponse.statusCode == 400) {
      final data = jsonDecode(orderResponse.body);
      return data['detail'] as String;
    } else if (orderResponse.statusCode != 201) {
      throw Exception(
          'Failed to create order: ${orderResponse.statusCode} ${orderResponse.body}');
    }

    final order = jsonDecode(orderResponse.body);
    final int orderId = order['id'] as int;

    // Nothing paid now (a pure credit sale): leave the order open with the
    // full balance due, and don't call the payments endpoint at all.
    if (amountPaid <= 0.005) {
      return null;
    }

    final paymentResponse = await http.post(
      Uri.parse('$baseUrl/orders/$orderId/payments'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'order_id': orderId,
        'method': method,
        'amount': amountPaid,
      }),
    );

    if (paymentResponse.statusCode == 201) {
      return null;
    }

    // The payment was refused. Only cancel the order if it was meant to be
    // paid in full right now (no customer, i.e. a walk-in sale) — a
    // customer's partial-payment order should stay open even if this one
    // payment attempt failed, since she may retry the payment rather than
    // the whole sale.
    if (customerId == null) {
      await http.post(
        Uri.parse('$baseUrl/orders/$orderId/cancel'),
        headers: await _authHeaders(),
      );
    }

    if (paymentResponse.statusCode == 400) {
      final data = jsonDecode(paymentResponse.body);
      return data['detail'] as String;
    }
    throw Exception(
        'Failed to record payment: ${paymentResponse.statusCode} ${paymentResponse.body}');
  }

  // ---------- Restock ----------

  /// Adds newly received stock to a product (a "restock" stock movement).
  /// If [newCostPrice] (buying price) and/or [newPrice] (selling price) are
  /// given, they are saved first in a single request (safe to repeat), then
  /// the stock is added, so a retry after a failure can never add the stock
  /// twice because of the price step.
  /// Returns null on success, or an error message to show the user.
  /// Throws for network/server errors.
  Future<String?> restockProduct({
    required int productId,
    required int quantity,
    double? newCostPrice,
    double? newPrice,
    String? note,
  }) async {
    final priceChanges = <String, dynamic>{
      'cost_price': ?newCostPrice,
      'price': ?newPrice,
    };

    if (priceChanges.isNotEmpty) {
      final priceResponse = await http.patch(
        Uri.parse('$baseUrl/products/$productId'),
        headers: await _authHeaders(),
        body: jsonEncode(priceChanges),
      );

      if (priceResponse.statusCode == 400) {
        final data = jsonDecode(priceResponse.body);
        return data['detail'] as String;
      } else if (priceResponse.statusCode != 200) {
        throw Exception(
            'Failed to update prices: ${priceResponse.statusCode} ${priceResponse.body}');
      }
    }

    final response = await http.post(
      Uri.parse('$baseUrl/products/$productId/stock-movement'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'product_id': productId,
        'quantity_change': quantity,
        'movement_type': 'restock',
        if (note != null && note.isNotEmpty) 'note': note,
      }),
    );

    if (response.statusCode == 201) {
      return null;
    } else if (response.statusCode == 400) {
      final data = jsonDecode(response.body);
      return data['detail'] as String;
    } else {
      throw Exception('Failed to add stock: ${response.statusCode} ${response.body}');
    }
  }

  // ---------- Orders (sales history) ----------

  /// Loads orders, newest first. Pass [status] ('open', 'completed' or
  /// 'cancelled') to load only those, and/or [customerId] to load only one
  /// customer's orders. Pass [query] to search by customer name or phone
  /// (walk-in orders never match, since they have no customer). Pass
  /// either [period] ('today'/'week'/'month') or the [startDate]/[endDate]
  /// pair to filter by when the order was created; leave all three null to
  /// load orders from any time. [limit] and [offset] load a page at a time
  /// so the list stays fast as the shop's history grows.
  /// Throws for network/server errors.
  Future<List<Order>> getOrders({
    String? status,
    int? customerId,
    String? query,
    String? period,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/orders/').replace(
      queryParameters: {
        'status_filter': ?status,
        'customer_id': ?customerId?.toString(),
        'q': ?query,
        'period': ?period,
        'start_date': ?startDate != null ? _dateOnly(startDate) : null,
        'end_date': ?endDate != null ? _dateOnly(endDate) : null,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );

    final response = await http.get(
      uri,
      headers: await _authHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Order.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load orders: ${response.statusCode} ${response.body}');
    }
  }

  /// Downloads the sales history matching the given filters as CSV or
  /// Excel and opens the OS share sheet so it can be saved or sent on.
  /// Ignores pagination — exports everything matching the filters, not
  /// just whatever page is loaded on screen. Throws for network/server
  /// errors.
  Future<void> downloadOrders({
    required String format,
    String? status,
    int? customerId,
    String? query,
    String? period,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final uri = Uri.parse('$baseUrl/orders/').replace(
      queryParameters: {
        'status_filter': ?status,
        'customer_id': ?customerId?.toString(),
        'q': ?query,
        'period': ?period,
        'start_date': ?startDate != null ? _dateOnly(startDate) : null,
        'end_date': ?endDate != null ? _dateOnly(endDate) : null,
        'format': format,
      },
    );

    await _downloadAndShare(
      uri: uri,
      filenameBase: 'sales_history',
      format: format,
      shareText: 'sales_history report',
    );
  }

  /// Cancels an open order; its stock goes back on the shelf.
  /// Returns null on success, or an error message to show the user
  /// (e.g. the order is no longer open). Throws for network/server errors.
  Future<String?> cancelOrder(int orderId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/orders/$orderId/cancel'),
      headers: await _authHeaders(),
    );

    if (response.statusCode == 200) {
      return null;
    } else if (response.statusCode == 400) {
      final data = jsonDecode(response.body);
      return data['detail'] as String;
    } else {
      throw Exception('Failed to cancel order: ${response.statusCode} ${response.body}');
    }
  }

  // ---------- Product edit ----------

  /// Updates any of a product's editable fields. Only the parameters you
  /// pass are changed; everything else is left as it is.
  /// Returns null on success, or an error message to show the user
  /// (e.g. duplicate SKU, or a category that isn't hers). Throws for
  /// network/server errors.
  Future<String?> updateProduct({
    required int productId,
    String? sku,
    String? name,
    String? description,
    int? categoryId,
    double? price,
    double? costPrice,
  }) async {
    final body = <String, dynamic>{
      'sku': ?sku,
      'name': ?name,
      'description': ?description,
      'category_id': ?categoryId,
      'price': ?price,
      'cost_price': ?costPrice,
    };

    final response = await http.patch(
      Uri.parse('$baseUrl/products/$productId'),
      headers: await _authHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return null;
    } else if (response.statusCode == 400) {
      final data = jsonDecode(response.body);
      return data['detail'] as String;
    } else if (response.statusCode == 422) {
      return 'Please check the product details';
    } else {
      throw Exception('Failed to update product: ${response.statusCode} ${response.body}');
    }
  }

  /// Hides a product from the sale, restock and product lists without
  /// deleting it, so past sales keep showing its name. Throws for
  /// network/server errors.
  Future<void> hideProduct(int productId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/products/$productId'),
      headers: await _authHeaders(),
    );

    if (response.statusCode != 204) {
      throw Exception('Failed to hide product: ${response.statusCode} ${response.body}');
    }
  }

  /// Brings a hidden product back. Throws for network/server errors.
  Future<void> reactivateProduct(int productId) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/products/$productId'),
      headers: await _authHeaders(),
      body: jsonEncode({'is_active': true}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to reactivate product: ${response.statusCode} ${response.body}');
    }
  }

  /// Takes stock out for a reason other than a sale: 'expired', 'damaged'
  /// or 'correction' (she typed the wrong number when adding it). [quantity]
  /// is how many are being removed (a positive number).
  /// Returns null on success, or an error message to show the user (e.g.
  /// more than is in stock). Throws for network/server errors.
  Future<String?> removeStock({
    required int productId,
    required int quantity,
    required String reason,
    String? note,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/products/$productId/stock-movement'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'product_id': productId,
        'quantity_change': -quantity,
        'movement_type': reason,
        if (note != null && note.isNotEmpty) 'note': note,
      }),
    );

    if (response.statusCode == 201) {
      return null;
    } else if (response.statusCode == 400) {
      final data = jsonDecode(response.body);
      return data['detail'] as String;
    } else {
      throw Exception('Failed to remove stock: ${response.statusCode} ${response.body}');
    }
  }

    // ---------- Customers ----------

    Future<List<Customer>> getCustomers({String? query}) async {
    final uri = Uri.parse('$baseUrl/customers/').replace(
      queryParameters: {
        'q': ?query,
      },
    );

    final response = await http.get(
      uri,
      headers: await _authHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Customer.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load customers: ${response.statusCode} ${response.body}');
    }
  }

  /// Returns null on success, or an error message to show the user
  /// (e.g. duplicate phone number). Throws for network/server errors.
  Future<String?> createCustomer({
    required String name,
    String? phoneNumber,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/customers/'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'name': name,
        if (phoneNumber != null && phoneNumber.isNotEmpty)
          'phone_number': phoneNumber,
      }),
    );

    if (response.statusCode == 201) {
      return null;
    } else if (response.statusCode == 400) {
      final data = jsonDecode(response.body);
      return data['detail'] as String;
    } else if (response.statusCode == 422) {
      return 'Please check the customer details';
    } else {
      throw Exception('Failed to create customer: ${response.statusCode} ${response.body}');
    }
  }


    // ---------- Outstanding balances ----------

    Future<List<OutstandingBalance>> getOutstandingBalances({String? query}) async {
    final uri = Uri.parse('$baseUrl/reports/outstanding-balances').replace(
      queryParameters: {
        'q': ?query,
      },
    );

    final response = await http.get(
      uri,
      headers: await _authHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => OutstandingBalance.fromJson(json)).toList();
    } else {
      throw Exception(
          'Failed to load outstanding balances: ${response.statusCode} ${response.body}');
    }
  }

  /// Records a payment against an existing open order (paying off some or
  /// all of its balance). Returns null on success, or an error message to
  /// show the user (e.g. amount exceeds the remaining balance). Throws for
  /// network/server errors.
  Future<String?> recordPayment({
    required int orderId,
    required String method,
    required double amount,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/orders/$orderId/payments'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'order_id': orderId,
        'method': method,
        'amount': amount,
      }),
    );

    if (response.statusCode == 201) {
      return null;
    } else if (response.statusCode == 400) {
      final data = jsonDecode(response.body);
      return data['detail'] as String;
    } else {
      throw Exception('Failed to record payment: ${response.statusCode} ${response.body}');
    }
  }
    // ---------- Reports ----------

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Builds the period/start_date/end_date query params shared by every
  /// report endpoint. Pass exactly one of [period] or the
  /// [startDate]/[endDate] pair, matching the backend's rule.
  Map<String, String?> _timeframeParams({
    String? period,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return {
      'period': period,
      'start_date': startDate != null ? _dateOnly(startDate) : null,
      'end_date': endDate != null ? _dateOnly(endDate) : null,
    };
  }

  Future<SalesSummary> getSalesSummary({
    String? period,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final uri = Uri.parse('$baseUrl/reports/sales-summary').replace(
      queryParameters: _timeframeParams(
        period: period,
        startDate: startDate,
        endDate: endDate,
      )..removeWhere((key, value) => value == null),
    );

    final response = await http.get(uri, headers: await _authHeaders());

    if (response.statusCode == 200) {
      return SalesSummary.fromJson(jsonDecode(response.body));
    } else {
      throw Exception(
          'Failed to load sales summary: ${response.statusCode} ${response.body}');
    }
  }

  Future<List<TopProduct>> getTopProducts({
    String? period,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 10,
  }) async {
    final params = _timeframeParams(
      period: period,
      startDate: startDate,
      endDate: endDate,
    )..removeWhere((key, value) => value == null);
    params['limit'] = limit.toString();

    final uri = Uri.parse('$baseUrl/reports/top-products')
        .replace(queryParameters: params);

    final response = await http.get(uri, headers: await _authHeaders());

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => TopProduct.fromJson(json)).toList();
    } else {
      throw Exception(
          'Failed to load top products: ${response.statusCode} ${response.body}');
    }
  }

  Future<List<LowStockItem>> getLowStock({int threshold = 5}) async {
    final uri = Uri.parse('$baseUrl/reports/low-stock').replace(
      queryParameters: {'threshold': threshold.toString()},
    );

    final response = await http.get(uri, headers: await _authHeaders());

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => LowStockItem.fromJson(json)).toList();
    } else {
      throw Exception(
          'Failed to load low stock: ${response.statusCode} ${response.body}');
    }
  }

  /// Downloads a report as CSV or Excel and opens the OS share sheet so it
  /// can be saved or sent on. [reportPath] is the report's path segment
  /// under /reports/ (e.g. 'sales-summary', 'top-products', 'low-stock',
  /// 'outstanding-balances'). [extraParams] carries anything beyond the
  /// timeframe (e.g. top-products' limit, low-stock's threshold).
  /// Throws for network/server errors.
  Future<void> downloadReport({
    required String reportPath,
    required String format,
    String? period,
    DateTime? startDate,
    DateTime? endDate,
    Map<String, String>? extraParams,
  }) async {
    final params = _timeframeParams(
      period: period,
      startDate: startDate,
      endDate: endDate,
    )..removeWhere((key, value) => value == null);
    params['format'] = format;
    if (extraParams != null) params.addAll(extraParams);

    final uri = Uri.parse('$baseUrl/reports/$reportPath')
        .replace(queryParameters: params);

    await _downloadAndShare(
      uri: uri,
      filenameBase: reportPath,
      format: format,
      shareText: '$reportPath report',
    );
  }

  /// Shared by downloadReport and downloadOrders: hits [uri], saves the
  /// response bytes to a temp file named [filenameBase].(xlsx|csv), and
  /// opens the OS share sheet. Throws for network/server errors.
  Future<void> _downloadAndShare({
    required Uri uri,
    required String filenameBase,
    required String format,
    required String shareText,
  }) async {
    final response = await http.get(uri, headers: await _authHeaders());

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to download report: ${response.statusCode} ${response.body}');
    }

    final extension = format == 'excel' ? 'xlsx' : 'csv';
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filenameBase.$extension');
    await file.writeAsBytes(response.bodyBytes);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: shareText),
    );
  }
}