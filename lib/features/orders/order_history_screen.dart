import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/api/api_client.dart';
import 'order_details_screen.dart';

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key, this.initialPhone});

  final String? initialPhone;

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  late final TextEditingController _phoneCtrl;

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    final fromWidget = (widget.initialPhone ?? '').trim();
    final fromAuth = (FirebaseAuth.instance.currentUser?.phoneNumber ?? '').trim();
    _phoneCtrl = TextEditingController(text: (fromWidget.isNotEmpty ? fromWidget : fromAuth));
    if (_phoneCtrl.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() {
        _orders = const [];
        _error = 'Please log in to view your order history.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _orders = const [];
    });

    try {
      final encoded = Uri.encodeComponent(phone);

      // Your backend exposes this route:
      // GET /api/customers/:phone/orders
      final res = await ApiClient.dio.get('/api/customers/$encoded/orders');

      final data = res.data as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception((data['error'] ?? 'Failed to load orders').toString());
      }

      final ordersRaw = (data['orders'] as List?) ?? const [];
      final parsed = <Map<String, dynamic>>[];
      for (final o in ordersRaw) {
        if (o is Map<String, dynamic>) parsed.add(o);
      }

      setState(() {
        _orders = parsed;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _orders = const [];
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          children: [
            Builder(
              builder: (context) {
                final hasPhone = _phoneCtrl.text.trim().isNotEmpty;

                if (hasPhone) {
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Logged in as ${_phoneCtrl.text.trim()} — showing your orders',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: _loading ? null : _load,
                        icon: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                      ),
                    ],
                  );
                }

                // Fallback (should rarely happen): manual lookup.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter your phone number to see your order history.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Phone',
                              hintText: '+9715xxxxxxx',
                            ),
                            onSubmitted: (_) => _load(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: _loading ? null : _load,
                            child: const Text('Search'),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.error),
              ),
            ],
            const SizedBox(height: 18),
            if (!_loading && _orders.isEmpty && _error == null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant),
                  color: cs.surface,
                ),
                child: Text(
                  'No orders found yet. Place your first order and it will show here.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
            for (final o in _orders) ...[
              _OrderCard(
                order: o,
                onTap: () {
                  final id = (o['id'] ?? '').toString();
                  if (id.isEmpty) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrderDetailsScreen(orderId: id),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final Map<String, dynamic> order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final id = (order['id'] ?? '').toString();
    final status = (order['status'] ?? '').toString();
    double _num(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    final subtotalN = _num(order['subtotal_aed'] ?? order['subtotal']);
    final deliveryN = _num(order['delivery_fee_aed'] ?? order['delivery_aed'] ?? order['delivery_fee']);
    final voucherN = _num(order['voucher_discount_aed'] ?? order['voucher_discount']);
    final loyaltyN = _num(order['loyalty_discount_aed'] ?? order['loyalty_discount']);
    final legacyDiscountN = _num(order['discount_aed']);
    final totalFromOrderN = _num(order['total_aed'] ?? order['total']);
    final computedTotalN = subtotalN + deliveryN - voucherN - loyaltyN - legacyDiscountN;
    final totalN = (totalFromOrderN > 0 && voucherN <= 0 && loyaltyN <= 0 && legacyDiscountN <= 0)
        ? totalFromOrderN
        : (totalFromOrderN > 0 ? totalFromOrderN : computedTotalN);
    final total = totalN.toStringAsFixed(2);
    final placedAt = (order['placed_at'] ?? '').toString();

    final shortId = id.isEmpty
        ? '—'
        : (id.length <= 8 ? id : '${id.substring(0, 8)}…');

    final statusText = status.isEmpty ? 'ORDER' : status.toUpperCase();

    final accent = _statusColor(status, cs);

    final itemsRaw = order['items'];
    final items = (itemsRaw is List)
        ? itemsRaw.whereType<Map<String, dynamic>>().toList()
        : const <Map<String, dynamic>>[];

    String itemLine(Map<String, dynamic> it) {
      final qty = (it['quantity'] ?? 1);
      final name = (it['item_name'] ?? it['itemName'] ?? '').toString();
      final variant = (it['variant_name'] ?? it['variantName'] ?? '').toString();
      final title = variant.isNotEmpty ? '$name ($variant)' : name;
      return '${qty}x $title'.trim();
    }

    final previewLines = items.take(2).map(itemLine).where((s) => s.isNotEmpty).toList();
    final extraCount = max(0, items.length - previewLines.length);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
          color: cs.surface,
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 46,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        statusText,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 10),
                      if (placedAt.isNotEmpty)
                        Expanded(
                          child: Text(
                            placedAt,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Order ID: $shortId',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  if (previewLines.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final line in previewLines)
                      Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    if (extraCount > 0)
                      Text(
                        '+$extraCount more item${extraCount == 1 ? '' : 's'}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'AED $total',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap to track',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status, ColorScheme cs) {
    final s = status.toLowerCase();
    if (s.contains('cancel')) return cs.error;
    if (s.contains('deliver')) return cs.tertiary;
    if (s.contains('out')) return cs.primary;
    if (s.contains('ready')) return cs.secondary;
    if (s.contains('prep')) return cs.secondaryContainer;
    if (s.contains('accept')) return cs.primaryContainer;
    return cs.outline;
  }
}
