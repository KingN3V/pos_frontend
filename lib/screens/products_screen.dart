import 'package:flutter/material.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import 'add_product_screen.dart';
import 'product_edit_screen.dart';

class ProductsScreen extends StatefulWidget {
  /// When set, only products in this category are shown.
  final Category? category;

  const ProductsScreen({super.key, this.category});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  // Matches the default threshold of the backend's /reports/low-stock.
  static const int _lowStockThreshold = 5;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  final _apiService = ApiService();

  List<Product> _products = [];
  bool _isLoading = true;
  String? _errorMessage;

  // When on, the list shows ONLY hidden products, not hidden-plus-active.
  bool _showHidden = false;

  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final products = await _apiService.getProducts(
        categoryId: widget.category?.id,
        onlyHidden: _showHidden,
      );
      if (!mounted) return;
      setState(() {
        _products = products;
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

  Future<void> _openAddProduct() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => const AddProductScreen()),
    );

    if (created == true) {
      _loadProducts();
    }
  }

  Future<void> _openEditProduct(Product product) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => ProductEditScreen(product: product),
      ),
    );

    if (changed == true) {
      _loadProducts();
    }
  }

  void _toggleShowHidden(bool value) {
    setState(() {
      _showHidden = value;
    });
    _loadProducts();
  }

  Widget _buildBody() {
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
                onPressed: _loadProducts,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final products = _visibleProducts;

    if (_products.isEmpty) {
      return Center(
        child: Text(
          _showHidden
              ? (widget.category == null
                  ? 'No hidden products.'
                  : 'No hidden products in this category.')
              : (widget.category == null
                  ? 'No products yet.'
                  : 'No products in this category yet.'),
        ),
      );
    }

    if (products.isEmpty) {
      return const Center(child: Text('No products match your search.'));
    }

    return ListView.separated(
      itemCount: products.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final product = products[index];
        final isLow = product.stockQuantity <= _lowStockThreshold;
        final isHidden = !product.isActive;

        return ListTile(
          tileColor: isHidden ? Colors.grey.shade200 : null,
          title: Text(
            product.name,
            style: isHidden
                ? TextStyle(color: Colors.grey.shade600)
                : null,
          ),
          subtitle: Text(
            isHidden ? 'SKU: ${product.sku} · Hidden' : 'SKU: ${product.sku}',
            style: isHidden ? TextStyle(color: Colors.grey.shade600) : null,
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'KES ${product.price.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isHidden ? Colors.grey.shade600 : null,
                ),
              ),
              Text(
                product.stockQuantity == 0
                    ? 'Out of stock'
                    : 'Stock: ${product.stockQuantity}',
                style: TextStyle(
                  color: isHidden
                      ? Colors.grey.shade600
                      : (isLow ? Colors.red : null),
                ),
              ),
            ],
          ),
          onTap: () => _openEditProduct(product),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category?.name ?? 'Products'),
        actions: [
          Row(
            children: [
              const Text('Show hidden'),
              Switch(
                value: _showHidden,
                onChanged: _isLoading ? null : _toggleShowHidden,
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
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
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddProduct,
        child: const Icon(Icons.add),
      ),
    );
  }
}