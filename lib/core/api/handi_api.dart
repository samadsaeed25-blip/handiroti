import 'dart:convert';
import 'package:http/http.dart' as http;

/// Result returned from `/api/vouchers/validate`.
class VoucherValidationResult {
  final bool ok;
  final String? error;
  final String? voucherId;
  final double discountAed;

  const VoucherValidationResult({
    required this.ok,
    this.error,
    this.voucherId,
    required this.discountAed,
  });

  factory VoucherValidationResult.fromJson(Map<String, dynamic> json) {
    final ok = json['ok'] == true;
    final voucher = (json['voucher'] is Map)
        ? (json['voucher'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final discRaw = voucher['discount_aed'];
    double disc = 0;
    if (discRaw is num) disc = discRaw.toDouble();
    if (discRaw is String) disc = double.tryParse(discRaw) ?? 0;
    return VoucherValidationResult(
      ok: ok,
      error: json['error']?.toString(),
      voucherId: voucher['voucher_id']?.toString(),
      discountAed: disc,
    );
  }
}

class SavedAddress {
  final String id;
  final String label;
  final String addressLine1;
  final String addressLine2;
  final String area;
  final String emirate;
  final bool isDefault;

  const SavedAddress({
    required this.id,
    required this.label,
    required this.addressLine1,
    required this.addressLine2,
    required this.area,
    required this.emirate,
    required this.isDefault,
  });

  factory SavedAddress.fromJson(Map<String, dynamic> json) {
    return SavedAddress(
      id: (json['id'] ?? '').toString(),
      label: ((json['label'] ?? 'Other').toString().trim().isEmpty
              ? 'Other'
              : (json['label'] ?? 'Other').toString().trim()),
      addressLine1: (json['address_line1'] ?? '').toString(),
      addressLine2: (json['address_line2'] ?? '').toString(),
      area: (json['area'] ?? '').toString(),
      emirate: (json['emirate'] ?? '').toString(),
      isDefault: json['is_default'] == true,
    );
  }

  String get fullAddress {
    final parts = <String>[
      if (addressLine1.trim().isNotEmpty) addressLine1.trim(),
      if (addressLine2.trim().isNotEmpty) addressLine2.trim(),
      if (area.trim().isNotEmpty) area.trim(),
      if (emirate.trim().isNotEmpty) emirate.trim(),
    ];
    return parts.join(', ');
  }
}

class CustomerProfileResult {
  final bool ok;
  final String? error;
  final String? customerId;
  final String? phone;
  final String? name;
  final List<SavedAddress> addresses;

  const CustomerProfileResult({
    required this.ok,
    this.error,
    this.customerId,
    this.phone,
    this.name,
    this.addresses = const [],
  });

  factory CustomerProfileResult.fromJson(Map<String, dynamic> json) {
    final customer = (json['customer'] is Map)
        ? (json['customer'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    final rawAddresses = (json['addresses'] is List)
        ? (json['addresses'] as List)
        : const [];

    return CustomerProfileResult(
      ok: json['ok'] == true,
      error: json['error']?.toString(),
      customerId: customer['id']?.toString(),
      phone: customer['phone']?.toString(),
      name: customer['name']?.toString(),
      addresses: rawAddresses
          .whereType<Map>()
          .map((e) => SavedAddress.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

class HandiApi {
  /// Change only if your domain changes
  static const String baseUrl = 'https://order.handiroti.ae';

  final http.Client _client;
  HandiApi({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> _headers() => const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  dynamic _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return {'ok': false, 'error': 'Invalid JSON response', 'raw': body};
    }
  }

  Map<String, dynamic> _asError(int code, dynamic body) {
    if (body is Map<String, dynamic>) {
      return {
        'ok': false,
        'status': code,
        'error': body['error'] ?? body['message'] ?? 'Request failed',
        ...body,
      };
    }
    return {
      'ok': false,
      'status': code,
      'error': 'Request failed',
      'body': body,
    };
  }

  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> payload) async {
    final uri = Uri.parse('$baseUrl/api/orders');
    final resp =
        await _client.post(uri, headers: _headers(), body: jsonEncode(payload));
    final body = _decodeJson(resp.body);

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return (body is Map<String, dynamic>) ? body : {'ok': true, 'data': body};
    }
    return _asError(resp.statusCode, body);
  }

  Future<Map<String, dynamic>> getOrder(String orderId) async {
    final uri = Uri.parse('$baseUrl/api/orders/$orderId');
    final resp = await _client.get(uri, headers: _headers());
    final body = _decodeJson(resp.body);

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return (body is Map<String, dynamic>) ? body : {'ok': true, 'data': body};
    }
    return _asError(resp.statusCode, body);
  }

  Future<Map<String, dynamic>> getCustomerOrders(String phone) async {
    final enc = Uri.encodeComponent(phone);
    final uri = Uri.parse('$baseUrl/api/customers/$enc/orders');
    final resp = await _client.get(uri, headers: _headers());
    final body = _decodeJson(resp.body);

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return (body is Map<String, dynamic>) ? body : {'ok': true, 'data': body};
    }
    return _asError(resp.statusCode, body);
  }

  Future<CustomerProfileResult> getCustomerProfile(String phone) async {
    final enc = Uri.encodeComponent(phone.trim());
    final uri = Uri.parse('$baseUrl/api/customers/$enc/profile');
    final resp = await _client.get(uri, headers: _headers());
    final body = _decodeJson(resp.body);

    if (body is Map<String, dynamic>) {
      return CustomerProfileResult.fromJson(body);
    }

    return const CustomerProfileResult(
      ok: false,
      error: 'Invalid server response',
    );
  }

  Future<Map<String, dynamic>> deleteSavedAddress({
    required String phone,
    required String addressId,
  }) async {
    final encPhone = Uri.encodeComponent(phone.trim());
    final encAddress = Uri.encodeComponent(addressId.trim());
    final uri = Uri.parse('$baseUrl/api/customers/$encPhone/addresses/$encAddress');
    final resp = await _client.delete(uri, headers: _headers());
    final body = _decodeJson(resp.body);

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return (body is Map<String, dynamic>) ? body : {'ok': true, 'data': body};
    }
    return _asError(resp.statusCode, body);
  }

  Future<VoucherValidationResult> validateVoucher({
    required String voucherCode,
    required double subtotalAed,
    String? customerKey,
  }) async {
    final payload = <String, dynamic>{
      'voucher_code': voucherCode.trim(),
      'subtotal_aed': subtotalAed,
    };
    final ck = customerKey?.trim();
    if (ck != null && ck.isNotEmpty) {
      payload['customer_id'] = ck;
    }

    final res = await http.post(
      Uri.parse('$baseUrl/api/vouchers/validate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return VoucherValidationResult.fromJson(data);
    } catch (_) {
      return const VoucherValidationResult(
        ok: false,
        error: 'Invalid server response',
        voucherId: null,
        discountAed: 0,
      );
    }
  }
}
