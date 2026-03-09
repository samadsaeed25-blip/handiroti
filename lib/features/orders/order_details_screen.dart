import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';

class OrderDetailsScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailsScreen({super.key, required this.orderId});

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
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
      final data = (res.data as Map).cast<String, dynamic>();
      if (data['ok'] != true) {
        throw Exception((data['error'] ?? 'Failed to load order').toString());
      }

      final o = (data['order'] as Map).cast<String, dynamic>();
      final items = (data['items'] as List?) ?? const [];

      setState(() {
        _order = o;
        _items = items;
        _loading = false;
      });
    } catch (e) {
      setState(() {
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
        title: const Text('Order Details'),
        actions: [
          IconButton(
            onPressed: _fetch,
            icon: const Icon(Icons.refresh_rounded),
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
              : _buildContent(cs),
    );
  }

  Widget _buildContent(ColorScheme cs) {
    final o = _order ?? const {};
    final status = (o['status'] ?? '').toString();    double _num(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    final subtotalN = _num(o['subtotal_aed'] ?? o['subtotal']);
    final deliveryN = _num(o['delivery_fee_aed'] ?? o['delivery_aed'] ?? o['delivery_fee']);
    final voucherN = _num(o['voucher_discount_aed'] ?? o['voucher_discount']);
    final loyaltyN = _num(o['loyalty_discount_aed'] ?? o['loyalty_discount']);
    final legacyDiscountN = _num(o['discount_aed']);
    final totalFromOrderN = _num(o['total_aed'] ?? o['total']);
    final computedTotalN = subtotalN + deliveryN - voucherN - loyaltyN - legacyDiscountN;
    final totalN = (totalFromOrderN > 0 && voucherN <= 0 && loyaltyN <= 0 && legacyDiscountN <= 0)
        ? totalFromOrderN
        : (totalFromOrderN > 0 ? totalFromOrderN : computedTotalN);

    final total = totalN.toStringAsFixed(2);
    final delivery = deliveryN.toStringAsFixed(2);
    final discount = legacyDiscountN.toStringAsFixed(2);
    final subtotal = subtotalN.toStringAsFixed(2);
    final voucher = voucherN.toStringAsFixed(2);
    final loyalty = loyaltyN.toStringAsFixed(2);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
            color: cs.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Order #${widget.orderId}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Status: $status', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text('Payment: ${(o['payment_method'] ?? '').toString()}'),
              const SizedBox(height: 8),
              Text('Deliver to: ${(o['address_line1'] ?? '').toString()}'),
              Text('Area: ${(o['area'] ?? '').toString()}'),
              Text('Emirate: ${(o['emirate'] ?? '').toString()}'),
            ],
          ),
        ),
        const SizedBox(height: 14),

        const Text('Items', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        if (_items.isEmpty)
          Text('No items found for this order.', style: TextStyle(color: cs.onSurfaceVariant))
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
              color: cs.surface,
            ),
            child: Column(
              children: [
                for (int i = 0; i < _items.length; i++) ...[
                  _OrderItemRow(item: (_items[i] as Map).cast<String, dynamic>()),
                  if (i != _items.length - 1)
                    Divider(height: 1, thickness: 1, color: cs.outlineVariant),
                ],
              ],
            ),
          ),

        const SizedBox(height: 14),
        const Text('Bill Summary', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
            color: cs.surface,
          ),
          child: Column(
            children: [
              _kv('Subtotal', 'AED $subtotal'),
              if (voucherN > 0) _kv('Voucher', 'AED -$voucher'),
              if (loyaltyN > 0) _kv('Loyalty', 'AED -$loyalty'),
              if (legacyDiscountN > 0) _kv('Discount', 'AED -$discount'),
              _kv('Delivery', 'AED $delivery'),
              const Divider(),
              _kv('Total', 'AED $total', bold: true),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _kv(String k, String v, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600))),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w700)),
        ],
      ),
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  const _OrderItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final name = (item['item_name'] ?? item['name'] ?? 'Item').toString();
    final variant = (item['variant_name'] ?? '').toString();
    final qty = (item['quantity'] ?? item['qty'] ?? 1).toString();

    final unit = (item['unit_price_aed'] ?? item['unit_price'] ?? '').toString();
    final lineTotal = (item['line_total_aed'] ?? item['line_total'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name${variant.isNotEmpty ? " ($variant)" : ""}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text('Qty: $qty', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                if (unit.isNotEmpty) Text('Unit: AED $unit', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (lineTotal.isNotEmpty)
            Text('AED $lineTotal', style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
