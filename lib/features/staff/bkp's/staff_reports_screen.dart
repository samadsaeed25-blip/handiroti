// lib/features/staff/staff_reports_screen.dart
import 'package:flutter/material.dart';

import 'staff_api.dart';
import 'dart:convert';

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

  // ---- Safe JSON casting helpers (backend can return strings or loosely-typed lists) ----
  String _date10(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  void _assertOk(dynamic res, String label) {
    final m = _safeMap(res);
    if (m.isNotEmpty && m['ok'] == false) {
      throw Exception('$label: ${m['error'] ?? 'failed'}');
    }
  }

  Map<String, dynamic> _safeMap(dynamic v) {
    if (v == null) return <String, dynamic>{};
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val));
    }
    if (v is String) {
      try {
        final decoded = jsonDecode(v);
        return _safeMap(decoded);
      } catch (_) {
        return <String, dynamic>{'_raw': v};
      }
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _safeMapList(dynamic v) {
    if (v == null) return <Map<String, dynamic>>[];
    if (v is String) {
      try {
        final decoded = jsonDecode(v);
        return _safeMapList(decoded);
      } catch (_) {
        return <Map<String, dynamic>>[];
      }
    }
    if (v is List) {
      final out = <Map<String, dynamic>>[];
      for (final e in v) {
        final m = _safeMap(e);
        if (m.isNotEmpty) out.add(m);
      }
      return out;
    }
    return <Map<String, dynamic>>[];
  }

  num _safeNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  final _api = StaffApi();

  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  bool _loading = false;
  String? _error;

  Map<String, dynamic>? _ordersSummary;
  List<Map<String, dynamic>> _topCustomers = const [];
  Map<String, dynamic>? _vouchersSummary;
  List<Map<String, dynamic>> _vouchersByCode = const [];
  List<Map<String, dynamic>> _campaigns = const [];

  // selection for targeted allowlist
  final Set<String> _selectedCustomerPhones = <String>{};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() => _range = picked);
    await _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      final from = _date10(_range.start);
      final to = _date10(_range.end);
    });
    try {
      // Back-end treats `to` as an exclusive upper bound. If we send a date-only
      // (or midnight) value, the entire end-day can get excluded.
      // Send (end date + 1 day) at midnight so the selected end-day is included.
      final from = DateTime(_range.start.year, _range.start.month, _range.start.day);
      final to = DateTime(_range.end.year, _range.end.month, _range.end.day).add(const Duration(days: 1));

      final orders = await _api.reportsOrdersSummary(from: from, to: to);
      final top = await _api.reportsTopCustomers(from: from, to: to, limit: 25);
      final vs = await _api.reportsVouchersSummary(from: from, to: to);
      final vb = await _api.reportsVouchersByCode(from: from, to: to, limit: 50);
      final camp = await _api.reportsCampaigns(from: from, to: to);

      _assertOk(orders, 'Orders summary');
      _assertOk(top, 'Top customers');
      _assertOk(vs, 'Vouchers summary');
      _assertOk(vb, 'Vouchers by code');
      _assertOk(camp, 'Campaigns');

      setState(() {
        _ordersSummary = _safeMap(orders['summary'] ?? orders);
        _topCustomers = _safeMapList(top['customers'] ?? top['items'] ?? top['rows'] ?? top);
        _vouchersSummary = _safeMap(vs['summary'] ?? vs);
        _vouchersByCode = _safeMapList(vb['items'] ?? vb['vouchers'] ?? vb['rows'] ?? vb);
        _campaigns = _safeMapList(camp['campaigns'] ?? camp['items'] ?? camp['rows'] ?? camp);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assignExistingVoucherToSelected() async {
    if (_selectedCustomerPhones.isEmpty) {
      _snack('Select at least 1 customer');
      return;
    }

    // fetch vouchers list for dropdown
    List<Map<String, dynamic>> vouchers = const [];
    try {
      vouchers = await _api.listVouchers();
    } catch (e) {
      _snack('Failed to load vouchers: $e');
      return;
    }

    if (!mounted) return;

    String? pickedVoucherId;
    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Assign existing voucher'),
          content: StatefulBuilder(
            builder: (ctx, setStateDialog) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: pickedVoucherId,
                    decoration: const InputDecoration(
                      labelText: 'Voucher',
                      border: OutlineInputBorder(),
                    ),
                    items: vouchers.map((v) {
                      final id = (v['id'] ?? v['voucher_id'] ?? '').toString();
                      final code = (v['code'] ?? '').toString();
                      return DropdownMenuItem(
                        value: id,
                        child: Text(code.isNotEmpty ? '$code  •  ${id.substring(0, id.length.clamp(0, 8))}…' : id),
                      );
                    }).toList(),
                    onChanged: (val) => setStateDialog(() => pickedVoucherId = val),
                  ),
                  const SizedBox(height: 10),
                  Text('Selected customers: ${_selectedCustomerPhones.length}'),
                ],
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (pickedVoucherId == null || pickedVoucherId!.trim().isEmpty) {
                  _snack('Pick a voucher');
                  return;
                }
                Navigator.pop(context);
                await _applyAllowlist(pickedVoucherId!, _selectedCustomerPhones.toList());
              },
              child: const Text('Assign'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createVoucherAndAssignToSelected() async {
    if (_selectedCustomerPhones.isEmpty) {
      _snack('Select at least 1 customer');
      return;
    }

    final codeC = TextEditingController(text: 'VIP${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}');
    final amountC = TextEditingController(text: '10');
    String kind = 'flat';
    final minSubtotalC = TextEditingController(text: '0');
    final maxDiscountC = TextEditingController(text: '');
    final daysValidC = TextEditingController(text: '14');

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Create voucher + assign to selected'),
          content: StatefulBuilder(
            builder: (ctx, setStateDialog) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: codeC,
                      decoration: const InputDecoration(
                        labelText: 'Code (unique)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: kind,
                      decoration: const InputDecoration(
                        labelText: 'Kind',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'flat', child: Text('Flat (AED)')),
                        DropdownMenuItem(value: 'percent', child: Text('Percent (%)')),
                      ],
                      onChanged: (v) => setStateDialog(() => kind = v ?? 'flat'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: amountC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: minSubtotalC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Min Subtotal (AED)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: maxDiscountC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Max Discount (AED) (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: daysValidC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Valid for (days)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Selected customers: ${_selectedCustomerPhones.length}'),
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);

                final code = codeC.text.trim();
                final amount = num.tryParse(amountC.text.trim()) ?? 0;
                final minSubtotal = num.tryParse(minSubtotalC.text.trim()) ?? 0;
                final maxDiscTxt = maxDiscountC.text.trim();
                final maxDisc = maxDiscTxt.isEmpty ? null : (num.tryParse(maxDiscTxt) ?? 0);
                final daysValid = int.tryParse(daysValidC.text.trim()) ?? 14;

                if (code.isEmpty || amount <= 0) {
                  _snack('Invalid code/amount');
                  return;
                }

                try {
                  final now = DateTime.now().toUtc();
                  final voucher = await _api.createVoucher(
                    code: code,
                    kind: kind,
                    amount: amount,
                    minSubtotalAed: minSubtotal,
                    maxDiscountAed: maxDisc,
                    maxUsesPerCustomer: 1,
                    maxUsesTotal: null,
                    startsAt: now,
                    endsAt: now.add(Duration(days: daysValid)),
                    isActive: true,
                  );

                  final voucherId = (voucher['id'] ?? voucher['voucher_id'] ?? '').toString();
                  if (voucherId.isEmpty) {
                    _snack('Voucher created but missing id in response');
                    return;
                  }

                  await _applyAllowlist(voucherId, _selectedCustomerPhones.toList());
                  await _loadAll();
                } catch (e) {
                  _snack('Create/assign failed: $e');
                }
              },
              child: const Text('Create & Assign'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _applyAllowlist(String voucherId, List<String> phones) async {
    setState(() => _loading = true);
    try {
      final res = await _api.addVoucherAllowlist(voucherId: voucherId, customerKeys: phones);
      final added = (res['added'] ?? '').toString();
      _snack('Assigned voucher to ${phones.length} customer(s). Added: $added');
      setState(() => _selectedCustomerPhones.clear());
    } catch (e) {
      _snack('Allowlist failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadAll,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Reports',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickRange,
                      icon: const Icon(Icons.date_range),
                      label: Text('${_range.start.toString().substring(0, 10)} → ${_range.end.toString().substring(0, 10)}'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.2)),
                    ),
                    child: Text(_error!, style: TextStyle(color: Colors.red.shade800)),
                  ),

                const SizedBox(height: 8),
                _OrdersSummaryCard(summary: _ordersSummary),
                const SizedBox(height: 12),

                _TopCustomersCard(
                  customers: _topCustomers,
                  selectedPhones: _selectedCustomerPhones,
                  onToggleSelect: (phone, sel) {
                    setState(() {
                      if (sel) {
                        _selectedCustomerPhones.add(phone);
                      } else {
                        _selectedCustomerPhones.remove(phone);
                      }
                    });
                  },
                  onAssignExisting: _assignExistingVoucherToSelected,
                  onCreateAndAssign: _createVoucherAndAssignToSelected,
                ),
                const SizedBox(height: 12),
                _PushPanelCard(
                  selectedCount: _selectedCustomerPhones.length,
                  isBusy: _loading,
                  onSelectCustomers: _openCustomerSelector,
                  onVoucherByCode: _pushVoucherByCodeDialog,
                  onCustomAll: _pushCustomAllDialog,
                  onCustomSelected: _pushCustomSelectedDialog,
                ),


                const SizedBox(height: 12),
                _VoucherSummaryCard(summary: _vouchersSummary),
                const SizedBox(height: 12),

                _VoucherByCodeCard(items: _vouchersByCode),
                const SizedBox(height: 12),

                _CampaignsCard(items: _campaigns),
              ],
            ),
          ),
          if (_loading)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: false,
                child: Container(
                  color: Colors.black.withOpacity(0.05),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }


  // --- Push + customer selector helpers (Reports only) ---

  String _safeDate10(dynamic v) {
    final s = (v ?? '').toString();
    if (s.isEmpty) return '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }


  Future<void> _openCustomerSelector() async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return _CustomerPickerSheet(
          api: _api,
          initialSelected: _selectedCustomerPhones,
          currentRange: _range,
        );
      },
    );

    if (picked == null) return;
    setState(() {
      _selectedCustomerPhones
        ..clear()
        ..addAll(picked);
    });
  }

  Future<void> _pushVoucherByCodeDialog() async {
    final TextEditingController codeCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send voucher push (by code)'),
        content: TextField(
          controller: codeCtrl,
          decoration: const InputDecoration(
            labelText: 'Voucher code',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );

    if (ok != true) return;
    final code = codeCtrl.text.trim();
    if (code.isEmpty) { _snack('Please enter a voucher code.'); return; }

    try {
      setState(() => _loading = true);
      await _api.pushVoucherByCode(code: code);
      _snack('Push sent for voucher: $code');
    } catch (e) {
      _snack('Failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pushCustomAllDialog() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom push to ALL customers'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: bodyCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );

    if (ok != true) return;
    final title = titleCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) { _snack('Please fill title and message.'); return; }

    try {
      setState(() => _loading = true);
      await _api.pushSendAll(title: title, body: body);
      _snack('Push sent to all customers.');
    } catch (e) {
      _snack('Failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pushCustomSelectedDialog() async {
    if (_selectedCustomerPhones.isEmpty) {
      _snack('Please select customers first.');
      return;
    }

    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Custom push to selected (${_selectedCustomerPhones.length})'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: bodyCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );

    if (ok != true) return;
    final title = titleCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) { _snack('Please fill title and message.'); return; }

    try {
      setState(() => _loading = true);
      await _api.pushSendCustomers(
        title: title,
        body: body,
        customerKeys: _selectedCustomerPhones.toList(),
      );
      _snack('Push sent to selected customers.');
    } catch (e) {
      _snack('Failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}


class _PushPanelCard extends StatelessWidget {
  final int selectedCount;
  final bool isBusy;
  final VoidCallback onSelectCustomers;
  final Future<void> Function() onVoucherByCode;
  final Future<void> Function() onCustomAll;
  final Future<void> Function() onCustomSelected;

  const _PushPanelCard({
    required this.selectedCount,
    required this.isBusy,
    required this.onSelectCustomers,
    required this.onVoucherByCode,
    required this.onCustomAll,
    required this.onCustomSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notifications',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              selectedCount == 0 ? 'No customers selected.' : 'Selected customers: $selectedCount',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: isBusy ? null : onSelectCustomers,
                  icon: const Icon(Icons.people_alt_outlined),
                  label: const Text('Select customers'),
                ),
                OutlinedButton.icon(
                  onPressed: isBusy ? null : () => onVoucherByCode(),
                  icon: const Icon(Icons.local_offer_outlined),
                  label: const Text('Voucher by code'),
                ),
                OutlinedButton.icon(
                  onPressed: isBusy ? null : () => onCustomAll(),
                  icon: const Icon(Icons.campaign_outlined),
                  label: const Text('Custom to ALL'),
                ),
                OutlinedButton.icon(
                  onPressed: (isBusy || selectedCount == 0) ? null : () => onCustomSelected(),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Custom to selected'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerPickerSheet extends StatefulWidget {
  final StaffApi api;
  final Set<String> initialSelected;
  final DateTimeRange currentRange;

  const _CustomerPickerSheet({
    required this.api,
    required this.initialSelected,
    required this.currentRange,
  });

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  late Set<String> _selected;
  String _query = '';
  bool _loading = false;
  String? _error;

  // 0 = use current range; others are presets.
  int _presetIndex = 0;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];

  static const List<_Preset> _presets = <_Preset>[
    _Preset('In range', null, null),
    _Preset('Last 5d', 5, null),
    _Preset('Last 7d', 7, null),
    _Preset('Last 15d', 15, null),
    _Preset('Last 30d', 30, null),
    _Preset('3 months', null, 3),
    _Preset('6 months', null, 6),
    _Preset('12 months', null, 12),
  ];

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelected);
    _fetch();
  }

  DateTimeRange _rangeForPreset() {
    final now = DateTime.now();
    final p = _presets[_presetIndex];
    if (p.days != null) {
      return DateTimeRange(start: now.subtract(Duration(days: p.days!)), end: now);
    }
    if (p.months != null) {
      final start = DateTime(now.year, now.month - p.months!, now.day);
      return DateTimeRange(start: start, end: now);
    }
    return widget.currentRange;
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = _rangeForPreset();
      final from = DateTime(r.start.year, r.start.month, r.start.day);
      final to = DateTime(r.end.year, r.end.month, r.end.day).add(const Duration(days: 1));

      final top = await widget.api.reportsTopCustomers(from: from, to: to, limit: 250);
      final list = ((top['customers'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Sort by orders_count desc (fallback to 0), then total_aed desc.
      list.sort((a, b) {
        final ao = (a['orders_count'] ?? a['orders'] ?? 0);
        final bo = (b['orders_count'] ?? b['orders'] ?? 0);
        final ai = ao is num ? ao.toInt() : int.tryParse('$ao') ?? 0;
        final bi = bo is num ? bo.toInt() : int.tryParse('$bo') ?? 0;
        if (bi != ai) return bi.compareTo(ai);
        final at = (a['total_aed'] ?? a['total'] ?? 0);
        final bt = (b['total_aed'] ?? b['total'] ?? 0);
        final ad = at is num ? at.toDouble() : double.tryParse('$at') ?? 0.0;
        final bd = bt is num ? bt.toDouble() : double.tryParse('$bt') ?? 0.0;
        return bd.compareTo(ad);
      });

      setState(() => _rows = list);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _rows.where((r) {
      if (_query.trim().isEmpty) return true;
      final phone = (r['phone'] ?? r['customer_phone'] ?? r['customer_key'] ?? r['key'] ?? '').toString();
      return phone.contains(_query.trim());
    }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Select customers',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: _loading ? null : _fetch,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                )
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _presets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final selected = i == _presetIndex;
                  return ChoiceChip(
                    label: Text(_presets[i].label),
                    selected: selected,
                    onSelected: _loading
                        ? null
                        : (v) {
                            if (!v) return;
                            setState(() => _presetIndex = i);
                            _fetch();
                          },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by phone…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 10),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No customers found for this period.'))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final r = filtered[i];
                        final phone = (r['phone'] ?? r['customer_phone'] ?? r['customer_key'] ?? r['key'] ?? '').toString();
                        final ocRaw = (r['orders_count'] ?? r['orders'] ?? 0);
                        final oc = ocRaw is num ? ocRaw.toInt() : int.tryParse('$ocRaw') ?? 0;
                        final totRaw = (r['total_aed'] ?? r['total'] ?? 0);
                        final tot = totRaw is num ? totRaw.toDouble() : double.tryParse('$totRaw') ?? 0.0;

                        return CheckboxListTile(
                          value: _selected.contains(phone),
                          onChanged: _loading
                              ? null
                              : (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selected.add(phone);
                                    } else {
                                      _selected.remove(phone);
                                    }
                                  });
                                },
                          title: Text(phone),
                          subtitle: Text('Orders: $oc  •  Total: AED ${tot.toStringAsFixed(0)}'),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton(
                  onPressed: _loading ? null : () => setState(() => _selected.clear()),
                  child: const Text('Clear'),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_selected),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Preset {
  final String label;
  final int? days;
  final int? months;
  const _Preset(this.label, this.days, this.months);
}

class _OrdersSummaryCard extends StatelessWidget {
  final Map<String, dynamic>? summary;
  const _OrdersSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary ?? const {};
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Restaurant performance', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _kpi('Orders', (s['orders_count'] ?? s['count'] ?? 0).toString()),
                _kpi('Revenue (AED)', _money(s['total_aed'] ?? s['total'])),
                _kpi('Subtotal', _money(s['subtotal_aed'] ?? s['subtotal'])),
                _kpi('Delivery', _money(s['delivery_fee_aed'] ?? s['delivery_fee'])),
                _kpi('Voucher Disc', _money(s['voucher_discount_aed'] ?? s['voucher_discount'])),
                _kpi('Loyalty Disc', _money(s['loyalty_discount_aed'] ?? s['loyalty_discount'])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpi(String label, String value) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.black.withOpacity(0.65), fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        ],
      ),
    );
  }
}


class _TopCustomersDataSource extends DataTableSource {
  final List<Map<String, dynamic>> customers;
  final Set<String> selectedPhones;
  final void Function(String phone, bool selected) onToggleSelect;

  _TopCustomersDataSource({
    required this.customers,
    required this.selectedPhones,
    required this.onToggleSelect,
  });

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= customers.length) return null;
    final c = customers[index];
    final phone = (c['phone'] ?? '').toString();
    final name = (c['name'] ?? '').toString();
    final sel = phone.isNotEmpty && selectedPhones.contains(phone);
    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(Checkbox(
          value: sel,
          onChanged: phone.isEmpty ? null : (v) => onToggleSelect(phone, v ?? false),
        )),
        DataCell(Text(name.isEmpty ? '(no name)' : name)),
        DataCell(Text(phone.isEmpty ? '-' : phone)),
        DataCell(Text((c['orders_count'] ?? 0).toString())),
        DataCell(Text(_money(c['total_spent_aed']))),
        DataCell(Text(_money(c['voucher_discount_aed']))),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => customers.length;

  @override
  int get selectedRowCount => selectedPhones.length;
}

class _TopCustomersCard extends StatelessWidget {
  final List<Map<String, dynamic>> customers;
  final Set<String> selectedPhones;
  final void Function(String phone, bool selected) onToggleSelect;
  final VoidCallback onAssignExisting;
  final VoidCallback onCreateAndAssign;

  const _TopCustomersCard({
    required this.customers,
    required this.selectedPhones,
    required this.onToggleSelect,
    required this.onAssignExisting,
    required this.onCreateAndAssign,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Top customers (target vouchers)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Text('${selectedPhones.length} selected'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: selectedPhones.isEmpty ? null : onAssignExisting,
                    icon: const Icon(Icons.local_offer),
                    label: const Text('Assign existing voucher'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: selectedPhones.isEmpty ? null : onCreateAndAssign,
                    icon: const Icon(Icons.add),
                    label: const Text('Create + assign'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (customers.isEmpty)
              const Text('No customers for the selected range.')
            else
              PaginatedDataTable(
              header: const Text('Top customers'),
              rowsPerPage: 10,
              availableRowsPerPage: const [10, 20, 50],
              columns: const [
                DataColumn(label: Text('')),
                DataColumn(label: Text('Customer')),
                DataColumn(label: Text('Phone')),
                DataColumn(label: Text('Orders')),
                DataColumn(label: Text('Spent (AED)')),
                DataColumn(label: Text('Voucher Disc')),
              ],
              source: _TopCustomersDataSource(
                customers: customers,
                selectedPhones: selectedPhones,
                onToggleSelect: onToggleSelect,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoucherSummaryCard extends StatelessWidget {
  final Map<String, dynamic>? summary;
  const _VoucherSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary ?? const {};
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Voucher performance', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _kpi('Redemptions', (s['redemptions_count'] ?? s['uses'] ?? 0).toString()),
                _kpi('Discount (AED)', _money(s['voucher_discount_aed'] ?? s['discount_aed'])),
                _kpi('Orders w/ voucher', (s['orders_with_voucher'] ?? s['orders'] ?? 0).toString()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpi(String label, String value) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.black.withOpacity(0.65), fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        ],
      ),
    );
  }
}

class _VoucherByCodeCard extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _VoucherByCodeCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Voucher breakdown (by code)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const Text('No voucher usage in this range.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Code')),
                    DataColumn(label: Text('Uses')),
                    DataColumn(label: Text('Discount (AED)')),
                    DataColumn(label: Text('Min Subtotal')),
                    DataColumn(label: Text('Active')),
                  ],
                  rows: items.map((v) {
                    final code = (v['code'] ?? v['voucher_code'] ?? '').toString();
                    return DataRow(cells: [
                      DataCell(Text(code)),
                      DataCell(Text((v['uses_count'] ?? v['uses'] ?? 0).toString())),
                      DataCell(Text(_money(v['discount_aed'] ?? v['voucher_discount_aed']))),
                      DataCell(Text(_money(v['min_subtotal_aed']))),
                      DataCell(Text((v['is_active'] ?? '').toString())),
                    ]);
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CampaignsCard extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _CampaignsCard({required this.items});


  String _safeDate10(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.isEmpty) return '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Campaigns', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const Text('No campaigns in this range.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Created')),
                    DataColumn(label: Text('Recipients')),
                    DataColumn(label: Text('Redemptions')),
                  ],
                  rows: items.map((c) {
                    return DataRow(cells: [
                      DataCell(Text((c['name'] ?? '').toString())),
                      DataCell(Text(_safeDate10(c['created_at']))),
                      DataCell(Text((c['recipients_count'] ?? c['recipients'] ?? 0).toString())),
                      DataCell(Text((c['redemptions_count'] ?? c['redemptions'] ?? 0).toString())),
                    ]);
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}