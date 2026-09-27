import 'package:flutter/material.dart';
import '../models/low_stock.dart';
import '../services/api_service.dart';

class LowStockScreen extends StatefulWidget {
  const LowStockScreen({super.key});

  @override
  State<LowStockScreen> createState() => _LowStockScreenState();
}

class _LowStockScreenState extends State<LowStockScreen> {
  // Matches the backend's default and the threshold already used elsewhere
  // in the app (products_screen.dart, restock_screen.dart).
  static const int _defaultThreshold = 5;

  final _apiService = ApiService();

  int _threshold = _defaultThreshold;
  List<LowStockItem> _items = [];
  bool _isLoading = true;
  bool _isDownloading = false;
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
      final items = await _apiService.getLowStock(threshold: _threshold);
      if (!mounted) return;
      setState(() {
        _items = items;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load the report. Check your connection.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onThresholdChanged(int value) {
    setState(() {
      _threshold = value;
    });
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
        reportPath: 'low-stock',
        format: format,
        extraParams: {'threshold': _threshold.toString()},
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

  Widget _buildThresholdBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          const Text('Show stock at or below:'),
          Expanded(
            child: Slider(
              value: _threshold.toDouble(),
              min: 1,
              max: 50,
              divisions: 49,
              label: '$_threshold',
              onChanged: _isLoading
                  ? null
                  : (value) => setState(() => _threshold = value.round()),
              onChangeEnd: (value) => _onThresholdChanged(value.round()),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$_threshold',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: _isDownloading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            tooltip: 'Download',
            onPressed: _isDownloading ? null : _showDownloadOptions,
          ),
        ],
      ),
    );
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
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Text('Nothing at or below $_threshold in stock.'),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = _items[index];
          final isOut = item.stockQuantity <= 0;

          return ListTile(
            leading: Icon(
              isOut ? Icons.remove_shopping_cart_outlined : Icons.warning_amber_outlined,
              color: Colors.red,
            ),
            title: Text(item.name),
            subtitle: Text('SKU: ${item.sku}'),
            trailing: Text(
              isOut ? 'Out of stock' : 'Stock: ${item.stockQuantity}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Low Stock'),
      ),
      body: Column(
        children: [
          _buildThresholdBar(),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}