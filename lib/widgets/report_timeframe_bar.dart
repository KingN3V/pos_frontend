import 'package:flutter/material.dart';

enum ReportPeriod { today, week, month, custom }

/// What a report screen needs to build its request: either a named period
/// ('today', 'week', 'month') or an explicit start/end date range.
class ReportTimeframe {
  final ReportPeriod period;
  final DateTimeRange? customRange;

  const ReportTimeframe({required this.period, this.customRange});

  /// Query-param-ready values. For a named period, [period] is set and
  /// [startDate]/[endDate] are null. For a custom range, the reverse.
  String? get periodParam =>
      period == ReportPeriod.custom ? null : period.name;

  DateTime? get startDate =>
      period == ReportPeriod.custom ? customRange?.start : null;

  DateTime? get endDate =>
      period == ReportPeriod.custom ? customRange?.end : null;

  String get label {
    switch (period) {
      case ReportPeriod.today:
        return 'Today';
      case ReportPeriod.week:
        return 'This week';
      case ReportPeriod.month:
        return 'This month';
      case ReportPeriod.custom:
        if (customRange == null) return 'Custom';
        final s = customRange!.start;
        final e = customRange!.end;
        String d(DateTime t) => '${t.day}/${t.month}/${t.year}';
        return '${d(s)} – ${d(e)}';
    }
  }
}

/// Timeframe chips (Today/Week/Month/Custom) plus a download button, shared
/// across the report screens. The parent owns the selected timeframe and
/// export handling; this widget just presents the controls.
class ReportTimeframeBar extends StatelessWidget {
  final ReportTimeframe timeframe;
  final ValueChanged<ReportTimeframe> onChanged;

  /// Called with 'csv' or 'excel' when the download button is tapped.
  /// Null hides the download button (e.g. while a request is in flight).
  final ValueChanged<String>? onDownload;

  const ReportTimeframeBar({
    super.key,
    required this.timeframe,
    required this.onChanged,
    this.onDownload,
  });

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: timeframe.customRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
    );

    if (range != null) {
      onChanged(ReportTimeframe(period: ReportPeriod.custom, customRange: range));
    }
  }

  Future<void> _showDownloadOptions(BuildContext context) async {
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
      onDownload?.call(format);
    }
  }

  Widget _chip(BuildContext context, String label, ReportPeriod period) {
    final selected = timeframe.period == period;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        if (period == ReportPeriod.custom) {
          _pickCustomRange(context);
        } else {
          onChanged(ReportTimeframe(period: period));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip(context, 'Today', ReportPeriod.today),
                  const SizedBox(width: 8),
                  _chip(context, 'Week', ReportPeriod.week),
                  const SizedBox(width: 8),
                  _chip(context, 'Month', ReportPeriod.month),
                  const SizedBox(width: 8),
                  _chip(
                    context,
                    timeframe.period == ReportPeriod.custom
                        ? timeframe.label
                        : 'Custom',
                    ReportPeriod.custom,
                  ),
                ],
              ),
            ),
          ),
          if (onDownload != null)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Download',
              onPressed: () => _showDownloadOptions(context),
            ),
        ],
      ),
    );
  }
}