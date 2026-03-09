import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import 'staff_api.dart';

class StaffOrderView extends StatefulWidget {
  final String orderId;
  const StaffOrderView({super.key, required this.orderId});

  @override
  State<StaffOrderView> createState() => _StaffOrderViewState();
}

class _StaffOrderViewState extends State<StaffOrderView> {
  final StaffApi _staffApi = StaffApi();

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _order;
  List<dynamic> _items = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ApiClient.dio.get('/api/orders/${widget.orderId}');
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception((data['error'] ?? 'Failed to fetch order').toString());
      }

      _order = (data['order'] as Map).cast<String, dynamic>();
      _items = (data['items'] as List);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _status() => (_order?['status'] ?? '').toString();

  bool _isLocked() {
    final s = _status();
    return s == 'delivered' || s == 'cancelled';
  }

  Future<void> _setStatus(String status) async {
    if (_isLocked()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order is ${_status()} and cannot be changed.')),
      );
      return;
    }

    try {
      await _staffApi.updateStatus(orderId: widget.orderId, status: status);
      await _fetch();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _cancelOrder() async {
    if (_isLocked()) return;

    final controller = TextEditingController(text: 'Customer requested change. Please re-order.');
    final note = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Cancel order'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason / note',
              hintText: 'Why is this order cancelled?',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Close')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Cancel Order'),
            ),
          ],
        );
      },
    );

    if (note == null || note.trim().isEmpty) return;

    try {
      await _staffApi.updateStatus(orderId: widget.orderId, status: 'cancelled', note: note.trim());
      await _fetch();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  String _fmtAed(dynamic v) {
    if (v == null) return '0.00';
    if (v is num) return v.toStringAsFixed(2);
    return v.toString();
  }

  /// Key-value line for details cards.
  Widget _kv(BuildContext context, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;

    return Scaffold(
      appBar: AppBar(
        title: Text('Order ${widget.orderId.substring(0, 6)}'),
        actions: [
          IconButton(
            onPressed: _fetch,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _fetch, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async => _fetch(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Summary / status
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle(context, 'Order details'),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _statusChip(context, _status()),
                                  if (_isLocked())
                                    Chip(
                                      label: const Text('Final'),
                                      avatar: const Icon(Icons.lock, size: 16),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _kv(context, 'Status', _status()),
                              _kv(context, 'Payment', (o?['payment_method'] ?? '').toString()),
                              _kv(context, 'Placed at', (o?['placed_at'] ?? '').toString()),
                              const Divider(height: 18),
                              _kv(context, 'Customer', (o?['customer_name'] ?? '').toString()),
                              _kv(context, 'Phone', (o?['customer_phone'] ?? '').toString()),
                              const Divider(height: 18),
                              _kv(context, 'Deliver to', (o?['address_line1'] ?? '').toString()),
                              _kv(context, 'Address 2', (o?['address_line2'] ?? '').toString()),
                              _kv(context, 'Area', (o?['area'] ?? '').toString()),
                              _kv(context, 'Emirate', (o?['emirate'] ?? '').toString()),
                              if ((o?['label'] ?? '').toString().trim().isNotEmpty) ...[
                                const Divider(height: 18),
                                _kv(context, 'Label', (o?['label'] ?? '').toString()),
                              ],
                              const Divider(height: 18),
                              _kv(context, 'Subtotal', 'AED ${_fmtAed(o?['subtotal_aed'])}'),
                              if (_fmtAed(o?['discount_aed']) != '0.00')
                                _kv(context, 'Discount', 'AED ${_fmtAed(o?['discount_aed'])}'),
                              _kv(context, 'Delivery', 'AED ${_fmtAed(o?['delivery_fee_aed'])}'),
                              _kv(context, 'Total', 'AED ${_fmtAed(o?['total_aed'])}'),
                              if ((o?['notes'] ?? '').toString().trim().isNotEmpty) ...[
                                const Divider(height: 18),
                                _kv(context, 'Notes', (o?['notes'] ?? '').toString()),
                              ],
                              if ((o?['cancel_note'] ?? '').toString().trim().isNotEmpty) ...[
                                const Divider(height: 18),
                                _kv(context, 'Cancel reason', (o?['cancel_note'] ?? '').toString()),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Items
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle(context, 'Items'),
                              if (_items.isEmpty)
                                const Text('No items found for this order.')
                              else
                                ..._items.map((it) {
                                  final m = (it as Map).cast<String, dynamic>();
                                  final name = (m['name'] ?? m['item_name'] ?? '').toString();
                                  final qty = (m['qty'] ?? m['quantity'] ?? 1).toString();
                                  final variant = (m['variant_name'] ?? m['variant'] ?? '').toString();
                                  final price = m['price_aed'] ?? m['unit_price_aed'] ?? m['unit_price'] ?? m['line_total_aed'];
                                  final lineTotal = m['line_total_aed'] ?? m['total_aed'] ?? '';
                                   final itemNotes = (m['notes'] ?? m['note'] ?? m['special_instructions'] ?? '').toString().trim();

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 14,
                                          child: Text(qty),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name.isEmpty ? 'Item' : name,
                                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                                              ),
                                              if (variant.trim().isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 2),
                                                  child: Text(
                                                    variant,
                                                    style: Theme.of(context).textTheme.bodySmall,
                                                  ),
                                                ),
                                                                                          if (itemNotes.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 6),
                                                  child: Container(
                                                    width: double.infinity,
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFFFF3CD),
                                                      borderRadius: BorderRadius.circular(10),
                                                      border: Border.all(color: const Color(0xFFFFE08A)),
                                                    ),
                                                    child: Text(
                                                      'Note: $itemNotes',
                                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                    ),
                                                  ),
                                                ),
],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          lineTotal.toString().trim().isNotEmpty
                                              ? 'AED ${_fmtAed(lineTotal)}'
                                              : (price != null ? 'AED ${_fmtAed(price)}' : ''),
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Actions
                      if (!_isLocked())
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionTitle(context, 'Actions'),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    FilledButton.tonal(
                                      onPressed: () => _setStatus('accepted'),
                                      child: const Text('Accept'),
                                    ),
                                    FilledButton.tonal(
                                      onPressed: () => _setStatus('preparing'),
                                      child: const Text('Preparing'),
                                    ),
                                    FilledButton.tonal(
                                      onPressed: () => _setStatus('ready'),
                                      child: const Text('Ready'),
                                    ),
                                    FilledButton.tonal(
                                      onPressed: () => _setStatus('out_for_delivery'),
                                      child: const Text('Out'),
                                    ),
                                    FilledButton(
                                      onPressed: () => _setStatus('delivered'),
                                      child: const Text('Delivered'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _cancelOrder,
                                      icon: const Icon(Icons.cancel),
                                      label: const Text('Cancel'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _statusChip(BuildContext context, String status) {
    final s = status.trim().toLowerCase();
    IconData icon = Icons.receipt_long;
    String text = status.isEmpty ? 'unknown' : status;

    if (s == 'placed') {
      icon = Icons.fiber_new;
      text = 'placed';
    } else if (s == 'accepted') {
      icon = Icons.check_circle;
      text = 'accepted';
    } else if (s == 'preparing') {
      icon = Icons.restaurant;
      text = 'preparing';
    } else if (s == 'ready') {
      icon = Icons.shopping_bag;
      text = 'ready';
    } else if (s == 'out_for_delivery') {
      icon = Icons.delivery_dining;
      text = 'out';
    } else if (s == 'delivered') {
      icon = Icons.done_all;
      text = 'delivered';
    } else if (s == 'cancelled') {
      icon = Icons.cancel;
      text = 'cancelled';
    }

    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
    );
  }
}
