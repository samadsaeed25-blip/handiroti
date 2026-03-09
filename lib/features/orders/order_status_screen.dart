import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/handi_api.dart';

class OrderStatusScreen extends StatefulWidget {
  final String orderId;
  const OrderStatusScreen({super.key, required this.orderId});

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  Timer? _timer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final res = await HandiApi().getOrder(widget.orderId);
      setState(() {
        _data = res;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = (_data?['order'] as Map<String, dynamic>?) ?? const {};
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
    final total = totalN > 0 ? totalN.toStringAsFixed(2) : (order['total_aed'] ?? '').toString();
    final placedAt = (order['placed_at'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order status'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Order ID', style: Theme.of(context).textTheme.labelLarge),
                      Text(widget.orderId, style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 16),
                      Text('Status', style: Theme.of(context).textTheme.labelLarge),
                      Text(status.isEmpty ? '-' : status),
                      const SizedBox(height: 16),
                      Text('Total', style: Theme.of(context).textTheme.labelLarge),
                      Text(total.isEmpty ? '-' : 'AED $total'),
                      const SizedBox(height: 16),
                      Text('Placed at', style: Theme.of(context).textTheme.labelLarge),
                      Text(placedAt.isEmpty ? '-' : placedAt),
                      const Spacer(),
                      Text(
                        'Auto-refreshing every 6 seconds…',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
      ),
    );
  }
}
