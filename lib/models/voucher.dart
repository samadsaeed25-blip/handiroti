// lib/models/voucher.dart
class Voucher {
  final String id;
  final String code;
  final String kind; // flat | percent
  final num amount;
  final num? maxDiscountAed;
  final num minSubtotalAed;
  final int? maxUsesTotal;
  final int? maxUsesPerCustomer;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;

  Voucher({
    required this.id,
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

  static num _toNum(dynamic v, {num fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? fallback;
    return fallback;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static DateTime? _toDt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory Voucher.fromJson(Map<String, dynamic> j) => Voucher(
        id: (j['id'] ?? '').toString(),
        code: (j['code'] ?? '').toString(),
        kind: (j['kind'] ?? '').toString(),
        amount: _toNum(j['amount']),
        maxDiscountAed: j['max_discount_aed'] == null ? null : _toNum(j['max_discount_aed']),
        minSubtotalAed: _toNum(j['min_subtotal_aed']),
        maxUsesTotal: _toInt(j['max_uses_total']),
        maxUsesPerCustomer: _toInt(j['max_uses_per_customer']),
        startsAt: _toDt(j['starts_at']),
        endsAt: _toDt(j['ends_at']),
        isActive: (j['is_active'] is bool) ? j['is_active'] as bool : (j['is_active']?.toString() == 'true'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'kind': kind,
        'amount': amount,
        'max_discount_aed': maxDiscountAed,
        'min_subtotal_aed': minSubtotalAed,
        'max_uses_total': maxUsesTotal,
        'max_uses_per_customer': maxUsesPerCustomer,
        'starts_at': startsAt?.toIso8601String(),
        'ends_at': endsAt?.toIso8601String(),
        'is_active': isActive,
      };

  String get labelKind => kind == 'percent' ? 'Percent' : 'Flat (AED)';
}
