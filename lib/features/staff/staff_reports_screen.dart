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
  List<Map<String, dynamic>> _pushHistory = const [];
  String _historyFilter = 'all';

  static const Color _bg = Color(0xFFF7F4EF);
  static const Color _card = Colors.white;
  static const Color _line = Color(0xFFE8DED1);
  static const Color _gold = Color(0xFFB8860B);
  static const Color _goldSoft = Color(0xFFF6E8C8);
  static const Color _ink = Color(0xFF1F1A14);
  static const Color _muted = Color(0xFF6F665B);
  static const Color _greenSoft = Color(0xFFE7F7EC);
  static const Color _redSoft = Color(0xFFFDEBEC);
  static const Color _amberSoft = Color(0xFFFFF3D8);

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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: _gold,
                  surface: Colors.white,
                ),
          ),
          child: child!,
        );
      },
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

    final from = DateTime(_range.start.year, _range.start.month, _range.start.day);
    final to = DateTime(_range.end.year, _range.end.month, _range.end.day).add(const Duration(days: 1));

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

    try {
      final res = await _api.pushHistory(limit: 50, kind: _historyFilter == 'all' ? null : _historyFilter);
      final m = Map<String, dynamic>.from(res);
      final list = (m['items'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() => _pushHistory = list);
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
      _toast(_pushResultMessage(res, successLabel: 'Broadcast saved and sent', failLabel: 'Broadcast failed'));
      await _loadAll();
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
      _toast(_pushResultMessage(res, successLabel: 'Top $_pushTopN customers push sent', failLabel: 'Targeted push failed'));
      await _loadAll();
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
      _toast(_pushResultMessage(res, successLabel: 'Voucher push sent', failLabel: 'Voucher push failed'));
      await _loadAll();
    } catch (e) {
      _toast('Failed to send: $e');
    } finally {
      if (mounted) setState(() => _sendingPush = false);
    }
  }

  String _pushResultMessage(Map<String, dynamic> res, {required String successLabel, required String failLabel}) {
    final ok = (res['ok'] == true) || (res['success'] == true);
    final sent = res['sent'] ?? res['targetedPhones'] ?? res['target_count'];
    final successCount = res['successCount'] ?? res['success_count'];
    final failureCount = res['failureCount'] ?? res['failure_count'];
    final invalid = res['invalid'] ?? res['invalid_count'];
    final err = (res['error'] ?? '').toString().trim();

    if (ok) {
      final parts = <String>[successLabel];
      if (sent != null) parts.add('Targeted: $sent');
      if (successCount != null) parts.add('Delivered: $successCount');
      if (failureCount != null) parts.add('Failed: $failureCount');
      if (invalid != null && '$invalid' != '0') parts.add('Invalid: $invalid');
      return parts.join(' • ');
    }

    return err.isNotEmpty ? '$failLabel • $err' : failLabel;
  }

  String _fmtDateTime(dynamic v) {
    try {
      final dt = DateTime.parse((v ?? '').toString()).toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return (v ?? '').toString();
    }
  }

  String _fmtDisplayDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return raw;
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2F2B26),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fromStr = _date10(_range.start);
    final toStr = _date10(_range.end);

    return Scaffold(
      backgroundColor: _bg,
      body: RefreshIndicator(
        color: _gold,
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _headerCard(fromStr, toStr),
            const SizedBox(height: 14),
            if (_error != null) ...[
              _errorCard(),
              const SizedBox(height: 14),
            ],
            _sectionShell(
              title: 'Restaurant performance',
              icon: Icons.insights_rounded,
              subtitle: 'Quick view of orders, revenue, delivery and discounts for the selected range.',
              child: _kpiGrid(),
            ),
            const SizedBox(height: 16),
            _sectionShell(
              title: 'Top customers',
              icon: Icons.workspace_premium_rounded,
              subtitle: 'Best performing customers to target for campaigns, offers and re-engagement.',
              child: _topCustomersCard(),
            ),
            const SizedBox(height: 16),
            _sectionShell(
              title: 'Top items',
              icon: Icons.local_dining_rounded,
              subtitle: 'Best selling menu items ranked by quantity and revenue.',
              child: _topItemsCard(),
            ),
            const SizedBox(height: 16),
            _sectionShell(
              title: 'Orders by day',
              icon: Icons.calendar_view_week_rounded,
              subtitle: 'Daily performance breakdown for trend review.',
              child: _byDayCard(),
            ),
            const SizedBox(height: 16),
            _sectionShell(
              title: 'Voucher performance',
              icon: Icons.local_offer_rounded,
              subtitle: 'Track voucher usage and total discount impact.',
              child: _voucherPerfCard(),
            ),
            const SizedBox(height: 16),
            _sectionShell(
              title: 'Notification history',
              icon: Icons.notifications_active_rounded,
              subtitle: 'See what was sent, when it was sent and to whom.',
              child: _notificationHistoryCard(),
            ),
            if (_loading) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator(color: _gold)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _headerCard(String fromStr, String toStr) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F1A14), Color(0xFF3D2C15)],
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 24,
            offset: Offset(0, 14),
            color: Color(0x22000000),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reports Dashboard',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Restaurant analytics, vouchers, customers and campaign performance in one place.',
                      style: TextStyle(
                        color: Color(0xFFE9DEC6),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _headerAction(
                icon: Icons.calendar_month_rounded,
                label: '$fromStr  →  $toStr',
                onTap: _pickRange,
              ),
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
                child: _headerAction(
                  icon: Icons.download_rounded,
                  label: 'Export Reports',
                  onTap: null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerAction({required IconData icon, required String label, VoidCallback? onTap}) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: child);
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _redSoft,
        border: Border.all(color: Colors.red.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error ?? '',
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionShell({
    required String title,
    required IconData icon,
    required String subtitle,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _goldSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _line),
              ),
              child: Icon(icon, size: 20, color: _gold),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: _muted,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }

  Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            blurRadius: 22,
            offset: Offset(0, 10),
            color: Color(0x12000000),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _kpiGrid() {
    final orders = (_summary['orders_count'] ?? _summary['orders'] ?? 0).toString();
    final revenue = _money(_summary['total_aed'] ?? _summary['revenue_aed']);
    final subtotal = _money(_summary['subtotal_aed']);
    final delivery = _money(_summary['delivery_fee_aed']);
    final voucher = _money(_summary['voucher_discount_aed']);
    final loyalty = _money(_summary['loyalty_discount_aed']);

    return _panel(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _kpiTile(icon: Icons.receipt_long_rounded, label: 'Orders', value: orders)),
              const SizedBox(width: 12),
              Expanded(child: _kpiTile(icon: Icons.payments_rounded, label: 'Revenue (AED)', value: revenue)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _kpiTile(icon: Icons.shopping_bag_outlined, label: 'Subtotal', value: subtotal)),
              const SizedBox(width: 12),
              Expanded(child: _kpiTile(icon: Icons.delivery_dining_rounded, label: 'Delivery', value: delivery)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _kpiTile(icon: Icons.sell_outlined, label: 'Voucher Discount', value: voucher)),
              const SizedBox(width: 12),
              Expanded(child: _kpiTile(icon: Icons.card_giftcard_rounded, label: 'Loyalty Discount', value: loyalty)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiTile({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFCF8), Color(0xFFF7F1E8)],
        ),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _goldSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _gold),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              height: 1.1,
              fontWeight: FontWeight.w900,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _topCustomersCard() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_topCustomers.isEmpty)
            _emptyState('No customers for the selected range.')
          else ...[
            ...List.generate(_topCustomers.take(10).length, (index) {
              final c = _topCustomers[index];
              final phone = (c['phone'] ?? '').toString();
              final orders = (c['orders_count'] ?? 0).toString();
              final spent = _money(c['total_spent_aed'] ?? c['total_spent'] ?? c['total']);
              return _rankedRow(
                rank: index + 1,
                title: phone.isNotEmpty ? phone : 'Unknown customer',
                subtitle: 'Orders: $orders',
                trailing: 'AED $spent',
                icon: Icons.person_rounded,
              );
            }),
            const SizedBox(height: 8),
          ],
          const Divider(height: 26, color: _line),
          const Text(
            'Campaign center',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Send a broadcast, target your best customers, or push a voucher campaign without leaving reports.',
            style: TextStyle(color: _muted, height: 1.35),
          ),
          const SizedBox(height: 14),
          _campaignCard(
            title: 'Notification content',
            subtitle: 'This title and message will be used for broadcast, top customers and voucher push.',
            icon: Icons.edit_notifications_rounded,
            child: Column(
              children: [
                TextField(
                  controller: _pushTitleCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration('Title', Icons.title_rounded),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _pushBodyCtrl,
                  minLines: 3,
                  maxLines: 4,
                  decoration: _inputDecoration('Message', Icons.message_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _campaignCard(
            title: 'Target top customers',
            subtitle: 'Choose the top customers from this report and send them a campaign instantly.',
            icon: Icons.groups_2_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _goldSoft,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _line),
                      ),
                      child: DropdownButton<int>(
                        value: _pushTopN,
                        underline: const SizedBox.shrink(),
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
                    ),
                    const Spacer(),
                    if (_sendingPush)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _sendingPush ? null : _sendPushToTopCustomers,
                        icon: const Icon(Icons.people_alt_outlined),
                        label: const Text('Notify Top Customers'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          side: const BorderSide(color: _line),
                          foregroundColor: _ink,
                        ),
                        onPressed: _sendingPush ? null : _sendPushToAll,
                        icon: const Icon(Icons.campaign_outlined),
                        label: const Text('Notify All Customers'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _campaignCard(
            title: 'Voucher push',
            subtitle: 'Push a voucher code directly to customers using the same campaign message above.',
            icon: Icons.local_offer_outlined,
            child: Column(
              children: [
                TextField(
                  controller: _voucherCodeCtrl,
                  textInputAction: TextInputAction.done,
                  decoration: _inputDecoration('Voucher Code (e.g., WELCOME10)', Icons.confirmation_number_outlined),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3B2D1A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _sendingPush ? null : _pushVoucherByCode,
                    icon: const Icon(Icons.local_offer_outlined),
                    label: const Text('Push Voucher'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _campaignCard({required String title, required String subtitle, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _goldSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: _gold),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _muted),
      prefixIcon: Icon(icon, color: _gold),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _gold, width: 1.4),
      ),
      isDense: true,
    );
  }

  Widget _topItemsCard() {
    return _panel(
      child: _topItems.isEmpty
          ? _emptyState('No items for the selected range.')
          : Column(
              children: List.generate(_topItems.take(10).length, (index) {
                final it = _topItems[index];
                final name = (it['item_name'] ?? it['name'] ?? '').toString();
                final qty = (it['qty'] ?? it['quantity'] ?? 0).toString();
                final rev = _money(it['revenue_aed'] ?? it['revenue'] ?? it['total_aed']);
                return _rankedRow(
                  rank: index + 1,
                  title: name,
                  subtitle: 'Qty sold: $qty',
                  trailing: 'AED $rev',
                  icon: Icons.restaurant_menu_rounded,
                );
              }),
            ),
    );
  }

  Widget _byDayCard() {
    return _panel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: _byDay.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(4),
              child: _emptyState('No daily data for the selected range.'),
            )
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFCF8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _line),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        child: Text('Date', style: TextStyle(fontWeight: FontWeight.w900, color: _muted)),
                      ),
                      SizedBox(
                        width: 70,
                        child: Text('Orders', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, color: _muted)),
                      ),
                      SizedBox(width: 12),
                      SizedBox(
                        width: 100,
                        child: Text('Revenue', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, color: _muted)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ..._byDay.take(14).map((d) {
                  final day = (d['day'] ?? d['date'] ?? '').toString();
                  final orders = (d['orders_count'] ?? d['orders'] ?? 0).toString();
                  final total = _money(d['total_aed'] ?? d['revenue_aed']);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _line),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _fmtDisplayDate(day),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        SizedBox(
                          width: 70,
                          child: Text(orders, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 100,
                          child: Text('AED $total', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Widget _voucherPerfCard() {
    return _panel(
      child: _voucherPerf.isEmpty
          ? _emptyState('No voucher performance data for the selected range.')
          : Column(
              children: List.generate(_voucherPerf.take(12).length, (index) {
                final v = _voucherPerf[index];
                final code = (v['code'] ?? '').toString();
                final uses = (v['uses'] ?? v['uses_count'] ?? 0).toString();
                final disc = _money(v['discount_aed'] ?? v['voucher_discount_aed'] ?? v['amount']);
                return Container(
                  margin: EdgeInsets.only(bottom: index == _voucherPerf.take(12).length - 1 ? 0 : 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFCF8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _line),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _goldSoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Voucher',
                          style: TextStyle(fontWeight: FontWeight.w800, color: _gold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(code.isEmpty ? '—' : code, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                            const SizedBox(height: 3),
                            Text('Uses: $uses', style: const TextStyle(color: _muted, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      Text('AED $disc', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    ],
                  ),
                );
              }),
            ),
    );
  }

  Widget _notificationHistoryCard() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent sends',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _goldSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _line),
                ),
                child: DropdownButton<String>(
                  value: _historyFilter,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'broadcast', child: Text('Broadcast')),
                    DropdownMenuItem(value: 'customers', child: Text('Selected')),
                    DropdownMenuItem(value: 'voucher', child: Text('Voucher')),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => _historyFilter = v);
                    await _loadAll();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_pushHistory.isEmpty)
            _emptyState('No notification history yet.')
          else
            ..._pushHistory.take(20).map((h) {
              final kind = (h['kind'] ?? 'broadcast').toString();
              final title = (h['title'] ?? '').toString();
              final message = (h['message'] ?? '').toString();
              final voucher = (h['voucher_code'] ?? '').toString();
              final status = (h['status'] ?? '').toString();
              final targetMode = (h['target_mode'] ?? '').toString();
              final targetCount = (h['target_count'] ?? 0).toString();
              final successCount = (h['success_count'] ?? 0).toString();
              final failureCount = (h['failure_count'] ?? 0).toString();
              final invalidCount = (h['invalid_count'] ?? 0).toString();
              final error = (h['error'] ?? '').toString();
              final preview = (h['target_preview'] is List)
                  ? (h['target_preview'] as List).map((e) => e.toString()).toList()
                  : const <String>[];

              Color chipColor;
              Color chipBg;
              if (status == 'sent') {
                chipColor = Colors.green;
                chipBg = _greenSoft;
              } else if (status == 'failed') {
                chipColor = Colors.red;
                chipBg = _redSoft;
              } else {
                chipColor = Colors.orange;
                chipBg = _amberSoft;
              }

              return Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: const Color(0xFFFFFCF8),
                  border: Border.all(color: _line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: chipBg,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: chipColor.withOpacity(0.18)),
                          ),
                          child: Text(
                            '${kind.toUpperCase()} • ${status.toUpperCase()}',
                            style: TextStyle(
                              color: chipColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _fmtDateTime(h['created_at']),
                          style: const TextStyle(color: _muted, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    if (title.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                    ],
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(message, style: const TextStyle(height: 1.35)),
                    ],
                    if (voucher.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: _goldSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('Voucher code: $voucher', style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _metricPill('Target', targetMode.isEmpty ? '—' : targetMode),
                        _metricPill('Count', targetCount),
                        _metricPill('Delivered', successCount),
                        _metricPill('Failed', failureCount),
                        _metricPill('Invalid', invalidCount),
                      ],
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'To: ${preview.join(', ')}',
                        style: const TextStyle(color: _muted, height: 1.35),
                      ),
                    ],
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Error: $error', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _metricPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _line),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontWeight: FontWeight.w700, color: _ink),
      ),
    );
  }

  Widget _rankedRow({
    required int rank,
    required String title,
    required String subtitle,
    required String trailing,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _goldSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '#$rank',
              style: const TextStyle(fontWeight: FontWeight.w900, color: _gold),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _line),
            ),
            child: Icon(icon, color: _gold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? '—' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(color: _muted, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(trailing, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _emptyState(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Text(
        text,
        style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
      ),
    );
  }
}
