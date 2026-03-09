// lib/features/staff/staff_reports_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import 'staff_api.dart';

double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  if (s.isEmpty) return 0.0;
  return double.tryParse(s) ?? 0.0;
}

String _money(dynamic v) => _toDouble(v).toStringAsFixed(2);

class StaffReportsScreen extends StatefulWidget {
  const StaffReportsScreen({super.key});

  @override
  State<StaffReportsScreen> createState() => _StaffReportsScreenState();
}

class _StaffReportsScreenState extends State<StaffReportsScreen> {
  final StaffApi _api = StaffApi();

  // Push notifications (admin/staff marketing)
  final TextEditingController _pushTitleCtrl = TextEditingController();
  final TextEditingController _pushBodyCtrl = TextEditingController();
  final TextEditingController _voucherCodeCtrl = TextEditingController();

  bool _sendingPush = false;
  int _pushTopN = 10;


  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  bool _loading = true;
  String? _error;

  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _topCustomers = const [];
  List<Map<String, dynamic>> _topItems = const [];
  List<Map<String, dynamic>> _byDay = const [];
  List<Map<String, dynamic>> _voucherPerf = const [];

  String _date10(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _pushTitleCtrl.dispose();
    _pushBodyCtrl.dispose();
    _voucherCodeCtrl.dispose();
    super.dispose();
  }


  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() => _range = picked);
    await _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // to is exclusive on backend → include end date by adding +1 day
    final from = DateTime(_range.start.year, _range.start.month, _range.start.day);
    final to = DateTime(_range.end.year, _range.end.month, _range.end.day).add(const Duration(days: 1));

    // 1) Always load summary first (so KPI cards never show 0 because another section failed)
    try {
      final res = await _api.reportsOrdersSummary(from: from, to: to);
      final m = Map<String, dynamic>.from(res);
      final summary = (m['summary'] is Map) ? Map<String, dynamic>.from(m['summary']) : m;
      setState(() => _summary = summary);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Restaurant performance: Failed to generate report';
      });
      return;
    }

    // 2) Load the rest independently (non-fatal)
    try {
      final res = await _api.reportsTopCustomers(from: from, to: to, limit: 25);
      final m = Map<String, dynamic>.from(res);
      final list = (m['customers'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() => _topCustomers = list);
    } catch (e) {
      setState(() => _error = 'Top customers: Failed to generate report');
    }

    try {
      final res = await _api.reportsTopItems(from: from, to: to, limit: 25);
      final m = Map<String, dynamic>.from(res);
      final list = (m['items'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() => _topItems = list);
    } catch (e) {
      // Keep summary visible
      setState(() => _error ??= 'Top items: Failed to generate report');
    }

    try {
      final res = await _api.reportsOrdersByDay(from: from, to: to);
      final m = Map<String, dynamic>.from(res);
      final list = (m['days'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() => _byDay = list);
    } catch (_) {}

    try {
      final res = await _api.reportsVoucherPerformance(from: from, to: to);
      final m = Map<String, dynamic>.from(res);
      final list = (m['items'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() => _voucherPerf = list);
    } catch (_) {}

    setState(() => _loading = false);
  }

  Future<void> _exportSummary() async {
    final from = DateTime(_range.start.year, _range.start.month, _range.start.day);
    final to = DateTime(_range.end.year, _range.end.month, _range.end.day).add(const Duration(days: 1));
    final bytes = await _api.exportSummaryXlsx(from: from, to: to);
    await _shareBytes(bytes, 'handi_roti_summary_${_date10(from)}_${_date10(to)}.xlsx');
  }

  Future<void> _exportTopItems() async {
    final from = DateTime(_range.start.year, _range.start.month, _range.start.day);
    final to = DateTime(_range.end.year, _range.end.month, _range.end.day).add(const Duration(days: 1));
    final bytes = await _api.exportTopItemsXlsx(from: from, to: to, limit: 200);
    await _shareBytes(bytes, 'handi_roti_top_items_${_date10(from)}_${_date10(to)}.xlsx');
  }

  Future<void> _exportVouchers() async {
    final from = DateTime(_range.start.year, _range.start.month, _range.start.day);
    final to = DateTime(_range.end.year, _range.end.month, _range.end.day).add(const Duration(days: 1));
    final bytes = await _api.exportVouchersXlsx(from: from, to: to);
    await _shareBytes(bytes, 'handi_roti_vouchers_${_date10(from)}_${_date10(to)}.xlsx');
  }

  Future<void> _shareBytes(List<int> bytes, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'Handi Roti report export');
  }


  String? _customerKey(Map<String, dynamic> c) {
    const candidates = <String>[
      'customerKey',
      'customer_key',
      'customerId',
      'customer_id',
      'id',
      'phone',
    ];
    for (final k in candidates) {
      final v = c[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  Future<void> _sendPushToAll() async {
    final title = _pushTitleCtrl.text.trim();
    final body = _pushBodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _toast('Please enter both title and message.');
      return;
    }
    setState(() => _sendingPush = true);
    try {
      final res = await _api.pushSendAll(title: title, body: body);
      final ok = (res['ok'] == true) || (res['success'] == true);
      _toast(ok ? 'Notification sent to all customers.' : 'Failed to send. ${res['error'] ?? ''}'.trim());
    } catch (e) {
      _toast('Failed to send: $e');
    } finally {
      if (mounted) setState(() => _sendingPush = false);
    }
  }

  Future<void> _sendPushToTopCustomers() async {
    final title = _pushTitleCtrl.text.trim();
    final body = _pushBodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _toast('Please enter both title and message.');
      return;
    }
    final keys = _topCustomers
        .take(_pushTopN)
        .map((c) => _customerKey(c))
        .whereType<String>()
        .toSet()
        .toList();
    if (keys.isEmpty) {
      _toast('No customer targets found in the report.');
      return;
    }

    setState(() => _sendingPush = true);
    try {
      final res = await _api.pushSendCustomers(title: title, body: body, customerKeys: keys);
      final ok = (res['ok'] == true) || (res['success'] == true);
      _toast(ok ? 'Notification sent to top $_pushTopN customers.' : 'Failed to send. ${res['error'] ?? ''}'.trim());
    } catch (e) {
      _toast('Failed to send: $e');
    } finally {
      if (mounted) setState(() => _sendingPush = false);
    }
  }

  Future<void> _pushVoucherByCode() async {
    final code = _voucherCodeCtrl.text.trim();
    if (code.isEmpty) {
      _toast('Enter a voucher code.');
      return;
    }
    final title = _pushTitleCtrl.text.trim().isEmpty ? null : _pushTitleCtrl.text.trim();
    final body = _pushBodyCtrl.text.trim().isEmpty ? null : _pushBodyCtrl.text.trim();

    setState(() => _sendingPush = true);
    try {
      final res = await _api.pushVoucherByCode(code: code, title: title, body: body);
      final ok = (res['ok'] == true) || (res['success'] == true);
      _toast(ok ? 'Voucher push sent.' : 'Failed to send. ${res['error'] ?? ''}'.trim());
    } catch (e) {
      _toast('Failed to send: $e');
    } finally {
      if (mounted) setState(() => _sendingPush = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }


  @override
  Widget build(BuildContext context) {
    final fromStr = _date10(_range.start);
    final toStr = _date10(_range.end);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Reports', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                ),
                InkWell(
                  onTap: _pickRange,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month, size: 18),
                        const SizedBox(width: 8),
                        Text('$fromStr  →  $toStr', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'summary') _exportSummary();
                    if (v == 'top_items') _exportTopItems();
                    if (v == 'vouchers') _exportVouchers();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'summary', child: Text('Export Summary (Excel)')),
                    PopupMenuItem(value: 'top_items', child: Text('Export Top Items (Excel)')),
                    PopupMenuItem(value: 'vouchers', child: Text('Export Vouchers (Excel)')),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(Icons.download),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.red.withOpacity(0.08),
                  border: Border.all(color: Colors.red.withOpacity(0.25)),
                ),
                child: Text('Exception: $_error', style: const TextStyle(color: Colors.red)),
              ),
              const SizedBox(height: 12),
            ],

            _sectionTitle('Restaurant performance'),
            const SizedBox(height: 10),
            _kpiGrid(),

            const SizedBox(height: 18),
            _sectionTitle('Top customers (target vouchers)'),
            const SizedBox(height: 10),
            _topCustomersCard(),

            const SizedBox(height: 18),
            _sectionTitle('Top items'),
            const SizedBox(height: 10),
            _topItemsCard(),

            const SizedBox(height: 18),
            _sectionTitle('Orders by day'),
            const SizedBox(height: 10),
            _byDayCard(),

            const SizedBox(height: 18),
            _sectionTitle('Voucher performance'),
            const SizedBox(height: 10),
            _voucherPerfCard(),

            if (_loading) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Row(
        children: [
          const Icon(Icons.insights_rounded, size: 18),
          const SizedBox(width: 8),
          Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        ],
      );

  Widget _kpiGrid() {
    final orders = (_summary['orders_count'] ?? _summary['orders'] ?? 0).toString();
    final revenue = _money(_summary['total_aed'] ?? _summary['revenue_aed']);
    final subtotal = _money(_summary['subtotal_aed']);
    final delivery = _money(_summary['delivery_fee_aed']);
    final voucher = _money(_summary['voucher_discount_aed']);
    final loyalty = _money(_summary['loyalty_discount_aed']);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFBF7F3), Color(0xFFF4EEE8)],
        ),
        border: Border.all(color: const Color(0xFFE7DED6)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 12),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _kpi('Orders', orders)),
              const SizedBox(width: 10),
              Expanded(child: _kpi('Revenue (AED)', revenue)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _kpi('Subtotal', subtotal)),
              const SizedBox(width: 10),
              Expanded(child: _kpi('Delivery', delivery)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _kpi('Voucher Disc', voucher)),
              const SizedBox(width: 10),
              Expanded(child: _kpi('Loyalty Disc', loyalty)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE7DED6)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            offset: Offset(0, 10),
            color: Color(0x12000000),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.black.withOpacity(0.60),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _topCustomersCard() {
    if (_topCustomers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE7DED6)),
      ),
        child: const Text('No customers for the selected range.'),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE7DED6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._topCustomers.take(10).map((c) {
            final phone = (c['phone'] ?? '').toString();
            final orders = (c['orders_count'] ?? 0).toString();
            final spent = _money(c['total_spent_aed'] ?? c['total_spent'] ?? c['total']);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      phone.isNotEmpty ? phone : 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text('Orders: $orders  •  AED $spent'),
                ],
              ),
            );
          }).toList(),
          const Divider(height: 26),
          const Text('Send Notification', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            controller: _pushTitleCtrl,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pushBodyCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Message',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Target:'),
              const SizedBox(width: 10),
              DropdownButton<int>(
                value: _pushTopN,
                items: const [
                  DropdownMenuItem(value: 5, child: Text('Top 5')),
                  DropdownMenuItem(value: 10, child: Text('Top 10')),
                  DropdownMenuItem(value: 15, child: Text('Top 15')),
                  DropdownMenuItem(value: 25, child: Text('Top 25')),
                ],
                onChanged: _sendingPush
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() => _pushTopN = v);
                      },
              ),
              const Spacer(),
              if (_sendingPush) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _sendingPush ? null : _sendPushToTopCustomers,
                  icon: const Icon(Icons.people_alt_outlined),
                  label: const Text('Notify Top'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _sendingPush ? null : _sendPushToAll,
                  icon: const Icon(Icons.campaign_outlined),
                  label: const Text('Notify All'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Voucher Push', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            controller: _voucherCodeCtrl,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Voucher Code (e.g., WELCOME10)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _sendingPush ? null : _pushVoucherByCode,
            icon: const Icon(Icons.local_offer_outlined),
            label: const Text('Push Voucher'),
          ),
        ],
      ),
    );
  }

  Widget _topItemsCard() {
    if (_topItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE7DED6)),
      ),
        child: const Text('No items for the selected range.'),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE7DED6)),
      ),
      child: Column(
        children: _topItems.take(10).map((it) {
          final name = (it['item_name'] ?? it['name'] ?? '').toString();
          final qty = (it['qty'] ?? it['quantity'] ?? 0).toString();
          final rev = _money(it['revenue_aed'] ?? it['revenue'] ?? it['total_aed']);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('Qty: $qty  •  AED $rev'),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _byDayCard() {
    if (_byDay.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE7DED6)),
      ),
        child: const Text('No daily data for the selected range.'),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE7DED6)),
      ),
      child: Column(
        children: _byDay.take(14).map((d) {
          final day = (d['day'] ?? d['date'] ?? '').toString();
          final orders = (d['orders_count'] ?? d['orders'] ?? 0).toString();
          final total = _money(d['total_aed'] ?? d['revenue_aed']);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: Text(day, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('Orders: $orders  •  AED $total'),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _voucherPerfCard() {
    if (_voucherPerf.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE7DED6)),
      ),
        child: const Text('No voucher performance data for the selected range.'),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE7DED6)),
      ),
      child: Column(
        children: _voucherPerf.take(12).map((v) {
          final code = (v['code'] ?? '').toString();
          final uses = (v['uses'] ?? v['uses_count'] ?? 0).toString();
          final disc = _money(v['discount_aed'] ?? v['voucher_discount_aed'] ?? v['amount']);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: Text(code, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('Uses: $uses  •  AED $disc'),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
