import 'package:flutter/material.dart';
import '../models/order.dart';
import '../services/api_service.dart';

/// One customer's open (unpaid or partially paid) orders. Tap an order to
/// record a payment against it.
class CustomerOrdersScreen extends StatefulWidget {
  final int customerId;
  final String customerName;
  final String? customerPhone;

  const CustomerOrdersScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    this.customerPhone,
  });

  @override
  State<CustomerOrdersScreen> createState() => _CustomerOrdersScreenState();
}

class _CustomerOrdersScreenState extends State<CustomerOrdersScreen> {
  final _apiService = ApiService();

  List<Order> _orders = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final orders = await _apiService.getOrders(
        status: 'open',
        customerId: widget.customerId,
      );
      if (!mounted) return;
      setState(() {
        _orders = orders;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load orders. Check your connection.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- Payment ----------

  Future<void> _openPayment(Order order) async {
    final result = await showModalBottomSheet<_PaymentInput>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _PaymentSheet(order: order),
    );

    if (result == null || !mounted) return;
    await _recordPayment(order, result);
  }

  Future<void> _recordPayment(Order order, _PaymentInput input) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final error = await _apiService.recordPayment(
        orderId: order.id,
        method: input.method,
        amount: input.amount,
      );

      if (!mounted) return;

      if (error == null) {
        final remaining = order.balanceDue - input.amount;
        _showMessage(
          remaining <= 0.01
              ? '${order.orderNumber} paid off'
              : '${order.orderNumber} — KES ${remaining.toStringAsFixed(2)} still owed',
        );
      } else {
        _showMessage(error);
      }

      await _load();
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        'Could not confirm the payment. Check your connection, then check '
        'the balance before trying again.',
      );
      await _load();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ---------- UI ----------

  Widget _buildBody() {
    if (_isLoading && _orders.isEmpty) {
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
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_orders.isEmpty) {
      return const Center(
        child: Text('No open orders. All paid up.'),
      );
    }

    final totalOwed = _orders.fold(0.0, (sum, o) => sum + o.balanceDue);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Total owed: KES ${totalOwed.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          for (final order in _orders) ...[
            ListTile(
              enabled: !_isLoading,
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(order.orderNumber),
              subtitle: Text(
                '${order.unitCount} item${order.unitCount == 1 ? '' : 's'} · '
                'Total KES ${order.total.toStringAsFixed(2)} · '
                'Paid KES ${order.amountPaid.toStringAsFixed(2)}',
              ),
              trailing: Text(
                'KES ${order.balanceDue.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              onTap: _isLoading ? null : () => _openPayment(order),
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.customerPhone;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customerName),
      ),
      body: Column(
        children: [
          if (phone != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Phone: $phone'),
              ),
            ),
          if (_isLoading && _orders.isNotEmpty) const LinearProgressIndicator(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}

// ---------- Payment sheet ----------

class _PaymentInput {
  final double amount;
  final String method;

  const _PaymentInput({required this.amount, required this.method});
}

/// Collects the amount being paid off and the method. Only gathers input;
/// the screen makes the API call, so this sheet is already closed by the
/// time anything is sent and can't be submitted twice.
class _PaymentSheet extends StatefulWidget {
  final Order order;

  const _PaymentSheet({required this.order});

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late final TextEditingController _amountController;
  String _method = 'CASH';
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _amountController =
        TextEditingController(text: widget.order.balanceDue.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    final balance = widget.order.balanceDue;
    final value = double.tryParse(_amountController.text.trim());

    if (value == null || value <= 0) {
      setState(() => _errorText = 'Enter a valid amount above 0');
      return;
    }
    if (value > balance + 0.01) {
      setState(() =>
          _errorText = 'Cannot exceed the balance of KES ${balance.toStringAsFixed(2)}');
      return;
    }

    Navigator.of(context).pop(_PaymentInput(amount: value, method: _method));
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${order.orderNumber} — record payment',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Balance due: KES ${order.balanceDue.toStringAsFixed(2)}'),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Amount paid now (KES)',
                  border: const OutlineInputBorder(),
                  errorText: _errorText,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) {
                  if (_errorText != null) setState(() => _errorText = null);
                },
              ),
              const SizedBox(height: 16),
              const Text('How is the customer paying?'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Cash'),
                      selected: _method == 'CASH',
                      onSelected: (_) => setState(() => _method = 'CASH'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('M-Pesa'),
                      selected: _method == 'MPESA',
                      onSelected: (_) => setState(() => _method = 'MPESA'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _submit,
                child: const Text('Record payment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}