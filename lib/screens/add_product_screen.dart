import 'package:flutter/material.dart';
import '../models/category.dart';
import '../services/api_service.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _nameController = TextEditingController();
  final _skuController = TextEditingController();
  final _priceController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _stockController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _apiService = ApiService();

  List<Category> _categories = [];
  int? _selectedCategoryId;
  bool _categoriesFailed = false;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _priceController.dispose();
    _costPriceController.dispose();
    _stockController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _apiService.getCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _categoriesFailed = true;
      });
    }
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    final sku = _skuController.text.trim();
    final priceText = _priceController.text.trim();
    final costText = _costPriceController.text.trim();
    final stockText = _stockController.text.trim();
    final description = _descriptionController.text.trim();

    if (name.isEmpty ||
        sku.isEmpty ||
        priceText.isEmpty ||
        costText.isEmpty) {
      setState(() {
        _errorMessage =
            'Please fill in name, SKU, buying price and selling price';
      });
      return;
    }

    final price = double.tryParse(priceText);
    if (price == null || price <= 0) {
      setState(() {
        _errorMessage = 'Please enter a valid selling price';
      });
      return;
    }

    final costPrice = double.tryParse(costText);
    if (costPrice == null || costPrice <= 0) {
      setState(() {
        _errorMessage = 'Please enter a valid buying price';
      });
      return;
    }

    final stock = stockText.isEmpty ? 0 : int.tryParse(stockText);
    if (stock == null || stock < 0) {
      setState(() {
        _errorMessage = 'Stock must be a whole number, 0 or more';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final error = await _apiService.createProduct(
        sku: sku,
        name: name,
        description: description,
        categoryId: _selectedCategoryId,
        price: price,
        costPrice: costPrice,
        stockQuantity: stock,
      );

      if (!mounted) return;

      if (error == null) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _errorMessage = error;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not reach the server. Check your connection.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Product'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _skuController,
              decoration: const InputDecoration(
                labelText: 'SKU',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              value: _selectedCategoryId,
              decoration: const InputDecoration(
                labelText: 'Category (optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('No category'),
                ),
                ..._categories.map(
                  (c) => DropdownMenuItem<int?>(
                    value: c.id,
                    child: Text(c.name),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedCategoryId = value;
                });
              },
            ),
            if (_categoriesFailed) ...[
              const SizedBox(height: 8),
              const Text(
                'Could not load categories. You can still save without one.',
                style: TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _costPriceController,
              decoration: const InputDecoration(
                labelText: 'Buying price (KES)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _priceController,
              decoration: const InputDecoration(
                labelText: 'Selling price (KES)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _stockController,
              decoration: const InputDecoration(
                labelText: 'Stock on hand (leave blank for 0)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleSave(),
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
            ElevatedButton(
              onPressed: _isLoading ? null : _handleSave,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Product'),
            ),
          ],
        ),
      ),
    );
  }
}