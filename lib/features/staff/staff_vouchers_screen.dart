// lib/features/staff/staff_vouchers_screen.dart
import 'package:flutter/material.dart';

import '../../models/voucher.dart';
import 'staff_api.dart';

class StaffVouchersScreen extends StatefulWidget {
  const StaffVouchersScreen({super.key});

  @override
  State<StaffVouchersScreen> createState() => _StaffVouchersScreenState();
}

class _StaffVouchersScreenState extends State<StaffVouchersScreen> {
  final _api = StaffApi();
  late Future<List<Voucher>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Voucher>> _load() async {
    final list = await _api.listVouchers();
    return list.map(Voucher.fromJson).toList();
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  Future<void> _showCreateDialog() async {
    final result = await showDialog<_VoucherFormResult>(
      context: context,
      builder: (_) => const _VoucherFormDialog(),
    );

    if (result == null) return;

    await _api.createVoucher(
      code: result.code,
      kind: result.kind,
      amount: result.amount,
      maxDiscountAed: result.maxDiscountAed,
      minSubtotalAed: result.minSubtotalAed,
      maxUsesTotal: result.maxUsesTotal,
      maxUsesPerCustomer: result.maxUsesPerCustomer,
      startsAt: result.startsAt,
      endsAt: result.endsAt,
      isActive: result.isActive,
    );

    if (mounted) _refresh();
  }

  Future<void> _toggleActive(Voucher v) async {
    await _api.updateVoucher(v.id, isActive: !v.isActive);
    if (mounted) _refresh();
  }

  Future<void> _sendVoucherPush(String code) async {
    try {
      await _api.pushVoucherByCode(code: code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Push sent for voucher: $code')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Push failed: $e')),
      );
    }
  }

  Future<void> _openPushCenter() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final keysCtrl = TextEditingController();

    Future<void> sendAll() async {
      final title = titleCtrl.text.trim();
      final body = bodyCtrl.text.trim();
      if (title.isEmpty || body.isEmpty) return;
      await _api.pushSendAll(title: title, body: body);
    }

    Future<void> sendCustomers() async {
      final title = titleCtrl.text.trim();
      final body = bodyCtrl.text.trim();
      final keys = keysCtrl.text
          .split(RegExp(r'[\n,]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (title.isEmpty || body.isEmpty || keys.isEmpty) return;
      await _api.pushSendCustomers(title: title, body: body, customerKeys: keys);
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Push Notifications', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 8),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bodyCtrl,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(labelText: 'Message'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: keysCtrl,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Customer keys (optional)',
                    hintText: 'One per line (phone numbers or customer keys)',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            await sendAll();
                            if (!mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Push sent to ALL users')),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Push failed: $e')),
                            );
                          }
                        },
                        icon: const Icon(Icons.campaign_outlined),
                        label: const Text('Send to All'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            await sendCustomers();
                            if (!mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Push sent to selected customers')),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Push failed: $e')),
                            );
                          }
                        },
                        icon: const Icon(Icons.people_outline),
                        label: const Text('Send to Customers'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _delete(Voucher v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete voucher?'),
        content: Text('Delete ${v.code}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    await _api.deleteVoucher(v.id);
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vouchers'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
      body: FutureBuilder<List<Voucher>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Failed to load vouchers:\n${snap.error}'),
              ),
            );
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('No vouchers yet. Tap Create.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final v = items[i];
              final subtitle = <String>[
                '${v.labelKind}: ${v.kind == 'percent' ? '${v.amount}%' : 'AED ${v.amount}'}',
                'Min: AED ${v.minSubtotalAed}',
                if (v.maxDiscountAed != null) 'Max: AED ${v.maxDiscountAed}',
                if (v.maxUsesPerCustomer != null) 'Per customer: ${v.maxUsesPerCustomer}',
                if (v.maxUsesTotal != null) 'Total uses: ${v.maxUsesTotal}',
              ].join(' • ');

              final range = (v.startsAt != null && v.endsAt != null)
                  ? '${v.startsAt!.toLocal()} → ${v.endsAt!.toLocal()}'
                  : 'No date range';

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              v.code,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Send push',
                            onPressed: () => _sendVoucherPush(v.code),
                            icon: const Icon(Icons.notifications_active_outlined),
                          ),
                          Switch(
                            value: v.isActive,
                            onChanged: (_) => _toggleActive(v),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () => _delete(v),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(subtitle),
                      const SizedBox(height: 6),
                      Text(
                        range,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _VoucherFormResult {
  final String code;
  final String kind;
  final num amount;
  final num? maxDiscountAed;
  final num minSubtotalAed;
  final int? maxUsesTotal;
  final int? maxUsesPerCustomer;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isActive;

  _VoucherFormResult({
    required this.code,
    required this.kind,
    required this.amount,
    required this.maxDiscountAed,
    required this.minSubtotalAed,
    required this.maxUsesTotal,
    required this.maxUsesPerCustomer,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
  });
}

class _VoucherFormDialog extends StatefulWidget {
  const _VoucherFormDialog();

  @override
  State<_VoucherFormDialog> createState() => _VoucherFormDialogState();
}

class _VoucherFormDialogState extends State<_VoucherFormDialog> {
  final _formKey = GlobalKey<FormState>();

  final _code = TextEditingController();
  String _kind = 'flat';
  final _amount = TextEditingController(text: '20');
  final _minSubtotal = TextEditingController(text: '0');
  final _maxDiscount = TextEditingController();
  final _maxUsesTotal = TextEditingController();
  final _maxUsesPerCustomer = TextEditingController(text: '1');

  DateTime _startsAt = DateTime.now().toUtc();
  DateTime _endsAt = DateTime.now().toUtc().add(const Duration(days: 3));
  bool _active = true;

  @override
  void dispose() {
    _code.dispose();
    _amount.dispose();
    _minSubtotal.dispose();
    _maxDiscount.dispose();
    _maxUsesTotal.dispose();
    _maxUsesPerCustomer.dispose();
    super.dispose();
  }

  num? _parseNum(String s) => num.tryParse(s.trim());
  int? _parseInt(String s) => int.tryParse(s.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create voucher'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(labelText: 'Code (e.g., HANDI20)'),
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _kind,
                  items: const [
                    DropdownMenuItem(value: 'flat', child: Text('Flat (AED off)')),
                    DropdownMenuItem(value: 'percent', child: Text('Percent (%) off')),
                  ],
                  onChanged: (v) => setState(() => _kind = v ?? 'flat'),
                  decoration: const InputDecoration(labelText: 'Kind'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _amount,
                  decoration: InputDecoration(
                    labelText: _kind == 'percent' ? 'Percent (e.g., 15)' : 'Amount AED (e.g., 20)',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = _parseNum(v ?? '');
                    if (n == null || n <= 0) return 'Enter a valid number';
                    if (_kind == 'percent' && n > 100) return 'Max 100%';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                if (_kind == 'percent')
                  TextFormField(
                    controller: _maxDiscount,
                    decoration: const InputDecoration(labelText: 'Max discount AED (optional)'),
                    keyboardType: TextInputType.number,
                  ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _minSubtotal,
                  decoration: const InputDecoration(labelText: 'Min subtotal AED'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = _parseNum(v ?? '');
                    if (n == null || n < 0) return 'Enter a valid number';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _maxUsesPerCustomer,
                  decoration: const InputDecoration(labelText: 'Max uses per customer (optional)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _maxUsesTotal,
                  decoration: const InputDecoration(labelText: 'Max total uses (optional)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: const Text('Active'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                _DateRow(
                  label: 'Starts (UTC)',
                  value: _startsAt,
                  onPick: () async {
                    final dt = await _pickDateTimeUtc(context, _startsAt);
                    if (dt != null) setState(() => _startsAt = dt);
                  },
                ),
                const SizedBox(height: 8),
                _DateRow(
                  label: 'Ends (UTC)',
                  value: _endsAt,
                  onPick: () async {
                    final dt = await _pickDateTimeUtc(context, _endsAt);
                    if (dt != null) setState(() => _endsAt = dt);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;

            final code = _code.text.trim().toUpperCase();
            final amount = _parseNum(_amount.text)!;
            final minSubtotal = _parseNum(_minSubtotal.text) ?? 0;

            final maxDiscount = (_kind == 'percent') ? _parseNum(_maxDiscount.text) : null;
            final maxUsesTotal = _parseInt(_maxUsesTotal.text);
            final maxUsesPerCustomer = _parseInt(_maxUsesPerCustomer.text);

            Navigator.pop(
              context,
              _VoucherFormResult(
                code: code,
                kind: _kind,
                amount: amount,
                maxDiscountAed: maxDiscount,
                minSubtotalAed: minSubtotal,
                maxUsesTotal: maxUsesTotal,
                maxUsesPerCustomer: maxUsesPerCustomer,
                startsAt: _startsAt,
                endsAt: _endsAt,
                isActive: _active,
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final DateTime value;
  final VoidCallback onPick;

  const _DateRow({
    required this.label,
    required this.value,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        TextButton(
          onPressed: onPick,
          child: Text(value.toIso8601String().replaceFirst('.000', '')),
        ),
      ],
    );
  }
}

Future<DateTime?> _pickDateTimeUtc(BuildContext context, DateTime initialUtc) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initialUtc.toLocal(),
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
  );
  if (date == null) return null;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initialUtc.toLocal()),
  );
  if (time == null) return null;

  final local = DateTime(date.year, date.month, date.day, time.hour, time.minute);
  return local.toUtc();
}
