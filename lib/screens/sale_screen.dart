import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import 'customer_picker_screen.dart';

class SaleScreen extends StatefulWidget {
  const SaleScreen({super.key});

  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  final _apiService = ApiService();
  final _searchController = TextEditingController();

  List<Product> _products = [];
  final Map<int, int> _cart = {}; // product id -> quantity

  Customer? _selectedCustomer;

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------- Data ----------

  Future<void> _loadProducts() async {
    try {
      final products = await _apiService.getProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _errorMessage = null;
        _pruneCart();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load products. Check your connection.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Product? _find(int id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// After stock is reloaded, drop cart lines that are no longer sellable
  /// and cap quantities at what is actually in stock.
  void _pruneCart() {
    _cart.removeWhere((id, qty) {
      final product = _find(id);
      return product == null || product.stockQuantity <= 0;
    });
    _cart.updateAll((id, qty) {
      final stock = _find(id)!.stockQuantity;
      return qty > stock ? stock : qty;
    });
  }

  List<Product> get _visibleProducts {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _products;
    return _products
        .where((p) =>
            p.name.toLowerCase().contains(q) || p.sku.toLowerCase().contains(q))
        .toList();
  }

  double get _total {
    double sum = 0;
    _cart.forEach((id, qty) {
      final p = _find(id);
      if (p != null) sum += p.price * qty;
    });
    return sum;
  }

  int get _itemCount => _cart.values.fold(0, (a, b) => a + b);

  // ---------- Cart ----------

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _increase(Product product) {
    final current = _cart[product.id] ?? 0;
    if (current >= product.stockQuantity) {
      _showMessage(
        product.stockQuantity <= 0
            ? '${product.name} is out of stock'
            : 'Only ${product.stockQuantity} of ${product.name} in stock',
      );
      return;
    }
    setState(() {
      _cart[product.id] = current + 1;
    });
  }

  void _decrease(Product product) {
    final current = _cart[product.id] ?? 0;
    setState(() {
      if (current <= 1) {
        _cart.remove(product.id);
      } else {
        _cart[product.id] = current - 1;
      }
    });
  }

  // ---------- Customer ----------

  Future<void> _pickCustomer() async {
    final customer = await Navigator.of(context).push<Customer>(
      MaterialPageRoute(builder: (context) => const CustomerPickerScreen()),
    );
    if (customer == null || !mounted) return;
    setState(() {
      _selectedCustomer = customer;
    });
  }

  // ---------- Checkout ----------

  Future<void> _charge() async {
    if (_cart.isEmpty || _isSubmitting) return;

    // Only a sale with a customer attached can be partially or fully on
    // credit; a walk-in sale is always paid in full right now.
    double amountToCharge = _total;
    if (_selectedCustomer != null) {
      final entered = await _askAmountPaidNow();
      if (entered == null || !mounted) return;
      amountToCharge = entered;
    }

    // A pure credit sale (nothing paid now) has no payment method to record.
    String method = 'CASH';
    if (amountToCharge > 0.005) {
      final chosen = await _askPaymentMethod();
      if (chosen == null || !mounted) return;
      method = chosen;
    }

    final confirmed = await _confirmPayment(method, amountToCharge);
    if (!confirmed || !mounted) return;

    await _completeSale(method, amountToCharge);
  }

  Future<double?> _askAmountPaidNow() {
    final controller = TextEditingController(text: _total.toStringAsFixed(2));
    final total = _total;
    final customerName = _selectedCustomer!.name;

    return showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String? errorText;

          void submit() {
            final value = double.tryParse(controller.text.trim());
            if (value == null || value < 0) {
              setDialogState(() => errorText = 'Enter a valid amount, 0 or more');
              return;
            }
            if (value > total + 0.01) {
              setDialogState(() =>
                  errorText = 'Cannot exceed the total of KES ${total.toStringAsFixed(2)}');
              return;
            }
            Navigator.of(context).pop(value);
          }

          return AlertDialog(
            title: Text('$customerName — amount paid now'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                Text('Total: KES ${total.toStringAsFixed(2)}'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Amount paid now (KES)',
                    border: const OutlineInputBorder(),
                    errorText: errorText,
                    helperText:
                        'Leave as the total for full payment, or lower it for '
                        'a partial payment — the rest is recorded as owed.',
                    helperMaxLines: 3,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setDialogState(() => controller.text = '0'),
                    child: const Text('Fully on credit (nothing paid now)'),
                  ),
                ),
              ],
            ),
          ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: submit,
                child: const Text('Continue'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<String?> _askPaymentMethod() {
    return showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Total: KES ${_total.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'How is the customer paying?',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Cash'),
                onTap: () => Navigator.of(context).pop('CASH'),
              ),
              ListTile(
                leading: const Icon(Icons.phone_android),
                title: const Text('M-Pesa'),
                onTap: () => Navigator.of(context).pop('MPESA'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmPayment(String method, double amount) async {
    if (amount <= 0.005) {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm credit sale'),
          content: Text(
            'Record this KES ${_total.toStringAsFixed(2)} sale to '
            '${_selectedCustomer?.name} with nothing paid yet?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not yet'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes, record sale'),
            ),
          ],
        ),
      );
      return result == true;
    }

    final isMpesa = method == 'MPESA';
    final amountText = amount.toStringAsFixed(2);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isMpesa ? 'Confirm M-Pesa payment' : 'Confirm cash payment'),
        content: Text(
          isMpesa
              ? 'Have you received KES $amountText on M-Pesa? '
                  'Check the confirmation message on your phone.'
              : 'Have you received KES $amountText in cash?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not yet'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, complete sale'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _completeSale(String method, double amountPaid) async {
    final total = _total;
    final customerName = _selectedCustomer?.name;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final items = _cart.entries
          .map((e) => {'product_id': e.key, 'quantity': e.value})
          .toList();

      final error = await _apiService.completeSale(
        items: items,
        method: method,
        customerId: _selectedCustomer?.id,
        amountPaid: amountPaid,
      );

      if (!mounted) return;

      if (error == null) {
        setState(() {
          _cart.clear();
          _selectedCustomer = null;
        });

        if (amountPaid >= total - 0.01) {
          _showMessage('Sale completed');
        } else if (amountPaid <= 0.005) {
          _showMessage('Sale recorded for $customerName — nothing paid yet');
        } else {
          _showMessage(
            'Sale recorded — KES ${(total - amountPaid).toStringAsFixed(2)} still owed',
          );
        }
      } else {
        _showMessage(error);
      }

      // Stock has changed (or was found to be out of date), so refresh it.
      await _loadProducts();
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        'Could not confirm the sale. Check your connection, then check '
        'the stock before trying again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  // ---------- UI ----------

  Widget _buildCustomerBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12.0, 0, 12.0, 12.0),
      child: InkWell(
        onTap: _isSubmitting ? null : _pickCustomer,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.person_outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedCustomer == null
                      ? 'Walk-in sale — tap to add a customer for credit'
                      : _selectedCustomer!.name,
                  style: _selectedCustomer != null
                      ? const TextStyle(fontWeight: FontWeight.bold)
                      : null,
                ),
              ),
              if (_selectedCustomer != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove customer',
                  onPressed: _isSubmitting
                      ? null
                      : () => setState(() => _selectedCustomer = null),
                )
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                  _loadProducts();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final products = _visibleProducts;

    if (products.isEmpty) {
      return Center(
        child: Text(
          _products.isEmpty
              ? 'No products yet. Add some first.'
              : 'No products match your search.',
        ),
      );
    }

    return ListView.separated(
      itemCount: products.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final product = products[index];
        final inCart = _cart[product.id] ?? 0;
        final outOfStock = product.stockQuantity <= 0;

        return ListTile(
          enabled: !outOfStock,
          title: Text(product.name),
          subtitle: outOfStock
              ? const Text('Out of stock', style: TextStyle(color: Colors.red))
              : Text(
                  'KES ${product.price.toStringAsFixed(2)} · '
                  'Stock: ${product.stockQuantity}',
                ),
          trailing: inCart == 0
              ? IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: outOfStock ? null : () => _increase(product),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _decrease(product),
                    ),
                    Text(
                      '$inCart',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => _increase(product),
                    ),
                  ],
                ),
          onTap: outOfStock ? null : () => _increase(product),
        );
      },
    );
  }

  Widget _buildCheckoutBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: const [
            BoxShadow(blurRadius: 4, color: Colors.black26),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_itemCount item${_itemCount == 1 ? '' : 's'}'),
                  Text(
                    'KES ${_total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: (_cart.isEmpty || _isSubmitting) ? null : _charge,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Charge'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Sale'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear sale',
            onPressed: (_cart.isEmpty || _isSubmitting)
                ? null
                : () => setState(() => _cart.clear()),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by name or SKU',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildCustomerBar(),
          Expanded(child: _buildProductList()),
        ],
      ),
      bottomNavigationBar: _buildCheckoutBar(),
    );
  }
}