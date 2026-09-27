import 'package:flutter/material.dart';
import '../models/sales_summary.dart';
import '../services/api_service.dart';
import '../widgets/report_timeframe_bar.dart';

class SalesSummaryScreen extends StatefulWidget {
  const SalesSummaryScreen({super.key});

  @override
  State<SalesSummaryScreen> createState() => _SalesSummaryScreenState();
}

class _SalesSummaryScreenState extends State<SalesSummaryScreen> {
  final _apiService = ApiService();

  ReportTimeframe _timeframe = const ReportTimeframe(period: ReportPeriod.today);
  SalesSummary? _summary;
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
      final summary = await _apiService.getSalesSummary(
        period: _timeframe.periodParam,
        startDate: _timeframe.startDate,
        endDate: _timeframe.endDate,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
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
        reportPath: 'sales-summary',
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

  Widget _buildSummaryCard(SalesSummary summary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row('Orders', '${summary.orderCount}'),
            const Divider(height: 24),
            _row(
              'Revenue',
              'KES ${summary.totalRevenue.toStringAsFixed(2)}',
              bold: true,
            ),
            const SizedBox(height: 4),
            _row(
              'Profit',
              'KES ${summary.totalProfit.toStringAsFixed(2)}',
              bold: true,
              color: summary.totalProfit < 0 ? Colors.red : Colors.green.shade700,
            ),
            if (summary.unitsMissingCost > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${summary.unitsMissingCost} unit'
                '${summary.unitsMissingCost == 1 ? '' : 's'} sold with no buying '
                'price recorded — profit for those is not counted above.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 18 : null,
      color: color,
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }

  Widget _buildRevenueByMethod(SalesSummary summary) {
    if (summary.revenueByMethod.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Revenue by payment method',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            for (final entry in summary.revenueByMethod.entries) ...[
              _row(
                entry.key == 'MPESA' ? 'M-Pesa' : entry.key,
                'KES ${entry.value.toStringAsFixed(2)}',
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
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

    final summary = _summary;
    if (summary == null) {
      return const SizedBox.shrink();
    }

    if (summary.orderCount == 0) {
      return const Center(child: Text('No completed sales in this period.'));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12.0),
        children: [
          _buildSummaryCard(summary),
          const SizedBox(height: 12),
          _buildRevenueByMethod(summary),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Summary'),
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