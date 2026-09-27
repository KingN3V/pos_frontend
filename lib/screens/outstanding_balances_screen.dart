import 'dart:async';
import 'package:flutter/material.dart';
import '../models/outstanding_balance.dart';
import '../services/api_service.dart';
import 'customer_orders_screen.dart';

/// Everyone who currently owes money, worst first. Tap a customer to see
/// and pay off their individual open orders.
class OutstandingBalancesScreen extends StatefulWidget {
  const OutstandingBalancesScreen({super.key});

  @override
  State<OutstandingBalancesScreen> createState() =>
      _OutstandingBalancesScreenState();
}

class _OutstandingBalancesScreenState
    extends State<OutstandingBalancesScreen> {
  final _apiService = ApiService();
  final _searchController = TextEditingController();

  List<OutstandingBalance> _balances = [];
  double? _totalOwedUnfiltered;
  bool _isLoading = true;
  bool _isDownloading = false;
  String? _errorMessage;
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final isFiltered = _query.trim().isNotEmpty;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final balances = await _apiService.getOutstandingBalances(
        query: isFiltered ? _query.trim() : null,
      );
      if (!mounted) return;
      setState(() {
        _balances = balances;
        // Only the unfiltered load tells us the shop-wide total; keep the
        // last known one on screen while a search is active instead of
        // losing it.
        if (!isFiltered) {
          _totalOwedUnfiltered =
              balances.fold<double>(0.0, (sum, b) => sum + b.totalBalanceDue);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load balances. Check your connection.';
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
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _openCustomer(OutstandingBalance balance) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CustomerOrdersScreen(
          customerId: balance.customerId,
          customerName: balance.customerName,
          customerPhone: balance.phoneNumber,
        ),
      ),
    );
    // A payment may have changed things while that screen was open.
    _load();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _download(String format) async {
    setState(() {
      _isDownloading = true;
    });

    try {
      await _apiService.downloadReport(
        reportPath: 'outstanding-balances',
        format: format,
        // Exports the full list regardless of any active search filter —
        // she's downloading this to hand off or keep, not just what she
        // happens to be looking at on screen.
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not download the report. Check your connection.');
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _showDownloadOptions() async {
    final format = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Download as CSV'),
              onTap: () => Navigator.of(context).pop('csv'),
            ),
            ListTile(
              leading: const Icon(Icons.grid_on_outlined),
              title: const Text('Download as Excel'),
              onTap: () => Navigator.of(context).pop('excel'),
            ),
          ],
        ),
      ),
    );

    if (format != null) {
      await _download(format);
    }
  }

  Widget _buildBody() {
    if (_isLoading && _balances.isEmpty) {
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

    final isFiltered = _query.trim().isNotEmpty;

    if (_balances.isEmpty) {
      return Center(
        child: Text(
          isFiltered
              ? 'No customers match your search.'
              : 'No outstanding balances. Everyone is paid up.',
        ),
      );
    }

    final visibleTotal =
        _balances.fold(0.0, (sum, b) => sum + b.totalBalanceDue);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              isFiltered
                  ? 'Showing: KES ${visibleTotal.toStringAsFixed(2)}'
                      '${_totalOwedUnfiltered != null ? ' (total owed: KES ${_totalOwedUnfiltered!.toStringAsFixed(2)})' : ''}'
                  : 'Total owed: KES ${visibleTotal.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          for (final balance in _balances) ...[
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(balance.customerName),
              subtitle: Text(
                '${balance.openOrderCount} open order'
                '${balance.openOrderCount == 1 ? '' : 's'}'
                '${balance.phoneNumber != null ? ' · ${balance.phoneNumber}' : ''}',
              ),
              trailing: Text(
                'KES ${balance.totalBalanceDue.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              onTap: () => _openCustomer(balance),
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Outstanding Balances'),
        actions: [
          IconButton(
            icon: _isDownloading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_outlined),
            tooltip: 'Download',
            onPressed: _isDownloading ? null : _showDownloadOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isDownloading) const LinearProgressIndicator(),
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
    );
  }
}