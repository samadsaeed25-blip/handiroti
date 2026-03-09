// lib/features/checkout/offers_screen.dart
import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';

double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  if (s.isEmpty) return 0.0;
  return double.tryParse(s) ?? 0.0;
}

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _offers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // IMPORTANT: baseUrl is https://order.handiroti.ae (no /api)
      final res = await ApiClient.dio.get('/api/customer/offers');
      final data = Map<String, dynamic>.from(res.data as Map);
      final list = (data['offers'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() {
        _offers = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load offers. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(fontSize: 14)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _offers.isEmpty
                  ? const Center(child: Text('No offers available right now.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _offers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final o = _offers[i];
                        final code = (o['code'] ?? '').toString();
                        final title = (o['title'] ?? '').toString().trim();
                        final desc = (o['description'] ?? '').toString().trim();
                        final kind = (o['kind'] ?? '').toString();
                        final amount = o['amount'] ?? o['amount_off_aed'] ?? o['percent_off'];
                        final min = _toDouble(o['min_subtotal_aed'] ?? o['min_cart_aed']);
                        final starts = (o['starts_at'] ?? '').toString();
                        final ends = (o['ends_at'] ?? '').toString();

                        String headline = title.isNotEmpty ? title : 'Voucher $code';
                        String sub = desc.isNotEmpty ? desc : '';
                        String amountText;
                        if (kind == 'percent') {
                          amountText = '${_toDouble(amount).toStringAsFixed(0)}% OFF';
                        } else {
                          amountText = 'AED ${_toDouble(amount).toStringAsFixed(0)} OFF';
                        }

                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(headline, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(999),
                                        color: Colors.black.withOpacity(0.06),
                                      ),
                                      child: Text(amountText, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                                if (sub.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(sub, style: TextStyle(color: Colors.black.withOpacity(0.65))),
                                ],
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 6,
                                  children: [
                                    _pill('Code: $code'),
                                    if (min > 0) _pill('Min: AED ${min.toStringAsFixed(0)}'),
                                    if (starts.isNotEmpty) _pill('From: ${starts.substring(0, 10)}'),
                                    if (ends.isNotEmpty) _pill('To: ${ends.substring(0, 10)}'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _pill(String t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.black.withOpacity(0.05),
      ),
      child: Text(t, style: const TextStyle(fontSize: 12)),
    );
  }
}
