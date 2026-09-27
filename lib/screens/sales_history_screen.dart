import 'dart:async';
import 'package:flutter/material.dart';
import '../models/order.dart';
import '../services/api_service.dart';
import '../widgets/report_timeframe_bar.dart';

/// The filter chips. [status] is what the backend calls it: a "Sold" order
/// is one whose status is 'completed'.
enum _Filter {
  all('All', null, 'No sales yet. Sales will show up here.'),
  sold('Sold', 'completed', 'No completed sales yet.'),
  open('Open', 'open', 'No open orders. Nothing is holding stock.'),
  cancelled('Cancelled', 'cancelled', 'No cancelled orders.');

  final String label;
  final String? status;
  final String emptyText;

  const _Filter(this.label, this.status, this.emptyText);
}

// ---------- Small helpers ----------

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

String _formatTime(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final daysAgo = today.difference(day).inDays;
  final time = '${_two(t.hour)}:${_two(t.minute)}';

  if (daysAgo == 0) return 'Today, $time';
  if (daysAgo == 1) return 'Yesterday, $time';
  return '${t.day} ${_months[t.month - 1]} ${t.year}, $time';
}

String _statusLabel(Order order) {
  if (order.isCompleted) return 'Sold';
  if (order.isOpen) return 'Open';
  return 'Cancelled';
}

Color _statusColor(Order order) {
  if (order.isCompleted) return Colors.green.shade700;
  if (order.isOpen) return Colors.orange.shade800;
  return Colors.grey.shade600;
}

IconData _statusIcon(Order order) {
  if (order.isCompleted) return Icons.check_circle_outline;
  if (order.isOpen) return Icons.hourglass_bottom;
  return Icons.cancel_outlined;
}

Widget _moneyRow(String label, double amount, {bool bold = false, Color? color}) {
  final style = TextStyle(
    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    fontSize: bold ? 16 : null,
    color: color,
  );
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2.0),
    child: Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text('KES ${amount.toStringAsFixed(2)}', style: style),
      ],
    ),
  );
}

// ---------- Screen ----------

/// Recent sales, newest first, within a chosen time period, optionally
/// searched by customer. Lets her check whether a sale went through (for
/// example after a lost connection) and cancel an order that is still
/// open, which puts its stock back.
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  static const int _pageSize = 50;

  final _apiService = ApiService();
  final _searchController = TextEditingController();

  ReportTimeframe _timeframe = const ReportTimeframe(period: ReportPeriod.today);
  _Filter _filter = _Filter.all;
  String _query = '';
  Timer? _debounce;

  List<Order> _orders = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isCancelling = false;
  bool _isDownloading = false;
  bool _hasMore = false;
  String? _errorMessage;

  // Bumped on every fresh load, so a slow reply for a filter she has already
  // left can't overwrite the list she is looking at now.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ---------- Data ----------

  Future<void> _loadFirstPage({bool showSpinner = true}) async {
    final requestId = ++_requestId;

    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final orders = await _apiService.getOrders(
        status: _filter.status,
        query: _query.trim().isEmpty ? null : _query.trim(),
        period: _timeframe.periodParam,
        startDate: _timeframe.startDate,
        endDate: _timeframe.endDate,
        limit: _pageSize,
      );

      if (!mounted || requestId != _requestId) return;
      setState(() {
        _orders = orders;
        _hasMore = orders.length >= _pageSize;
        _errorMessage = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;

      if (showSpinner || _orders.isEmpty) {
        setState(() {
          _errorMessage = 'Could not load sales. Check your connection.';
          _isLoading = false;
        });
      } else {
        // Keep showing what she already has.
        _showMessage('Could not refresh. Check your connection.');
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    final requestId = _requestId;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final more = await _apiService.getOrders(
        status: _filter.status,
        query: _query.trim().isEmpty ? null : _query.trim(),
        period: _timeframe.periodParam,
        startDate: _timeframe.startDate,
        endDate: _timeframe.endDate,
        limit: _pageSize,
        offset: _orders.length,
      );

      if (!mounted || requestId != _requestId) return;

      final known = _orders.map((o) => o.id).toSet();
      final fresh = more.where((o) => !known.contains(o.id)).toList();

      setState(() {
        _orders = [..._orders, ...fresh];
        _hasMore = more.length >= _pageSize;
      });
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not load more. Check your connection.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  void _selectFilter(_Filter filter) {
    if (filter == _filter) return;

    setState(() {
      _filter = filter;
      _orders = [];
      _hasMore = false;
    });
    _loadFirstPage();
  }

  void _onTimeframeChanged(ReportTimeframe timeframe) {
    setState(() {
      _timeframe = timeframe;
      _orders = [];
      _hasMore = false;
    });
    _loadFirstPage();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _query = value;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _orders = [];
      _hasMore = false;
      _loadFirstPage();
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- Download ----------

  Future<void> _download(String format) async {
    setState(() {
      _isDownloading = true;
    });

    try {
      await _apiService.downloadOrders(
        format: format,
        status: _filter.status,
        query: _query.trim().isEmpty ? null : _query.trim(),
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

  // ---------- Details and cancelling ----------

  Future<void> _openDetails(Order order) async {
    final wantsCancel = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _OrderDetailsSheet(order: order),
    );

    if (wantsCancel != true || !mounted) return;

    final confirmed = await _confirmCancel(order);
    if (!confirmed || !mounted) return;

    await _cancelOrder(order);
  }

  Future<bool> _confirmCancel(Order order) async {
    final units = order.unitCount;
    final paid = order.amountPaid;

    var message = 'The $units item${units == 1 ? '' : 's'} will go back into '
        'stock. This cannot be undone.';
    if (paid > 0.005) {
      message += '\n\nKES ${paid.toStringAsFixed(2)} was already recorded as '
          'paid on this order. Cancelling does not refund it, so give that '
          'money back yourself.';
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel ${order.orderNumber}?'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep order'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _cancelOrder(Order order) async {
    setState(() {
      _isCancelling = true;
    });

    try {
      final error = await _apiService.cancelOrder(order.id);

      if (!mounted) return;

      if (error == null) {
        _showMessage('${order.orderNumber} cancelled. Stock put back.');
      } else {
        _showMessage(error);
      }

      // Reload either way, so the list shows what the server really has.
      await _loadFirstPage(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        'Could not confirm the cancellation. Check your connection, then '
        'look at the order again.',
      );
      await _loadFirstPage(showSpinner: false);
    } finally {
      if (mounted) {
        setState(() {
          _isCancelling = false;
        });
      }
    }
  }

  // ---------- UI ----------

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 0),
      child: TextField(
        controller: _searchController,
        decoration: const InputDecoration(
          labelText: 'Search by customer name or phone',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Row(
        children: [
          for (final filter in _Filter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                label: Text(filter.label),
                selected: _filter == filter,
                onSelected: (_) => _selectFilter(filter),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderTile(Order order) {
    final color = _statusColor(order);
    final customer = order.customerName;
    final units = order.unitCount;

    final details = [
      '$units item${units == 1 ? '' : 's'}',
            ?customer,
    ].join(' · ');

    return ListTile(
      enabled: !_isCancelling,
      isThreeLine: true,
      tileColor: order.isOpen ? Colors.orange.shade50 : null,
      leading: Icon(_statusIcon(order), color: color),
      title: Text(
        '${order.orderNumber} · KES ${order.total.toStringAsFixed(2)}',
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_formatTime(order.createdAt)),
          Text(details),
          if (order.isOpen)
            Text(
              'Not fully paid. Stock is being held.',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
        ],
      ),
      trailing: Text(
        _statusLabel(order),
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
      onTap: _isCancelling ? null : () => _openDetails(order),
    );
  }

  Widget _buildList() {
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
                onPressed: _loadFirstPage,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final isFiltered = _query.trim().isNotEmpty;

    if (_orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadFirstPage(showSpinner: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  isFiltered
                      ? 'No sales match your search in this period.'
                      : _filter.emptyText,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadFirstPage(showSpinner: false),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _orders.length + (_hasMore ? 1 : 0),
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == _orders.length) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: _isLoadingMore
                    ? const CircularProgressIndicator()
                    : TextButton(
                        onPressed: _loadMore,
                        child: const Text('Load more'),
                      ),
              ),
            );
          }
          return _buildOrderTile(_orders[index]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales History'),
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
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: (_isLoading || _isCancelling) ? null : _loadFirstPage,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isCancelling || _isDownloading) const LinearProgressIndicator(),
          ReportTimeframeBar(
            timeframe: _timeframe,
            onChanged: _onTimeframeChanged,
          ),
          _buildFilterChips(),
          _buildSearchBar(),
          const SizedBox(height: 8),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }
}

// ---------- Order details ----------

/// Bottom sheet with the items and money for one order. Pops with `true`
/// when she taps "Cancel order"; the screen then asks her to confirm.
class _OrderDetailsSheet extends StatelessWidget {
  final Order order;

  const _OrderDetailsSheet({required this.order});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(order);
    final customer = order.customerName;
    final phone = order.customerPhone;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.orderNumber,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  _statusLabel(order),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_formatTime(order.createdAt)),
            if (customer != null) Text('Customer: $customer'),
            if (phone != null) Text('Phone: $phone'),
            const Divider(height: 24),
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${item.quantity} × ${item.productName}'),
                    ),
                    Text('KES ${item.subtotal.toStringAsFixed(2)}'),
                  ],
                ),
              ),
            const Divider(height: 24),
            _moneyRow('Total', order.total, bold: true),
            if (!order.isCancelled || order.amountPaid > 0.005)
              _moneyRow('Paid', order.amountPaid),
            if (order.isOpen)
              _moneyRow('Balance due', order.balanceDue, color: Colors.red),
            if (order.isOpen) ...[
              Container(
                margin: const EdgeInsets.only(top: 16.0),
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: const Text(
                  'This sale is not fully paid, and its stock is being held. '
                  'If the customer did not pay, cancel the order to put the '
                  'stock back.',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Cancel order'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}