import 'package:flutter/material.dart';
import '../models/top_product.dart';
import '../services/api_service.dart';
import '../widgets/report_timeframe_bar.dart';

class TopProductsScreen extends StatefulWidget {
  const TopProductsScreen({super.key});

  @override
  State<TopProductsScreen> createState() => _TopProductsScreenState();
}

class _TopProductsScreenState extends State<TopProductsScreen> {
  final _apiService = ApiService();

  ReportTimeframe _timeframe = const ReportTimeframe(period: ReportPeriod.today);
  List<TopProduct> _products = [];
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
      final products = await _apiService.getTopProducts(
        period: _timeframe.periodParam,
        startDate: _timeframe.startDate,
        endDate: _timeframe.endDate,
      );
      if (!mounted) return;
      setState(() {
        _products = products;
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

  void _onTimeframeChanged(ReportTimeframe timeframe) {
    setState(() {
      _timeframe = timeframe;
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
        reportPath: 'top-products',
        format: format,
        period: _timeframe.periodParam,
        startDate: _timeframe.startDate,
        endDate: _timeframe.endDate,
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

    if (_products.isEmpty) {
      return const Center(child: Text('No sales in this period.'));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _products.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final product = _products[index];
          final rank = index + 1;

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: rank <= 3
                  ? Colors.amber.shade600
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              foregroundColor: rank <= 3 ? Colors.white : null,
              child: Text('$rank'),
            ),
            title: Text(product.name),
            subtitle: Text(
              '${product.quantitySold} sold · '
              'KES ${product.revenue.toStringAsFixed(2)} revenue'
              '${product.unitsMissingCost > 0 ? ' · ${product.unitsMissingCost} missing buying price' : ''}',
            ),
            trailing: Text(
              'KES ${product.profit.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: product.profit < 0 ? Colors.red : Colors.green.shade700,
              ),
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
        title: const Text('Top Products'),
      ),
      body: Column(
        children: [
          if (_isDownloading) const LinearProgressIndicator(),
          ReportTimeframeBar(
            timeframe: _timeframe,
            onChanged: _onTimeframeChanged,
            onDownload: _isDownloading ? null : _download,
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}