import 'dart:convert';

import 'dart:async';
import 'package:dio/dio.dart';

import 'staff_config.dart';

import '../../core/api/api_client.dart';

class StaffApi {
  // Global defaults (can be set after staff login).
  static String _globalBaseUrl = const String.fromEnvironment(
    'HANDI_ROTI_BASE_URL',
    defaultValue: '',
  );
  static String _globalAdminKey = const String.fromEnvironment(
    'HANDI_ROTI_ADMIN_KEY',
    defaultValue: '',
  );

  static void setGlobalBaseUrl(String url) {
    _globalBaseUrl = url.trim();
  }

  static void setGlobalAdminKey(String key) {
    _globalAdminKey = key.trim();
  }

  StaffApi({
    String? baseUrl,
    String? adminKey,
    Dio? dio,
  })  : _baseUrl = _pickBaseUrl(baseUrl),
        _adminKey = _pickAdminKey(adminKey),
        _dio = (dio ??
            Dio(BaseOptions(
              baseUrl: _pickBaseUrl(baseUrl),
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 30),
              // Don't throw DioException on non-2xx; we handle status codes + retries ourselves.
              validateStatus: (s) => s != null && s < 600,
            )));

  static String _pickBaseUrl(String? baseUrl) {
    String normalize(String s) {
      var out = s.trim();
      // Accept either https://domain or https://domain/api as input.
      if (out.endsWith('/')) out = out.substring(0, out.length - 1);
      if (out.toLowerCase().endsWith('/api')) {
        out = out.substring(0, out.length - 4);
      }
      return out;
    }

    final v = normalize(baseUrl ?? '');
    if (v.isNotEmpty) return v;

    final g = normalize(_globalBaseUrl);
    if (g.isNotEmpty) return g;

    // Last-resort default
    return 'https://order.handiroti.ae';
  }

  static String _pickAdminKey(String? adminKey) {
    final v = (adminKey ?? '').trim();
    if (v.isNotEmpty) return v;

    final g = (_globalAdminKey).trim();
    if (g.isNotEmpty) return g;

    // No key (UI may still show, but calls will 401 until staff logs in and sets it).
    return StaffConfig.adminKey;
  }

  final String _baseUrl;
  String _adminKey;
  final Dio _dio;

  String get baseUrl => _baseUrl;
  String get adminKey => _adminKey;

  void setAdminKey(String key) {
    _adminKey = key.trim();
    StaffApi.setGlobalAdminKey(_adminKey);
  }

  Options _opts() {
    return Options(headers: {
      'x-admin-key': _adminKey,
    });
  }



  // -----------------------------
  // Internal: retry wrapper for transient network/proxy errors (502/503/504/timeouts)
  // This prevents "Accept" etc. from failing once and then succeeding on manual retry.
  Future<T> _withRetry<T>(Future<T> Function() op, {int retries = 2}) async {
    int attempt = 0;
    while (true) {
      try {
        return await op();
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        final transientStatus = status == 502 || status == 503 || status == 504 || status == 408;
        final transientType = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.connectionError;
        if (attempt >= retries || (!transientStatus && !transientType)) {
          rethrow;
        }
        // small exponential-ish backoff
        final waitMs = attempt == 0 ? 350 : 900;
        await Future<void>.delayed(Duration(milliseconds: waitMs));
        attempt++;
      } catch (_) {
        rethrow;
      }
    }
  }

  // -----------------------------
  // Orders
  // -----------------------------

  /// List admin orders by status: placed/accepted/preparing/ready/out_for_delivery/delivered/cancelled
  Future<List<Map<String, dynamic>>> listOrders({
    required String status,
    int limit = 50,
  }) async {
    final res = await _dio.get(
      '/api/admin/orders',
      queryParameters: {'status': status, 'limit': limit},
      options: _opts(),
    );

    final data = res.data;
    if (data is Map && data['ok'] == true) {
      final orders = data['orders'];
      if (orders is List) {
        return orders
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      }
      return <Map<String, dynamic>>[];
    }

    throw Exception((data is Map && data['error'] != null)
        ? data['error'].toString()
        : 'Failed to load orders');
  }

  /// Some screens call this name
  Future<void> updateStatus({
    required String orderId,
    required String status,
    String? note,
  }) async {
    await updateOrderStatus(orderId: orderId, status: status, note: note);
  }

  /// Some screens call this name
  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
    String? note,
  }) async {
    await _withRetry(() => _dio.patch(
      '/api/admin/orders/$orderId/status',
      data: {'status': status, if (note != null) 'note': note},
      options: _opts(),
    ));
  }

  Future<Map<String, dynamic>> getOrderDetails({
    required String orderId,
  }) async {
    final res = await _dio.get(
      '/api/admin/orders/$orderId',
      options: _opts(),
    );

    final data = res.data;
    if (data is Map && data['ok'] == true) {
      final order = data['order'];
      if (order is Map) {
        return order.map((k, v) => MapEntry(k.toString(), v));
      }
      return <String, dynamic>{};
    }

    throw Exception((data is Map && data['error'] != null)
        ? data['error'].toString()
        : 'Failed to load order details');
  }

  // -----------------------------
  // Menu - Admin
  // -----------------------------

  /// Customer menu (public) - for staff view if needed
  Future<List<Map<String, dynamic>>> fetchMenuCategories() async {
    final res = await _dio.get('/api/menu');
    final data = res.data;

    if (data is Map && data['ok'] == true) {
      final cats = data['categories'];
      if (cats is List) {
        return cats
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      }
      return <Map<String, dynamic>>[];
    }

    throw Exception((data is Map && data['error'] != null)
        ? data['error'].toString()
        : 'Failed to load menu');
  }

  /// Admin menu (full editable)
  Future<List<Map<String, dynamic>>> getAdminMenu() async {
    final res = await _dio.get('/api/admin/menu', options: _opts());
    final data = res.data;

    if (data is Map && data['ok'] == true) {
      final cats = (data['categories'] is List) ? (data['categories'] as List) : const [];
      final items = (data['items'] is List) ? (data['items'] as List) : const [];
      final vars = (data['variants'] is List) ? (data['variants'] as List) : const [];

      // Normalize maps
      final categories = cats
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      final itemMaps = items
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      final varMaps = vars
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      // Group variants by item_id
      final variantsByItem = <String, List<Map<String, dynamic>>>{};
      for (final v in varMaps) {
        final itemId = (v['item_id'] ?? '').toString();
        if (itemId.isEmpty) continue;
        (variantsByItem[itemId] ??= <Map<String, dynamic>>[]).add(v);
      }

      // Group items by category_id, attach variants
      final itemsByCategory = <String, List<Map<String, dynamic>>>{};
      for (final it in itemMaps) {
        final cid = (it['category_id'] ?? '').toString();
        final iid = (it['id'] ?? '').toString();
        if (iid.isNotEmpty) {
          it['variants'] = variantsByItem[iid] ?? <Map<String, dynamic>>[];
        } else {
          it['variants'] = <Map<String, dynamic>>[];
        }
        if (cid.isEmpty) continue;
        (itemsByCategory[cid] ??= <Map<String, dynamic>>[]).add(it);
      }

      // Attach items to categories
      for (final c in categories) {
        final cid = (c['id'] ?? '').toString();
        c['items'] = itemsByCategory[cid] ?? <Map<String, dynamic>>[];
      }

      return categories;
    }

    throw Exception((data is Map && data['error'] != null)
        ? data['error'].toString()
        : 'Failed to load admin menu');
  }

  Future<void> toggleItem({
    required String itemId,
    bool? isActive,
  }) async {
    await _withRetry(() => _dio.patch(
      '/api/admin/items/$itemId',
      data: {'is_active': isActive ?? true},
      options: _opts(),
    ));
  }

  Future<void> toggleVariant({
    required String variantId,
    bool? isActive,
  }) async {
    await _withRetry(() => _dio.patch(
      '/api/admin/variants/$variantId',
      data: {'is_active': isActive ?? true},
      options: _opts(),
    ));
  }

  Future<Map<String, dynamic>> createCategory({
    required String name,
    int sortOrder = 0,
    bool isActive = true,
  }) async {
    final res = await _withRetry(() => _dio.post(
      '/api/admin/categories',
      data: {
        'name': name,
'is_active': isActive,
      },
      options: _opts(),
    ));
    final data = res.data;
    if (data is Map && data['ok'] == true) {
      return (data['category'] is Map)
          ? (data['category'] as Map)
              .map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
    }
    throw Exception((data is Map && data['error'] != null)
        ? data['error'].toString()
        : 'Failed to create category');
  }

  Future<Map<String, dynamic>> updateCategory({
    required String categoryId,
    String? name,
    int? sortOrder,
    bool? isActive,
  }) async {
    final res = await _withRetry(() => _dio.patch(
      '/api/admin/categories/$categoryId',
      data: {
        if (name != null) 'name': name,
        if (isActive != null) 'is_active': isActive,
      },
      options: _opts(),
    ));
    final data = res.data;
    if (data is Map && data['ok'] == true) {
      return (data['category'] is Map)
          ? (data['category'] as Map)
              .map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
    }
    throw Exception((data is Map && data['error'] != null)
        ? data['error'].toString()
        : 'Failed to update category');
  }

  Future<void> deleteCategory({required String categoryId}) async {
    final res = await _withRetry(() => _dio.delete(
      '/api/admin/categories/$categoryId',
      options: _opts(),
    ));
    final data = res.data;
    if (data is Map && data['ok'] == true) return;

    throw Exception((data is Map && data['error'] != null)
        ? data['error'].toString()
        : 'Failed to delete category');
  }

  Future<Map<String, dynamic>> createItem({
    required String categoryId,
    required String name,
    String description = '',
    double basePriceAed = 0,
    bool isActive = true,
    String? imageUrl,
    int sortOrder = 0,
  }) async {
    final res = await _withRetry(() => _dio.post(
      '/api/admin/items',
      data: {
        'category_id': categoryId,
        'name': name,
        'description': description,
        'base_price_aed': basePriceAed,
        'is_active': isActive,
        'image_url': imageUrl,
},
      options: _opts(),
    ));
    final data = res.data;
    if (data is Map && data['ok'] == true) {
      return (data['item'] is Map)
          ? (data['item'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
    }
    throw Exception((data is Map && data['error'] != null)
        ? data['error'].toString()
        : 'Failed to create item');
  }

  Future<Map<String, dynamic>> updateItem({
    required String itemId,
    String? categoryId,
    String? name,
    String? description,
    double? basePriceAed,
    bool? isActive,
    String? imageUrl,
    int? sortOrder,
  }) async {
    final res = await _withRetry(() => _dio.patch(
      '/api/admin/items/$itemId',
      data: {
        if (categoryId != null) 'category_id': categoryId,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (basePriceAed != null) 'base_price_aed': basePriceAed,
        if (isActive != null) 'is_active': isActive,
        if (imageUrl != null) 'image_url': imageUrl,
      },
      options: _opts(),
    ));
    final data = res.data;
    if (data is Map && data['ok'] == true) {
      return (data['item'] is Map)
          ? (data['item'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
    }
    throw Exception((data is Map && data['error'] != null)
        ? data['error'].toString()
        : 'Failed to update item');
  }

  Future<void> deleteItem({required String itemId}) async {
    final res = await _withRetry(() => _dio.delete(
      '/api/admin/items/$itemId',
      options: _opts(),
    ));
    final data = res.data;
    if (data is Map && data['ok'] == true) return;

    throw Exception((data is Map && data['error'] != null)
        ? data['error'].toString()
        : 'Failed to delete item');
  }

  Future<Map<String, dynamic>> createVariant({
    required String itemId,
    required String name,
    required double priceAed,
    bool isActive = true,
    int sortOrder = 0,
  }) async {
    final res = await _withRetry(() => _dio.post(
      '/api/admin/items/$itemId/variants',
      data: {
        'name': name,
        'price_aed': priceAed,
        'is_active': isActive,
        'sort_order': sortOrder,
},
      options: _opts(),
    ));
    final data = res.data;
    if (data is Map && data['ok'] == true) {
      return (data['variant'] is Map)
          ? (data['variant'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
    }
    throw Exception((data is Map && data['error'] != null)
        ? data['error'].toString()
        : 'Failed to create variant');
  }

  Future<Map<String, dynamic>> updateVariant({
    required String variantId,
    String? itemId,
    String? name,
    double? priceAed,
    bool? isActive,
    int? sortOrder,
  }) async {
    final res = await _withRetry(() => _dio.patch(
      '/api/admin/variants/$variantId',
      data: {
        if (name != null) 'name': name,
        if (priceAed != null) 'price_aed': priceAed,
        if (isActive != null) 'is_active': isActive,
      },
      options: _opts(),
    ));
    final data = res.data;
    if (data is Map && data['ok'] == true) {
      return (data['variant'] is Map)
          ? (data['variant'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
    }
    throw Exception((data is Map && data['error'] != null)
        ? data['error'].toString()
        : 'Failed to update variant');
  }

  Future<void> deleteVariant({required String variantId}) async {
    final res = await _withRetry(() => _dio.delete(
      '/api/admin/variants/$variantId',
      options: _opts(),
    ));
    final data = res.data;
    if (data is Map && data['ok'] == true) return;

    throw Exception((data is Map && data['error'] != null)
        ? data['error'].toString()
        : 'Failed to delete variant');
  }

  /// Base64 image upload helper (returns a NON-null URL string)
  Future<String> uploadMenuImage({
    required String fileName,
    required String mime,
    required String base64,
  }) async {
    final res = await _withRetry(() => _dio.post(
      '/api/admin/menu_images',
      data: {
        'file_name': fileName,
        'mime': mime,
        'base64': base64,
      },
      options: _opts(),
    ));

    final data = res.data;
    if (data is Map && data['ok'] == true) {
      final url = data['url']?.toString();
      if (url == null || url.trim().isEmpty) {
        throw Exception('Upload succeeded but no URL returned');
      }
      return url;
    }

    throw Exception((data is Map && data['error'] != null)
        ? data['error'].toString()
        : 'Failed to upload image');
  }

  // Convenience if any old code still calls this name
  Future<String> uploadMenuImageBase64({
    required String fileName,
    required String mime,
    required String base64,
  }) {
    return uploadMenuImage(fileName: fileName, mime: mime, base64: base64);
  }

  // Utility decode if needed by older code
  static String stripDataUrlPrefix(String b64) {
    final idx = b64.indexOf(',');
    if (idx >= 0) return b64.substring(idx + 1);
    return b64;
  }

  static List<int> decodeBase64Bytes(String b64) {
    return base64Decode(stripDataUrlPrefix(b64));
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) return v.cast<String, dynamic>();
    return <String, dynamic>{};
  }


  // ============================
  // Vouchers (Admin)
  // ============================

  Future<List<Map<String, dynamic>>> listVouchers() async {
    final res = await _dio.get('/api/admin/vouchers', options: _opts());
    final data = _asMap(res.data);
    final list = (data['vouchers'] as List? ?? const []);
    return list
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createVoucher({
    required String code,
    required String kind, // "flat" | "percent"
    required num amount,
    num? maxDiscountAed,
    num minSubtotalAed = 0,
    int? maxUsesTotal,
    int? maxUsesPerCustomer,
    DateTime? startsAt,
    DateTime? endsAt,
    bool isActive = true,
  }) async {
    final payload = <String, dynamic>{
      'code': code.trim(),
      'kind': kind,
      'amount': amount,
      'max_discount_aed': maxDiscountAed,
      'min_subtotal_aed': minSubtotalAed,
      'max_uses_total': maxUsesTotal,
      'max_uses_per_customer': maxUsesPerCustomer,
      'starts_at': (startsAt ?? DateTime.now().toUtc()).toIso8601String(),
      'ends_at': (endsAt ?? DateTime.now().toUtc().add(const Duration(days: 3)))
          .toIso8601String(),
      'is_active': isActive,
    };
    final res = await _withRetry(() => _dio.post('/api/admin/vouchers', data: payload, options: _opts()));
    final data = _asMap(res.data);
    return (data['voucher'] as Map?)?.cast<String, dynamic>() ?? data;
  }

  Future<Map<String, dynamic>> updateVoucher(
    String voucherId, {
    String? code,
    String? kind,
    num? amount,
    num? maxDiscountAed,
    num? minSubtotalAed,
    int? maxUsesTotal,
    int? maxUsesPerCustomer,
    DateTime? startsAt,
    DateTime? endsAt,
    bool? isActive,
  }) async {
    final payload = <String, dynamic>{};
    if (code != null) payload['code'] = code.trim();
    if (kind != null) payload['kind'] = kind;
    if (amount != null) payload['amount'] = amount;
    if (maxDiscountAed != null) payload['max_discount_aed'] = maxDiscountAed;
    if (minSubtotalAed != null) payload['min_subtotal_aed'] = minSubtotalAed;
    if (maxUsesTotal != null) payload['max_uses_total'] = maxUsesTotal;
    if (maxUsesPerCustomer != null) {
      payload['max_uses_per_customer'] = maxUsesPerCustomer;
    }
    if (startsAt != null) payload['starts_at'] = startsAt.toUtc().toIso8601String();
    if (endsAt != null) payload['ends_at'] = endsAt.toUtc().toIso8601String();
    if (isActive != null) payload['is_active'] = isActive;

    final res = await _withRetry(() => _dio.patch('/api/admin/vouchers/$voucherId', data: payload, options: _opts()));
    final data = _asMap(res.data);
    return (data['voucher'] as Map?)?.cast<String, dynamic>() ?? data;
  }

  Future<void> deleteVoucher(String voucherId) async {
    await _withRetry(() => _dio.delete('/api/admin/vouchers/$voucherId', options: _opts()));
  }




// -----------------------------
// Reports (used by Staff Reports screen)
  String _date10(DateTime dt) {
    final d = dt.toUtc();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Map<String, dynamic> _jsonMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{'ok': false};
  }

  Future<Map<String, dynamic>> reportsOrdersSummary({required DateTime from, required DateTime to}) async {
    final res = await _withRetry(() => _dio.get(
      '/api/admin/reports/orders/summary',
      queryParameters: {'from': _date10(from), 'to': _date10(to)},
      options: _opts(),
    ));
    return _jsonMap(res.data);
  }

  Future<Map<String, dynamic>> reportsTopCustomers({required DateTime from, required DateTime to, int limit = 25}) async {
    final res = await _withRetry(() => _dio.get(
      '/api/admin/reports/customers/top',
      queryParameters: {'from': _date10(from), 'to': _date10(to), 'limit': limit},
      options: _opts(),
    ));
    return _jsonMap(res.data);
  }

  Future<Map<String, dynamic>> reportsTopItems({required DateTime from, required DateTime to, int limit = 25}) async {
    final res = await _withRetry(() => _dio.get(
      '/api/admin/reports/orders/top_items',
      queryParameters: {'from': _date10(from), 'to': _date10(to), 'limit': limit},
      options: _opts(),
    ));
    return _jsonMap(res.data);
  }

  Future<Map<String, dynamic>> reportsOrdersByDay({required DateTime from, required DateTime to}) async {
    final res = await _withRetry(() => _dio.get(
      '/api/admin/reports/orders/by_day',
      queryParameters: {'from': _date10(from), 'to': _date10(to)},
      options: _opts(),
    ));
    return _jsonMap(res.data);
  }

  Future<Map<String, dynamic>> reportsVoucherPerformance({required DateTime from, required DateTime to}) async {
    final res = await _withRetry(() => _dio.get(
      '/api/admin/reports/vouchers/performance',
      queryParameters: {'from': _date10(from), 'to': _date10(to)},
      options: _opts(),
    ));
    return _jsonMap(res.data);
  }

  Future<Map<String, dynamic>> reportsVouchersSummary({required DateTime from, required DateTime to}) async {
    final res = await _withRetry(() => _dio.get(
      '/api/admin/reports/vouchers/summary',
      queryParameters: {'from': _date10(from), 'to': _date10(to)},
      options: _opts(),
    ));
    return _jsonMap(res.data);
  }

  Future<Map<String, dynamic>> reportsVouchersByCode({required DateTime from, required DateTime to, int limit = 50}) async {
    final res = await _withRetry(() => _dio.get(
      '/api/admin/reports/vouchers/by_code',
      queryParameters: {'from': _date10(from), 'to': _date10(to), 'limit': limit},
      options: _opts(),
    ));
    return _jsonMap(res.data);
  }

  Future<Map<String, dynamic>> reportsCampaigns({required DateTime from, required DateTime to}) async {
    final res = await _withRetry(() => _dio.get(
      '/api/admin/reports/campaigns',
      queryParameters: {'from': _date10(from), 'to': _date10(to)},
      options: _opts(),
    ));
    return _jsonMap(res.data);
  }

  Future<List<int>> exportSummaryXlsx({required DateTime from, required DateTime to}) async {
    final res = await _withRetry(() => _dio.get(
      '/api/admin/reports/export/summary.xlsx',
      queryParameters: {'from': _date10(from), 'to': _date10(to)},
      options: _opts().copyWith(responseType: ResponseType.bytes),
    ));
    return (res.data as List).cast<int>();
  }

  Future<List<int>> exportTopItemsXlsx({required DateTime from, required DateTime to, int limit = 200}) async {
    final res = await _withRetry(() => _dio.get(
      '/api/admin/reports/export/top_items.xlsx',
      queryParameters: {'from': _date10(from), 'to': _date10(to), 'limit': limit},
      options: _opts().copyWith(responseType: ResponseType.bytes),
    ));
    return (res.data as List).cast<int>();
  }

  Future<List<int>> exportVouchersXlsx({required DateTime from, required DateTime to}) async {
    final res = await _withRetry(() => _dio.get(
      '/api/admin/reports/export/vouchers.xlsx',
      queryParameters: {'from': _date10(from), 'to': _date10(to)},
      options: _opts().copyWith(responseType: ResponseType.bytes),
    ));
    return (res.data as List).cast<int>();
  }


Future<Map<String, dynamic>> addVoucherAllowlist({required String voucherId, required List<String> customerKeys}) async {
  final res = await _dio.post(
    '/api/admin/vouchers/$voucherId/allowlist',
    data: {'customerKeys': customerKeys},
    options: _opts(),
  );
  return (res.data is Map<String, dynamic>) ? (res.data as Map<String, dynamic>) : <String, dynamic>{'ok': false};
}

// -----------------------------
// Push (Reports screen buttons only)
Future<Map<String, dynamic>> pushVoucherByCode({required String code, String? title, String? body}) async {
  final res = await _dio.post(
    '/api/admin/push/voucher_by_code',
    data: {'voucherCode': code, 'code': code, 'title': title, 'message': body, 'body': body},
    options: _opts(),
  );
  return (res.data is Map<String, dynamic>) ? (res.data as Map<String, dynamic>) : <String, dynamic>{'ok': false};
}

Future<Map<String, dynamic>> pushSendAll({required String title, required String body}) async {
  final res = await _dio.post(
    '/api/admin/push/broadcast',
    data: {'title': title, 'message': body, 'body': body},
    options: _opts(),
  );
  return (res.data is Map<String, dynamic>) ? (res.data as Map<String, dynamic>) : <String, dynamic>{'ok': false};
}

Future<Map<String, dynamic>> pushSendCustomers({required String title, required String body, required List<String> customerKeys}) async {
  final res = await _dio.post(
    '/api/admin/push/customers',
    data: {'title': title, 'message': body, 'body': body, 'customerKeys': customerKeys},
    options: _opts(),
  );
  return (res.data is Map<String, dynamic>) ? (res.data as Map<String, dynamic>) : <String, dynamic>{'ok': false};
}
}
