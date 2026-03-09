import 'dart:async';
import 'package:flutter/material.dart';

import 'staff_api.dart';
import 'staff_order_view.dart';
import 'staff_menu_control_screen.dart';
import 'staff_vouchers_screen.dart';
import 'order_ringer.dart';
double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  if (s.isEmpty) return 0.0;
  return double.tryParse(s) ?? 0.0;
}

double _orderSubtotal(Map<String, dynamic> o) =>
    _toDouble(o['subtotal_aed'] ?? o['subtotal'] ?? o['sub_total_aed']);

double _orderDelivery(Map<String, dynamic> o) => _toDouble(
    o['delivery_fee_aed'] ?? o['delivery_aed'] ?? o['delivery_fee'] ?? 0);

double _orderVoucherDiscount(Map<String, dynamic> o) => _toDouble(
    o['voucher_discount_aed'] ?? o['discount_aed'] ?? o['voucher_discount'] ?? 0);

double _orderLoyaltyDiscount(Map<String, dynamic> o) =>
    _toDouble(o['loyalty_discount_aed'] ?? o['loyalty_discount'] ?? 0);

double _orderTotal(Map<String, dynamic> o) {
  final subtotal = _orderSubtotal(o);
  final delivery = _orderDelivery(o);
  final voucher = _orderVoucherDiscount(o);
  final loyalty = _orderLoyaltyDiscount(o);
  final serverTotal = _toDouble(o['total_aed'] ?? o['total'] ?? o['total_amount_aed']);
  final computed = (subtotal + delivery - voucher - loyalty);
  if (voucher > 0 || loyalty > 0 || serverTotal <= 0) return computed < 0 ? 0 : computed;
  return serverTotal;
}


class StaffOrdersScreen extends StatefulWidget {
  const StaffOrdersScreen({super.key});

  @override
  State<StaffOrdersScreen> createState() => _StaffOrdersScreenState();
}

class _StaffOrdersScreenState extends State<StaffOrdersScreen> with TickerProviderStateMixin {
  // Branding
  static const Color _headerBg = Color(0xFF111111);
  static const Color _gold = Color(0xFFE0A800);
  static const Color _surface = Color(0xFFFCF8F1);

  late final TabController _tabController;

  // IMPORTANT: set these to your real server + admin key
  // If you already have them elsewhere, replace these with your existing values.
  final StaffApi _api = StaffApi(
    baseUrl: const String.fromEnvironment('API_BASE_URL', defaultValue: 'https://order.handiroti.ae'),
    adminKey: const String.fromEnvironment('ADMIN_KEY', defaultValue: ''),
  );

  bool _loading = true;
  String? _error;

  Timer? _pollTimer;

  List<Map<String, dynamic>> _placed = [];
  List<Map<String, dynamic>> _accepted = [];
  List<Map<String, dynamic>> _preparing = [];
  List<Map<String, dynamic>> _ready = [];
  List<Map<String, dynamic>> _out = [];
  List<Map<String, dynamic>> _delivered = [];
  List<Map<String, dynamic>> _cancelled = [];

  // Ringing
  bool _ringing = false;
  final OrderRinger _ringer = OrderRinger();
  bool _ringerStarted = false;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 10, vsync: this); // + Menu tab
    _loadAll(initial: true);

    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _loadAll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    // Don't dispose the singleton player; just stop it.
    _ringer.stop();
    super.dispose();
  }

  List<Map<String, dynamic>> _sortNewestFirst(List<Map<String, dynamic>> orders) {
    final copy = List<Map<String, dynamic>>.from(orders);
    copy.sort((a, b) {
      final ad = (a['created_at'] ?? a['createdAt'] ?? '').toString();
      final bd = (b['created_at'] ?? b['createdAt'] ?? '').toString();
      return bd.compareTo(ad);
    });
    return copy;
  }

  Future<void> _loadAll({bool initial = false}) async {
    if (initial) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final placed = await _api.listOrders(status: 'placed', limit: 200);
      final accepted = await _api.listOrders(status: 'accepted', limit: 200);
      final preparing = await _api.listOrders(status: 'preparing', limit: 200);
      final ready = await _api.listOrders(status: 'ready', limit: 200);
      final out = await _api.listOrders(status: 'out', limit: 200);
      final delivered = await _api.listOrders(status: 'delivered', limit: 200);
      final cancelled = await _api.listOrders(status: 'cancelled', limit: 200);

      // Ringing if new "placed" exists
      final shouldRing = placed.isNotEmpty;

      if (!mounted) return;
      setState(() {
        _placed = _sortNewestFirst(placed);
        _accepted = _sortNewestFirst(accepted);
        _preparing = _sortNewestFirst(preparing);
        _ready = _sortNewestFirst(ready);
        _out = _sortNewestFirst(out);
        _delivered = _sortNewestFirst(delivered);
        _cancelled = _sortNewestFirst(cancelled);

        _loading = false;
        _error = null;
      });
      await _applyRingingState(shouldRing);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _applyRingingState(bool shouldRing) async {
    // Start/stop the actual audio ringer AND update UI flag.
    if (shouldRing && !_ringerStarted) {
      _ringerStarted = true;
      try {
        await _ringer.start();
      } catch (_) {}
    } else if (!shouldRing && _ringerStarted) {
      _ringerStarted = false;
      try {
        await _ringer.stop();
      } catch (_) {}
    }

    if (!mounted) return;
    if (_ringing != shouldRing) {
      setState(() => _ringing = shouldRing);
    }
  }

  Future<void> _onQuickAction(String orderId, String nextStatus) async {
    try {
      await _api.updateOrderStatus(orderId: orderId, status: nextStatus);
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _openOrder(BuildContext context, String orderId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StaffOrderView(orderId: orderId)),
    );
    await _loadAll();
  }

  Widget _tabLabel(String text, int count) => Tab(text: '$text ($count)');

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(length: 10,
      child: Scaffold(
        backgroundColor: _surface,
        appBar: AppBar(
          backgroundColor: _headerBg,
          foregroundColor: Colors.white,
          title: const Text('Kitchen / Staff Panel'),
          actions: [
            IconButton(
              onPressed: () => _loadAll(initial: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: _gold,
                unselectedLabelColor: Colors.white,
                labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                indicatorColor: _gold,
                indicatorWeight: 3,
                tabs: [
                  _tabLabel('Placed', _placed.length),
                  _tabLabel('Accepted', _accepted.length),
                  _tabLabel('Preparing', _preparing.length),
                  _tabLabel('Ready', _ready.length),
                  _tabLabel('Out', _out.length),
                  _tabLabel('Delivered', _delivered.length),
                  _tabLabel('Cancelled', _cancelled.length),
                  const Tab(text: 'Menu'),
				  const Tab(text: 'Vouchers'),
                  const Tab(text: 'Reports'),

                ],
              ),
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null)
                ? _ErrorView(message: _error!, onRetry: () => _loadAll(initial: true))
                : Column(
                    children: [
                      Container(
                        width: double.infinity,
                        color: const Color(0xFFEDEAE4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(
                          _ringing ? '🔔 New order ringing' : 'No active ringing',
                          style: TextStyle(
                            color: _ringing ? _gold : Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _OrdersList(
                              orders: _placed,
                              emptyText: 'No placed orders',
                              onTapOrder: (id) => _openOrder(context, id),
                              onQuickAction: _onQuickAction,
                            ),
                            _OrdersList(
                              orders: _accepted,
                              emptyText: 'No accepted orders',
                              onTapOrder: (id) => _openOrder(context, id),
                              onQuickAction: _onQuickAction,
                            ),
                            _OrdersList(
                              orders: _preparing,
                              emptyText: 'No preparing orders',
                              onTapOrder: (id) => _openOrder(context, id),
                              onQuickAction: _onQuickAction,
                            ),
                            _OrdersList(
                              orders: _ready,
                              emptyText: 'No ready orders',
                              onTapOrder: (id) => _openOrder(context, id),
                              onQuickAction: _onQuickAction,
                            ),
                            _OrdersList(
                              orders: _out,
                              emptyText: 'No out for delivery orders',
                              onTapOrder: (id) => _openOrder(context, id),
                              onQuickAction: _onQuickAction,
                            ),
                            _OrdersList(
                              orders: _delivered,
                              emptyText: 'No delivered orders',
                              onTapOrder: (id) => _openOrder(context, id),
                              onQuickAction: _onQuickAction,
                              lockDelivered: true,
                            ),
                            _CancelledOrdersList(
                              orders: _cancelled,
                              emptyText: 'No cancelled orders',
                              onTapOrder: (id) => _openOrder(context, id),
                            ),
                            const StaffMenuControlScreen(),
							const StaffVouchersScreen(),
                            const StaffReportsScreen(),

                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  const _OrdersList({
    required this.orders,
    required this.emptyText,
    required this.onTapOrder,
    required this.onQuickAction,
    this.lockDelivered = false,
  });

  final List<Map<String, dynamic>> orders;
  final String emptyText;
  final void Function(String orderId) onTapOrder;
  final void Function(String orderId, String nextStatus) onQuickAction;
  final bool lockDelivered;

  static const Color _gold = Color(0xFFE0A800);

  String _str(Map<String, dynamic> o, String key) => (o[key] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(child: Text(emptyText));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final o = orders[i];
        final id = _str(o, 'id');
        final customer = _str(o, 'customer_name');
        final phone = _str(o, 'customer_phone');
        final area = _str(o, 'area');
        final payment = _str(o, 'payment_method');
        final totalAed = _orderTotal(o).toStringAsFixed(2);

        return InkWell(
          onTap: () => onTapOrder(id),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2D6C7)),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 10,
                  offset: Offset(0, 6),
                  color: Color(0x14000000),
                ),
              ],
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.receipt_long, size: 28, color: Color(0xFF444444)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.isEmpty ? 'Customer' : customer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        phone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${area.isEmpty ? '-' : area} • ${payment.isEmpty ? '-' : payment}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'AED $totalAed',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    if (!lockDelivered) _QuickButtons(status: _str(o, 'status'), onQuickAction: (s) => onQuickAction(id, s)),
                    if (lockDelivered)
                      const SizedBox(
                        height: 36,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text('Delivered', style: TextStyle(color: _gold, fontWeight: FontWeight.w800)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuickButtons extends StatelessWidget {
  const _QuickButtons({
    required this.status,
    required this.onQuickAction,
  });

  final String status;
  final void Function(String nextStatus) onQuickAction;

  static const Color _gold = Color(0xFFE0A800);

  @override
  Widget build(BuildContext context) {
    // Small, non-overflowing buttons: fixed height + tight padding.
    Widget btn(String label, String next) {
      return SizedBox(
        height: 34,
        child: OutlinedButton(
          onPressed: () => onQuickAction(next),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            side: BorderSide(color: _gold.withOpacity(0.55)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    // Two buttons max to keep it neat
    if (status == 'placed') {
      return Row(mainAxisSize: MainAxisSize.min, children: [btn('Accept', 'accepted'), const SizedBox(width: 8), btn('Cancel', 'cancelled')]);
    }
    if (status == 'accepted') {
      return Row(mainAxisSize: MainAxisSize.min, children: [btn('Preparing', 'preparing'), const SizedBox(width: 8), btn('Cancel', 'cancelled')]);
    }
    if (status == 'preparing') {
      return Row(mainAxisSize: MainAxisSize.min, children: [btn('Ready', 'ready'), const SizedBox(width: 8), btn('Cancel', 'cancelled')]);
    }
    if (status == 'ready') {
      return Row(mainAxisSize: MainAxisSize.min, children: [btn('Out', 'out'), const SizedBox(width: 8), btn('Cancel', 'cancelled')]);
    }
    if (status == 'out') {
      return Row(mainAxisSize: MainAxisSize.min, children: [btn('Delivered', 'delivered'), const SizedBox(width: 8), btn('Cancel', 'cancelled')]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [btn('Cancel', 'cancelled')]);
  }
}

class _CancelledOrdersList extends StatelessWidget {
  const _CancelledOrdersList({
    required this.orders,
    required this.emptyText,
    required this.onTapOrder,
  });

  final List<Map<String, dynamic>> orders;
  final String emptyText;
  final void Function(String orderId) onTapOrder;

  String _str(Map<String, dynamic> o, String key) => (o[key] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(child: Text(emptyText));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final o = orders[i];
        final id = _str(o, 'id');
        final customer = _str(o, 'customer_name');
        final phone = _str(o, 'customer_phone');
        final note = _str(o, 'cancel_note');

        return InkWell(
          onTap: () => onTapOrder(id),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2D6C7)),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.isEmpty ? 'Customer' : customer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(phone, style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 6),
                      Text(
                        note.isEmpty ? '—' : note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// TEMP placeholder Reports screen.
/// Your current lib/features/staff/staff_reports_screen.dart file appears to define
/// StaffMenuControlScreen instead of StaffReportsScreen (likely overwritten).
/// Upload the correct StaffReportsScreen file and I'll restore it fully.
class StaffReportsScreen extends StatelessWidget {
  const StaffReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Reports screen is temporarily unavailable because the reports file is missing/overwritten.\n\n'
            'Please upload your correct staff_reports_screen.dart (the one that defines StaffReportsScreen) '
            'and I will restore it without breaking anything.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
