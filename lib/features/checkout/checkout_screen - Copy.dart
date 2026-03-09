import 'package:flutter/material.dart';
import 'order_success_screen.dart';
import 'offers_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/handi_api.dart';
import '../../core/auth/current_user_phone.dart';
import '../cart/cart_provider.dart';
import '../orders/order_status_screen.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameC = TextEditingController();
  final _phoneC = TextEditingController();

  // Voucher
  final _voucherCodeC = TextEditingController();
  bool _applyingVoucher = false;
  String? _voucherId;
  String? _appliedVoucherCode;
  double _voucherDiscountAed = 0.0;
  String? _voucherError;

  final _address1C = TextEditingController();
  final _areaC = TextEditingController();
  final _buildingC = TextEditingController();
  final _apartmentC = TextEditingController();
  final _notesC = TextEditingController();

  String _payment = 'cod'; // 'cod' or 'card'

  @override
  void initState() {
    super.initState();

    // Prefill phone from Firebase user (if logged in)
    Future.microtask(() async {
      final phone = (await CurrentUserPhone.get())?.trim();
      if (!mounted) return;
      if ((phone ?? '').isNotEmpty && _phoneC.text.trim().isEmpty) {
        setState(() => _phoneC.text = phone!);
      }
    });
  }
  bool _busy = false;

  @override
  void dispose() {
    _nameC.dispose();
    _phoneC.dispose();
    _voucherCodeC.dispose();
    _address1C.dispose();
    _areaC.dispose();
    _buildingC.dispose();
    _apartmentC.dispose();
    _notesC.dispose();
    super.dispose();
  }

  
  Future<void> _openOffers() async {
    final phone = _phoneC.text.trim().isNotEmpty
        ? _phoneC.text.trim()
        : ((await CurrentUserPhone.get())?.trim() ?? '');

    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => OffersScreen(phone: phone.isNotEmpty ? phone : null),
      ),
    );

    if (picked != null && picked.trim().isNotEmpty) {
      setState(() {
        _voucherCodeC.text = picked.trim().toUpperCase();
        _voucherError = null;
      });
      await _applyVoucher();
    }
  }


  double _deliveryFeeFor(double subtotal) {
    // Rule: under 50 => AED 5, 50+ => free (all over RAK)
    return subtotal < 50.0 ? 5.0 : 0.0;
  }

  Future<void> _applyVoucher() async {
    final code = _voucherCodeC.text.trim();
    if (code.isEmpty) {
      setState(() {
        _voucherError = 'Please enter a voucher code';
        _voucherId = null;
        _voucherDiscountAed = 0.0;
      });
      return;
    }

    // Restrict to ONE voucher per order
    if (_voucherId != null) {
      setState(() {
        _voucherError = 'Only one voucher can be applied per order. Remove it first.';
      });
      return;
    }

    final subtotal = ref.read(cartTotalProvider);
    if (subtotal <= 0) {
      setState(() {
        _voucherError = 'Add items to cart first';
        _voucherId = null;
        _voucherDiscountAed = 0.0;
      });
      return;
    }

    setState(() {
      _applyingVoucher = true;
      _voucherError = null;
    });

    try {
      // Backend supports using phone as a "customer key".
      final customerKey = _phoneC.text.trim();
      final result = await HandiApi().validateVoucher(
        voucherCode: code,
        subtotalAed: subtotal,
        customerKey: customerKey.isEmpty ? null : customerKey,
      );

      if (!mounted) return;

      if (result.ok && result.voucherId != null && result.discountAed > 0) {
        setState(() {
          _voucherId = result.voucherId;
          _appliedVoucherCode = code;
          _voucherDiscountAed = result.discountAed;
          _voucherError = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voucher applied: -AED ${result.discountAed.toStringAsFixed(2)}')),
        );
      } else {
        setState(() {
          _voucherId = null;
          _voucherDiscountAed = 0.0;
          _voucherError = result.error ?? 'Invalid voucher';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voucherId = null;
        _voucherDiscountAed = 0.0;
        _voucherError = 'Failed to validate voucher';
      });
    } finally {
      if (mounted) setState(() => _applyingVoucher = false);
    }
  }

  void _clearVoucher() {
    setState(() {
      _voucherId = null;
      _voucherDiscountAed = 0.0;
      _voucherError = null;
      _voucherCodeC.clear();
    });
  }

  Future<void> _placeOrder() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final cartLines = ref.read(cartProvider);
    if (cartLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty')),
      );
      return;
    }

    setState(() => _busy = true);

    try {
      final subtotal = ref.read(cartTotalProvider);
      final deliveryFee = _deliveryFeeFor(subtotal);
      final voucherDisc = (_voucherDiscountAed <= 0) ? 0.0 : (_voucherDiscountAed > subtotal ? subtotal : _voucherDiscountAed);
      final subtotalAfterVoucher = subtotal - voucherDisc;
      final total = subtotalAfterVoucher + deliveryFee;

      final payload = <String, dynamic>{
        'customer': {
          'name': _nameC.text.trim(),
          'phone': _phoneC.text.trim(),
          if (_voucherId != null) 'voucher_id': _voucherId,
          if ((_appliedVoucherCode ?? '').trim().isNotEmpty) 'voucher_code': (_appliedVoucherCode ?? '').trim(),
          if (voucherDisc > 0) 'voucher_discount_aed': voucherDisc,
        },
        'address': {
          'address_line1': _address1C.text.trim(),
          'area': _areaC.text.trim(),
          'building_villa': _buildingC.text.trim(),
          if (_apartmentC.text.trim().isNotEmpty) 'apartment': _apartmentC.text.trim(),
          // hard-coded because we decided "all over RAK"
          'emirate': 'Ras Al Khaimah',
        },
        'payment_method': _payment,
        if (_notesC.text.trim().isNotEmpty) 'notes': _notesC.text.trim(),
        'items': cartLines
            .map((e) => {
                  'item_id': e.itemId,
                  'variant_id': e.variantId,
                  'quantity': e.qty, // IMPORTANT: your model uses qty (not quantity)
                })
            .toList(),

        // NOTE: We are NOT sending delivery_zone_id at all (NO ZONES).
        // Backend should apply delivery logic globally.
      };
      if (((_appliedVoucherCode ?? '').trim()).isNotEmpty) {
        payload['voucher_code'] = (_appliedVoucherCode ?? '').trim();
      }


      final res = await HandiApi().createOrder(payload);

      if (res['ok'] == true) {
        final order = (res['order'] as Map?) ?? {};
        final orderId = (order['id'] ?? '').toString();

        // Clear cart after success
        ref.read(cartProvider.notifier).clear();

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OrderSuccessScreen(
              orderId: orderId,
              totalAed: total.toStringAsFixed(2),
            ),
          ),
        );
      } else {
        final msg = (res['error'] ?? 'Failed to place order').toString();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartLines = ref.watch(cartProvider);
    final subtotal = ref.watch(cartTotalProvider);
    final deliveryFee = _deliveryFeeFor(subtotal);
    final voucherDisc = (_voucherDiscountAed <= 0) ? 0.0 : (_voucherDiscountAed > subtotal ? subtotal : _voucherDiscountAed);
    final subtotalAfterVoucher = subtotal - voucherDisc;
    final total = subtotalAfterVoucher + deliveryFee;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Customer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              TextFormField(
                controller: _nameC,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter name' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phoneC,
                decoration: const InputDecoration(labelText: 'Phone (e.g. +9715xxxxxxx)'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter phone' : null,
              ),

              const SizedBox(height: 18),
              const Text('Delivery Address (RAK)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              TextFormField(
                controller: _address1C,
                decoration: const InputDecoration(labelText: 'Address line 1'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _areaC,
                decoration: const InputDecoration(labelText: 'Area'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _buildingC,
                decoration: const InputDecoration(labelText: 'Building / Villa'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _apartmentC,
                decoration: const InputDecoration(labelText: 'Apartment (optional)'),
              ),

              const SizedBox(height: 18),
              const Text('Payment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'cod', label: Text('Cash on Delivery')),
                  ButtonSegment(value: 'card', label: Text('Card')),
                ],
                selected: {_payment},
                onSelectionChanged: (set) => setState(() => _payment = set.first),
              ),

              const SizedBox(height: 18),
              TextFormField(
                controller: _notesC,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
                maxLines: 2,
              ),

              const SizedBox(height: 18),
              const Text('Voucher', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _openOffers,
                  icon: const Icon(Icons.local_offer_outlined, size: 18),
                  label: const Text('View available offers'),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _voucherCodeC,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Voucher code',
                        hintText: 'e.g. HANDI20',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 48,
                    child: FilledButton.tonal(
                      onPressed: _applyingVoucher ? null : _applyVoucher,
                      child: _applyingVoucher
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Apply'),
                    ),
                  ),
                  if (_voucherId != null) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () {
                          _voucherCodeC.clear();
                          setState(() {
                            _voucherId = null;
                            _appliedVoucherCode = null;
                            _voucherDiscountAed = 0.0;
                            _voucherError = null;
                          });
                        },
                        child: const Text('Clear'),
                      ),
                    ),
                  ],
                ],
              ),
              if (_voucherError != null) ...[
                const SizedBox(height: 8),
                Text(_voucherError!, style: const TextStyle(color: Colors.red)),
              ],

              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 10),

              const Text('Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              _summaryRow('Items', '${cartLines.length}'),
              _summaryRow('Subtotal', 'AED ${subtotal.toStringAsFixed(2)}'),
              if (voucherDisc > 0) ...[
                const SizedBox(height: 6),
                _summaryRow('Voucher', '-AED ${voucherDisc.toStringAsFixed(2)}'),
              ],
              _summaryRow('Delivery', 'AED ${deliveryFee.toStringAsFixed(2)}'),
              const SizedBox(height: 6),
              _summaryRow('Total', 'AED ${total.toStringAsFixed(2)}', bold: true),

              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _busy ? null : _placeOrder,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Place Order'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String left, String right, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(left, style: style), Text(right, style: style)],
      ),
    );
  }
}