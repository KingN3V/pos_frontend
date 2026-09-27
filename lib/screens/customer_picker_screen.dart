import 'dart:async';
import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../services/api_service.dart';

/// Lets her search existing customers or add a new one, then pops with
/// the selected Customer. Pushed from the sale screen when she chooses
/// "on account" / adds a customer to the sale.
class CustomerPickerScreen extends StatefulWidget {
  const CustomerPickerScreen({super.key});

  @override
  State<CustomerPickerScreen> createState() => _CustomerPickerScreenState();
}

class _CustomerPickerScreenState extends State<CustomerPickerScreen> {
  final _apiService = ApiService();
  final _searchController = TextEditingController();

  List<Customer> _customers = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final customers = await _apiService.getCustomers(
        query: _query.trim().isEmpty ? null : _query.trim(),
      );
      if (!mounted) return;
      setState(() {
        _customers = customers;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load customers. Check your connection.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _query = value;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _loadCustomers);
  }

  Future<void> _openAddDialog() async {
    final created = await showDialog<Customer>(
      context: context,
      builder: (context) => const _AddCustomerDialog(),
    );

    if (created == null) return;

    // She was mid-search when she added this customer, so hand the new
    // customer straight back to the sale instead of making her find it
    // in the refreshed list.
    if (!mounted) return;
    Navigator.of(context).pop(created);
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
                onPressed: _loadCustomers,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_customers.isEmpty) {
      return Center(
        child: Text(
          _query.trim().isEmpty
              ? 'No customers yet. Tap + to add one.'
              : 'No customers match your search.',
        ),
      );
    }

    return ListView.separated(
      itemCount: _customers.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final customer = _customers[index];
        return ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(customer.name),
          subtitle:
              customer.phoneNumber != null ? Text(customer.phoneNumber!) : null,
          onTap: () => Navigator.of(context).pop(customer),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Customer'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by name or phone',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Small dialog with name + phone fields. Pops with the created Customer
/// so the picker screen can hand it straight back.
class _AddCustomerDialog extends StatefulWidget {
  const _AddCustomerDialog();

  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _apiService = ApiService();

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final phoneText = _phoneController.text.trim();
    final phone = phoneText.isEmpty ? null : phoneText;

    if (name.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a name';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final error = await _apiService.createCustomer(
        name: name,
        phoneNumber: phone,
      );

      if (!mounted) return;

      if (error != null) {
        setState(() {
          _errorMessage = error;
          _isSaving = false;
        });
        return;
      }

      // createCustomer only confirms success, not the new row's id, so
      // search for it by name + phone before handing it back.
      final matches = await _apiService.getCustomers(query: name);
      if (!mounted) return;

      Customer? match;
      for (final c in matches) {
        if (c.name == name && c.phoneNumber == phone) {
          match = c;
          break;
        }
      }

      if (match != null) {
        Navigator.of(context).pop(match);
      } else {
        // Extremely unlikely, but don't guess: close without selecting so
        // she can pick the new customer from the refreshed list herself.
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not reach the server. Check your connection.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Customer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            enabled: !_isSaving,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: 'Phone number (optional)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            enabled: !_isSaving,
            onSubmitted: (_) => _isSaving ? null : _save(),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}