import 'package:flutter/material.dart';
import 'sales_summary_screen.dart';
import 'top_products_screen.dart';
import 'low_stock_screen.dart';
import 'outstanding_balances_screen.dart';

class ReportsMenuScreen extends StatelessWidget {
  const ReportsMenuScreen({super.key});

  Widget _buildTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? destination,
  }) {
    final enabled = destination != null;

    return Card(
      child: ListTile(
        leading: Icon(icon, color: enabled ? null : Colors.grey.shade400),
        title: Text(
          title,
          style: enabled ? null : TextStyle(color: Colors.grey.shade400),
        ),
        subtitle: Text(
          enabled ? subtitle : 'Coming soon',
          style: enabled ? null : TextStyle(color: Colors.grey.shade400),
        ),
        trailing: enabled
            ? const Icon(Icons.chevron_right)
            : Icon(Icons.chevron_right, color: Colors.grey.shade300),
        onTap: enabled
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => destination),
                );
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildTile(
            context: context,
            icon: Icons.summarize_outlined,
            title: 'Sales Summary',
            subtitle: 'Revenue, profit and orders for a period',
            destination: const SalesSummaryScreen(),
          ),
          _buildTile(
            context: context,
            icon: Icons.emoji_events_outlined,
            title: 'Top Products',
            subtitle: 'Best sellers for a period',
            destination: const TopProductsScreen(),
          ),
           _buildTile(
            context: context,
            icon: Icons.warning_amber_outlined,
            title: 'Low Stock',
            subtitle: 'Products running low',
            destination: const LowStockScreen(),
          ),
            _buildTile(
            context: context,
            icon: Icons.receipt_long_outlined,
            title: 'Outstanding Balances',
            subtitle: 'See and collect what customers owe',
            destination: const OutstandingBalancesScreen(),
          ),
        ],
      ),
    );
  }
}