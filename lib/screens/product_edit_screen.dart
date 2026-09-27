import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../services/api_service.dart';

/// Reasons for taking stock out that are not a sale. The value is what is
/// saved as the stock movement's type; expired/damaged are losses, mistake
/// is a correction (she typed the wrong number when adding it).
enum _RemovalReason {
  expired('expired', 'Expired'),
  damaged('damaged', 'Damaged'),
  mistake('correction', 'Entered by mistake');

  final String value;
  final String label;

  const _RemovalReason(this.value, this.label);
}

/// Edit a product's details, remove stock that was lost (not sold), or
/// hide/unhide it. Pops with `true` if anything was actually changed, so
/// the screen that opened this one knows whether to reload its list.
class ProductEditScreen extends StatefulWidget {
  final Product product;

  const ProductEditScreen({super.key, required this.product});

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final _apiService = ApiService();

  // Local copy of the product's editable fields. Updated only after the
  // server confirms a change, so the screen always reflects what was
  // actually saved.
  late String _sku;
  late String _name;
  late String _description;
  int? _categoryId;
  late double _price;
  double? _costPrice;
  late bool _isActive;
  late int _stockQuantity;

  final _skuController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _costController = TextEditingController();

  List<Category> _categories = [];
  bool _categoriesLoaded = false;
  bool _categoriesFailed = false;

  bool _isSavingDetails = false;
  String? _detailsError;

  final _removeQuantityController = TextEditingController();
  final _removeNoteController = TextEditingController();
  _RemovalReason _removalReason = _RemovalReason.expired;
  bool _isRemovingStock = false;
  String? _removeQuantityError;

  bool _isChangingStatus = false;

  bool _changedSomething = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _sku = p.sku;
    _name = p.name;
    _description = p.description ?? '';
    _categoryId = p.categoryId;
    _price = p.price;
    _costPrice = p.costPrice;
    _isActive = p.isActive;
    _stockQuantity = p.stockQuantity;

    _skuController.text = _sku;
    _nameController.text = _name;
    _descriptionController.text = _description;
    _priceController.text = _price.toStringAsFixed(2);
    _costController.text = _costPrice?.toStringAsFixed(2) ?? '';

    _loadCategories();
  }

  @override
  void dispose() {
    _skuController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _removeQuantityController.dispose();
    _removeNoteController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _apiService.getCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _categoriesLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _categoriesFailed = true;
        _categoriesLoaded = true;
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- Details ----------

  Future<void> _saveDetails() async {
    final sku = _skuController.text.trim();
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final priceText = _priceController.text.trim();
    final costText = _costController.text.trim();

    if (sku.isEmpty || name.isEmpty || priceText.isEmpty || costText.isEmpty) {
      setState(() {
        _detailsError = 'Please fill in SKU, name, buying price and selling price';
      });
      return;
    }

    final price = double.tryParse(priceText);
    if (price == null || price <= 0) {
      setState(() {
        _detailsError = 'Please enter a valid selling price';
      });
      return;
    }

    final costPrice = double.tryParse(costText);
    if (costPrice == null || costPrice <= 0) {
      setState(() {
        _detailsError = 'Please enter a valid buying price';
      });
      return;
    }

    // Only send what actually changed.
    final skuChanged = sku != _sku;
    final nameChanged = name != _name;
    final descriptionChanged = description != _description;
    final categoryChanged = _pendingCategoryId != _categoryId;
    final priceChanged = price != _price;
    final costChanged = costPrice != _costPrice;

    if (!skuChanged &&
        !nameChanged &&
        !descriptionChanged &&
        !categoryChanged &&
        !priceChanged &&
        !costChanged) {
      _showMessage('Nothing to save');
      return;
    }

    if (price <= costPrice) {
      final proceed = await _confirmNoProfit(price, costPrice);
      if (!proceed || !mounted) return;
    }

    setState(() {
      _isSavingDetails = true;
      _detailsError = null;
    });

    try {
      final error = await _apiService.updateProduct(
        productId: widget.product.id,
        sku: skuChanged ? sku : null,
        name: nameChanged ? name : null,
        description: descriptionChanged ? description : null,
        categoryId: categoryChanged ? _pendingCategoryId : null,
        price: priceChanged ? price : null,
        costPrice: costChanged ? costPrice : null,
      );

      if (!mounted) return;

      if (error == null) {
        setState(() {
          _sku = sku;
          _name = name;
          _description = description;
          _categoryId = _pendingCategoryId;
          _price = price;
          _costPrice = costPrice;
          _changedSomething = true;
        });
        _showMessage('Saved');
      } else {
        setState(() {
          _detailsError = error;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _detailsError = 'Could not reach the server. Check your connection.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSavingDetails = false;
        });
      }
    }
  }

  // Category dropdown state lives separately so it can be compared to
  // _categoryId without touching the text controllers above.
  int? _pendingCategoryId;
  bool _categoryInitialised = false;

  Future<bool> _confirmNoProfit(double price, double costPrice) async {
    final profit = price - costPrice;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No profit on this price'),
        content: Text(
          profit == 0
              ? 'The selling price equals the buying price, so there is no '
                  'profit on this item.'
              : 'The selling price is below the buying price, so this item '
                  'sells at a loss of KES ${(-profit).toStringAsFixed(2)} '
                  'per unit.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Go back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ---------- Remove stock ----------

  Future<void> _removeStock() async {
    final quantity = int.tryParse(_removeQuantityController.text.trim());

    if (quantity == null || quantity <= 0) {
      setState(() {
        _removeQuantityError = 'Enter a whole number above 0';
      });
      return;
    }

    if (quantity > _stockQuantity) {
      setState(() {
        _removeQuantityError = 'Only $_stockQuantity in stock';
      });
      return;
    }

    setState(() {
      _isRemovingStock = true;
      _removeQuantityError = null;
    });

    try {
      final note = _removeNoteController.text.trim();
      final error = await _apiService.removeStock(
        productId: widget.product.id,
        quantity: quantity,
        reason: _removalReason.value,
        note: note.isEmpty ? null : note,
      );

      if (!mounted) return;

      if (error == null) {
        setState(() {
          _stockQuantity -= quantity;
          _changedSomething = true;
        });
        _removeQuantityController.clear();
        _removeNoteController.clear();
        _showMessage(
          'Removed $quantity (${_removalReason.label.toLowerCase()})',
        );
      } else {
        _showMessage(error);
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        'Could not confirm the stock was removed. Check the stock before '
        'trying again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRemovingStock = false;
        });
      }
    }
  }

  // ---------- Hide / unhide ----------

  Future<void> _confirmHide() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hide $_name?'),
        content: Text(
          _stockQuantity > 0
              ? 'It will no longer appear when selling, restocking or '
                  'adding products. The $_stockQuantity in stock stay '
                  'recorded. Past sales are not affected. You can unhide '
                  'it later.'
              : 'It will no longer appear when selling, restocking or '
                  'adding products. Past sales are not affected. You can '
                  'unhide it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hide product'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _setActive(false);
    }
  }

  Future<void> _setActive(bool active) async {
    setState(() {
      _isChangingStatus = true;
    });

    try {
      if (active) {
        await _apiService.reactivateProduct(widget.product.id);
      } else {
        await _apiService.hideProduct(widget.product.id);
      }

      if (!mounted) return;
      setState(() {
        _isActive = active;
        _changedSomething = true;
      });
      _showMessage(active ? 'Product unhidden' : 'Product hidden');
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not reach the server. Check your connection.');
    } finally {
      if (mounted) {
        setState(() {
          _isChangingStatus = false;
        });
      }
    }
  }

  // ---------- UI ----------

  Widget _buildDetailsCard() {
    if (!_categoryInitialised) {
      _pendingCategoryId = _categoryId;
      _categoryInitialised = true;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              enabled: !_isSavingDetails,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _skuController,
              decoration: const InputDecoration(
                labelText: 'SKU',
                border: OutlineInputBorder(),
              ),
              enabled: !_isSavingDetails,
            ),
            const SizedBox(height: 16),
            if (!_categoriesLoaded)
              const TextField(
                enabled: false,
                decoration: InputDecoration(
                  labelText: 'Category (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Loading categories…',
                ),
              )
            else if (_categoriesFailed)
              const TextField(
                enabled: false,
                decoration: InputDecoration(
                  labelText: 'Category (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Could not load — category will not change',
                ),
              )
            else
              DropdownButtonFormField<int?>(
                initialValue: _pendingCategoryId,
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
                onChanged: _isSavingDetails
                    ? null
                    : (value) {
                        setState(() {
                          _pendingCategoryId = value;
                        });
                      },
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _costController,
              decoration: const InputDecoration(
                labelText: 'Buying price (KES)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              enabled: !_isSavingDetails,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _priceController,
              decoration: const InputDecoration(
                labelText: 'Selling price (KES)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              enabled: !_isSavingDetails,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              enabled: !_isSavingDetails,
            ),
            const SizedBox(height: 16),
            if (_detailsError != null) ...[
              Text(
                _detailsError!,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 8),
            ],
            ElevatedButton(
              onPressed: _isSavingDetails ? null : _saveDetails,
              child: _isSavingDetails
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save details'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoveStockCard() {
    final typed = int.tryParse(_removeQuantityController.text.trim());
    final resulting = typed != null ? _stockQuantity - typed : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Remove stock', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              'For stock that did not sell: expired, damaged, or entered by '
              'mistake. To sell it, use New Sale instead.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _removeQuantityController,
              decoration: InputDecoration(
                labelText: 'Quantity to remove',
                border: const OutlineInputBorder(),
                helperText: resulting != null
                    ? 'Stock now $_stockQuantity, after this: $resulting'
                    : 'Stock now: $_stockQuantity',
                helperMaxLines: 2,
                errorText: _removeQuantityError,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              enabled: !_isRemovingStock,
              onChanged: (_) {
                setState(() {
                  _removeQuantityError = null;
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<_RemovalReason>(
              initialValue: _removalReason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
              items: _RemovalReason.values
                  .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                  .toList(),
              onChanged: _isRemovingStock
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _removalReason = value;
                        });
                      }
                    },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _removeNoteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
              enabled: !_isRemovingStock,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: (_isRemovingStock || _stockQuantity <= 0)
                  ? null
                  : _removeStock,
              child: _isRemovingStock
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Remove stock'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Product status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _isActive ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: _isActive ? Colors.green.shade700 : Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  _isActive ? 'Active — shown in the app' : 'Hidden — not shown in the app',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isActive ? Colors.green.shade700 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: _isActive
                  ? ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    )
                  : null,
              onPressed: _isChangingStatus
                  ? null
                  : (_isActive ? _confirmHide : () => _setActive(true)),
              child: _isChangingStatus
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _isActive ? Colors.white : null,
                      ),
                    )
                  : Text(_isActive ? 'Hide product' : 'Unhide product'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pop(_changedSomething);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Edit ${widget.product.name}'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDetailsCard(),
              const SizedBox(height: 16),
              _buildRemoveStockCard(),
              const SizedBox(height: 16),
              _buildStatusCard(),
            ],
          ),
        ),
      ),
    );
  }
}