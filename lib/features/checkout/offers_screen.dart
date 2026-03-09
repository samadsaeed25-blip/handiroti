// lib/features/checkout/offers_screen.dart
// OffersScreen v5 (do NOT touch global baseUrl; use absolute URL only for offers)
import 'dart:convert';

import 'package:dio/dio.dart';
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
  final String? phone;
  const OffersScreen({super.key, this.phone});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  bool _loading = true;
  String? _error;
  String? _debug;
  List<Map<String, dynamic>> _offers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic> _parseObj(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);

    if (data is String) {
      final s = data.trim();
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        throw Exception('JSON decoded to ${decoded.runtimeType}, expected object');
      } catch (_) {
        final snippet = s.length > 320 ? s.substring(0, 320) : s;
        throw Exception('Non‑JSON response (first 320 chars): $snippet');
      }
    }

    throw Exception('Unexpected response type: ${data.runtimeType}');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _debug = null;
    });

    final base = ApiClient.dio.options.baseUrl.toString();

    // Use absolute URL so we bypass any /api vs /api/api proxy quirks without changing the whole app.
    const url = 'https://order.handiroti.ae/api/customer/offers';

    try {
      final res = await ApiClient.dio.get(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: const {'Accept': 'application/json'},
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );

      final data = _parseObj(res.data);
      final list = (data['offers'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() {
        _offers = list;
        _loading = false;
        _debug = 'OffersScreen v5\n(baseUrl unchanged) $base\nGET $url';
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load offers. Please try again.';
        _debug = 'OffersScreen v5\nbaseUrl=$base\nGET $url\n\n$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offers'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: const TextStyle(fontSize: 14)),
                        if (_debug != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _debug!,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Colors.black.withOpacity(0.55)),
                          ),
                        ],
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
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

                        final headline = title.isNotEmpty ? title : 'Voucher $code';
                        final sub = desc.isNotEmpty ? desc : '';
                        final amountText = (kind == 'percent')
                            ? '${_toDouble(amount).toStringAsFixed(0)}% OFF'
                            : 'AED ${_toDouble(amount).toStringAsFixed(0)} OFF';

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
                                      child: Text(
                                        headline,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                      ),
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
                                    if (starts.length >= 10) _pill('From: ${starts.substring(0, 10)}'),
                                    if (ends.length >= 10) _pill('To: ${ends.substring(0, 10)}'),
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
