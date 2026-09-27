import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/product.dart';
import '../services/api_service.dart';

/// Add newly received stock to a product. Search for the product, tap it,
/// enter how many arrived (and optionally a new buying price).
class RestockScreen extends StatefulWidget {
  const RestockScreen({super.key});

  @override
  State<RestockScreen> createState() => _RestockScreenState();
}

class _RestockScreenState extends State<RestockScreen> {
  // Matches the default threshold of the backend's /reports/low-stock.
  static const int _lowStockThreshold = 5;

  final _apiService = ApiService();
  final _searchController = TextEditingController();

  List<Product> _products = [];
  bool _isLoading = true;
  bool _isSaving = false;
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
      // Keep the list in a steady order so rows don't jump around after a
      // restock.
      products.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _products = products;
        _errorMessage = null;
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

  List<Product> get _visibleProducts {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _products;
    return _products
        .where((p) =>
            p.name.toLowerCase().contains(q) || p.sku.toLowerCase().contains(q))
        .toList();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- Restock ----------

  Future<void> _openRestock(Product product) async {
    if (_isSaving) return;

    final input = await showDialog<_RestockInput>(
      context: context,
      builder: (context) => _RestockDialog(product: product),
    );

    if (input == null || !mounted) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final error = await _apiService.restockProduct(
        productId: product.id,
        quantity: input.quantity,
        newCostPrice: input.newCostPrice,
        newPrice: input.newPrice,
      );

      if (!mounted) return;

      if (error == null) {
        final pricesChanged =
            input.newCostPrice != null || input.newPrice != null;
        _showMessage(
          'Added ${input.quantity} to ${product.name}'
          '${pricesChanged ? ' and updated the prices' : ''}',
        );
      } else {
        _showMessage(error);
      }

      // Reload so the list always shows the real stock.
      await _loadProducts();
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        'Could not confirm the stock was added. Check the stock before '
        'trying again.',
      );
      await _loadProducts();
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ---------- UI ----------

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
        final isLow = product.stockQuantity <= _lowStockThreshold;
        final cost = product.costPrice;
        final buying = cost == null
            ? 'No buying price'
            : 'Buy: KES ${cost.toStringAsFixed(2)}';

        return ListTile(
          enabled: !_isSaving,
          title: Text(product.name),
          isThreeLine: true,
          subtitle: Text(
            'SKU: ${product.sku}\n'
            '$buying · Sell: KES ${product.price.toStringAsFixed(2)}',
          ),
          trailing: Text(
            product.stockQuantity <= 0
                ? 'Out of stock'
                : 'Stock: ${product.stockQuantity}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isLow ? Colors.red : null,
            ),
          ),
          onTap: _isSaving ? null : () => _openRestock(product),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restock'),
      ),
      body: Column(
        children: [
          if (_isSaving) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12.0),
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
          Expanded(child: _buildProductList()),
        ],
      ),
    );
  }
}

/// What the dialog hands back to the screen.
class _RestockInput {
  final int quantity;

  /// null = keep the product's current buying price.
  final double? newCostPrice;

  /// null = keep the product's current selling price.
  final double? newPrice;

  const _RestockInput({
    required this.quantity,
    this.newCostPrice,
    this.newPrice,
  });
}

/// Collects the quantity received and optional new buying and selling prices.
/// It only gathers input; the screen makes the API call, so the dialog is
/// already closed by the time anything is sent and can't be submitted twice.
class _RestockDialog extends StatefulWidget {
  final Product product;

  const _RestockDialog({required this.product});

  @override
  State<_RestockDialog> createState() => _RestockDialogState();
}

class _RestockDialogState extends State<_RestockDialog> {
  final _quantityController = TextEditingController();
  final _costController = TextEditingController();
  final _priceController = TextEditingController();

  String? _quantityError;
  String? _costError;
  String? _priceError;

  @override
  void dispose() {
    _quantityController.dispose();
    _costController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  /// The amount typed in [controller] if it is valid and above 0, else null.
  double? _typedAmount(TextEditingController controller) {
    final value = double.tryParse(controller.text.trim());
    return (value != null && value > 0) ? value : null;
  }

  void _submit() {
    final quantity = int.tryParse(_quantityController.text.trim());
    final costText = _costController.text.trim();
    final priceText = _priceController.text.trim();
    final parsedCost = costText.isEmpty ? null : double.tryParse(costText);
    final parsedPrice = priceText.isEmpty ? null : double.tryParse(priceText);

    final quantityOk = quantity != null && quantity > 0;
    final costOk = costText.isEmpty || (parsedCost != null && parsedCost > 0);
    final priceOk =
        priceText.isEmpty || (parsedPrice != null && parsedPrice > 0);

    if (!quantityOk || !costOk || !priceOk) {
      setState(() {
        _quantityError = quantityOk ? null : 'Enter a whole number above 0';
        _costError =
            costOk ? null : 'Enter a valid buying price, or leave it blank';
        _priceError =
            priceOk ? null : 'Enter a valid selling price, or leave it blank';
      });
      return;
    }

    // Only send a price that is actually different from the current one.
    final costChanged =
        parsedCost != null && parsedCost != widget.product.costPrice;
    final priceChanged =
        parsedPrice != null && parsedPrice != widget.product.price;

    Navigator.of(context).pop(
      _RestockInput(
        quantity: quantity,
        newCostPrice: costChanged ? parsedCost : null,
        newPrice: priceChanged ? parsedPrice : null,
      ),
    );
  }

  /// Profit per unit using the new prices where typed, the current ones
  /// where left blank. Turns red when there is no profit.
  Widget _buildProfitLine(Product product) {
    final cost = _typedAmount(_costController) ?? product.costPrice;
    final price = _typedAmount(_priceController) ?? product.price;

    if (cost == null) {
      return const Text('Profit per unit: unknown (no buying price saved)');
    }

    final profit = price - cost;

    if (profit <= 0) {
      return Text(
        'Profit per unit: KES ${profit.toStringAsFixed(2)}. '
        'The selling price is not above the buying price.',
        style: const TextStyle(
          color: Colors.red,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return Text(
      'Profit per unit: KES ${profit.toStringAsFixed(2)}',
      style: const TextStyle(fontWeight: FontWeight.bold),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final typed = int.tryParse(_quantityController.text.trim());
    final cost = product.costPrice;

    return AlertDialog(
      title: Text('Restock ${product.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _quantityController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Quantity received',
                border: const OutlineInputBorder(),
                helperText: typed != null && typed > 0
                    ? 'Stock now ${product.stockQuantity}, '
                        'after this: ${product.stockQuantity + typed}'
                    : 'Stock now: ${product.stockQuantity}',
                helperMaxLines: 2,
                errorText: _quantityError,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                setState(() {
                  _quantityError = null;
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _costController,
              decoration: InputDecoration(
                labelText: 'New buying price (KES, optional)',
                border: const OutlineInputBorder(),
                helperText: cost == null
                    ? 'No buying price saved yet'
                    : 'Now KES ${cost.toStringAsFixed(2)}. '
                        'Leave blank to keep it',
                helperMaxLines: 2,
                errorText: _costError,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                setState(() {
                  _costError = null;
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _priceController,
              decoration: InputDecoration(
                labelText: 'New selling price (KES, optional)',
                border: const OutlineInputBorder(),
                helperText: 'Now KES ${product.price.toStringAsFixed(2)}. '
                    'Leave blank to keep it',
                helperMaxLines: 2,
                errorText: _priceError,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                setState(() {
                  _priceError = null;
                });
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            _buildProfitLine(product),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Add stock'),
        ),
      ],
    );
  }
}