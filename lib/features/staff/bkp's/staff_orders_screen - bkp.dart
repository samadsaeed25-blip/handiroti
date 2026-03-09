import 'dart:async';

import 'package:flutter/material.dart';

import 'order_ringer.dart';
import 'staff_api.dart';
import 'staff_order_view.dart';

class StaffOrdersScreen extends StatefulWidget {
  const StaffOrdersScreen({super.key});

  @override
  State<StaffOrdersScreen> createState() => _StaffOrdersScreenState();
}

class _StaffOrdersScreenState extends State<StaffOrdersScreen>
    with SingleTickerProviderStateMixin {
  final _api = StaffApi();
  final _ringer = OrderRinger();

  Timer? _timer;
  bool _loading = true;
  String? _error;

  late final TabController _tabController;

  // Status buckets
  List<Map<String, dynamic>> _placed = [];
  List<Map<String, dynamic>> _accepted = [];
  List<Map<String, dynamic>> _preparing = [];
  List<Map<String, dynamic>> _ready = [];
  List<Map<String, dynamic>> _out = [];
  List<Map<String, dynamic>> _delivered = [];

  // Ring logic
  final Set<String> _seenPlacedIds = {};
  String? _ringingOrderId;
  Map<String, dynamic>? _ringingOrder; // snapshot of the newest order

  bool _popupOpen = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _fetchAll();
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _fetchAll(silent: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ringer.dispose();
    _tabController.dispose();
    super.dispose();
  }

  String _idOf(Map<String, dynamic> o) => (o['id'] ?? '').toString();

  DateTime _placedAtOf(Map<String, dynamic> o) {
    final s = (o['placed_at'] ?? '').toString();
    return DateTime.tryParse(s)?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  List<Map<String, dynamic>> _sortNewestFirst(List<Map<String, dynamic>> list) {
    list.sort((a, b) => _placedAtOf(b).compareTo(_placedAtOf(a)));
    return list;
  }

  Future<void> _fetchAll({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);

    try {
      // Fetch all statuses for tabs
      final placed = await _api.listOrders(status: 'placed', limit: 100);
      final accepted = await _api.listOrders(status: 'accepted', limit: 100);
      final preparing = await _api.listOrders(status: 'preparing', limit: 100);
      final ready = await _api.listOrders(status: 'ready', limit: 100);
      final out = await _api.listOrders(status: 'out_for_delivery', limit: 100);
      final delivered = await _api.listOrders(status: 'delivered', limit: 100);

      // Detect NEW placed orders
      bool hasNewPlaced = false;
      for (final o in placed) {
        final id = _idOf(o);
        if (id.isEmpty) continue;
        if (!_seenPlacedIds.contains(id)) {
          hasNewPlaced = true;
          _seenPlacedIds.add(id);
        }
      }

      _placed = _sortNewestFirst(placed);
      _accepted = _sortNewestFirst(accepted);
      _preparing = _sortNewestFirst(preparing);
      _ready = _sortNewestFirst(ready);
      _out = _sortNewestFirst(out);
      _delivered = _sortNewestFirst(delivered);

      // Ring logic:
      // - Keep ringing while _ringingOrderId still exists in placed
      // - If no active ringing and a NEW placed appears, ring for newest placed (and popup)
      final placedIds = _placed.map(_idOf).toSet();
      final stillPlaced =
          _ringingOrderId != null && placedIds.contains(_ringingOrderId);

      if (stillPlaced) {
        await _ringer.start();
        if (!_popupOpen) {
          _schedulePopupIfNeeded();
        }
      } else {
        _ringingOrderId = null;
        _ringingOrder = null;
        await _ringer.stop();
        _closePopupIfOpen();

        if (hasNewPlaced && _placed.isNotEmpty) {
          _ringingOrderId = _idOf(_placed.first);
          _ringingOrder = _placed.first;

          await _ringer.start();

          if (_tabController.index != 0) {
            _tabController.animateTo(0);
          }

          _schedulePopupIfNeeded();
        }
      }

      _error = null;
    } catch (e) {
      _error = e.toString();
      await _ringer.stop();
      _ringingOrderId = null;
      _ringingOrder = null;
      _closePopupIfOpen();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _schedulePopupIfNeeded() {
    if (_popupOpen) return;
    if (_ringingOrderId == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_popupOpen) return;
      if (_ringingOrderId == null) return;
      _showNewOrderPopup();
    });
  }

  void _closePopupIfOpen() {
    if (!_popupOpen) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    _popupOpen = false;
  }

  Future<void> _showNewOrderPopup() async {
    if (_popupOpen) return;
    if (_ringingOrderId == null) return;

    _popupOpen = true;

    final o = _ringingOrder;
    final id = _ringingOrderId ?? '';
    final name = (o?['customer_name'] ?? 'Customer').toString();
    final phone = (o?['customer_phone'] ?? '').toString();
    final area = (o?['area'] ?? '').toString();
    final total = (o?['total_aed'] ?? '').toString();
    final pay = (o?['payment_method'] ?? '').toString();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.black.withOpacity(0.65),
          child: SafeArea(
            child: Container(
              width: double.infinity,
              height: double.infinity,
              padding: const EdgeInsets.all(18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 28,
                          offset: Offset(0, 16),
                          color: Color(0x33000000),
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.notifications_active_rounded,
                          size: 56,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'NEW ORDER RECEIVED',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Please accept to stop the ringing',
                          style:
                              TextStyle(color: Colors.black.withOpacity(0.65)),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        _kv('Customer', name),
                        if (phone.isNotEmpty) _kv('Phone', phone),
                        _kv('Area', area.isNotEmpty ? area : 'RAK'),
                        _kv('Payment', pay),
                        _kv('Total', 'AED $total'),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  // Close ONLY the dialog (not the whole staff screen)
                                  Navigator.of(dialogContext).pop();
                                  _popupOpen = false;
                                  await _openOrder(id);
                                },
                                icon: const Icon(Icons.receipt_long_rounded),
                                label: const Text('View Details'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () async {
                                  await _setStatus(id, 'accepted');
                                  if (!mounted) return;
                                  // Close ONLY the dialog (not the whole staff screen)
                                  Navigator.of(dialogContext).pop();
                                  _popupOpen = false;
                                },
                                icon: const Icon(Icons.check_circle_rounded),
                                label: const Text('ACCEPT'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (mounted) _popupOpen = false;
  }

  static Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              k,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black.withOpacity(0.75),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  Future<void> _setStatus(String id, String status, {String? note}) async {
    try {
      await _api.updateStatus(orderId: id, status: status, note: note);

      if (status == 'accepted' && _ringingOrderId == id) {
        _ringingOrderId = null;
        _ringingOrder = null;
        await _ringer.stop();
        _closePopupIfOpen();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status updated: $status')),
      );
      await _fetchAll(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    }
  }

  Future<void> _cancelOrder(String orderId) async {
    final note = await _askCancelReason();
    if (note == null) return;

    await _setStatus(orderId, 'cancelled', note: note);

    // If we cancelled the ringing order, stop ringing
    if (_ringingOrderId == orderId) {
      _ringingOrderId = null;
      _ringingOrder = null;
      await _ringer.stop();
      _closePopupIfOpen();
    }
  }

  Future<String?> _askCancelReason() async {
    final c = TextEditingController(
        text: 'Customer requested change. Please re-order.');

    final res = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel order?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This will cancel the order. Customer must place a new order.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason / Note',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(c.text.trim()),
              child: const Text('Yes, Cancel'),
            ),
          ],
        );
      },
    );

    c.dispose();
    if (res == null) return null;
    if (res.trim().isEmpty) return 'Cancelled by staff.';
    return res.trim();
  }

  Future<void> _openOrder(String orderId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StaffOrderView(orderId: orderId)),
    );
    await _fetchAll(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final ringingNote = _ringingOrderId == null
        ? 'No active ringing'
        : 'Ringing until accepted: $_ringingOrderId';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitchen / Staff Panel'),
        actions: [
          IconButton(
            onPressed: () => _fetchAll(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: 'Placed (${_placed.length})'),
            Tab(text: 'Accepted (${_accepted.length})'),
            Tab(text: 'Preparing (${_preparing.length})'),
            Tab(text: 'Ready (${_ready.length})'),
            Tab(text: 'Out (${_out.length})'),
            Tab(text: 'Delivered (${_delivered.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: Colors.black.withOpacity(0.04),
            child: Text(
              ringingNote,
              style: TextStyle(
                fontSize: 12,
                color: Colors.black.withOpacity(0.7),
              ),
            ),
          ),
          Expanded(
            child: _loading &&
                    _placed.isEmpty &&
                    _accepted.isEmpty &&
                    _preparing.isEmpty &&
                    _ready.isEmpty &&
                    _out.isEmpty &&
                    _delivered.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null &&
                        _placed.isEmpty &&
                        _accepted.isEmpty &&
                        _preparing.isEmpty &&
                        _ready.isEmpty &&
                        _out.isEmpty &&
                        _delivered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _fetchAll,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          // Placed: Accept + Cancel
                          _OrdersList(
                            label: 'Placed',
                            orders: _placed,
                            ringingOrderId: _ringingOrderId,
                            primaryActionLabel: 'Accept',
                            onPrimaryAction: (id) => _setStatus(id, 'accepted'),
                            secondaryActionLabel: 'Cancel',
                            onSecondaryAction: _cancelOrder,
                            onTapOrder: _openOrder,
                          ),

                          // Accepted
                          _OrdersList(
                            label: 'Accepted',
                            orders: _accepted,
                            onTapOrder: _openOrder,
                            quickActions: const [
                              _QuickAction('Preparing', 'preparing'),
                            ],
                            onQuickAction: _setStatus,
                            secondaryActionLabel: 'Cancel',
                            onSecondaryAction: _cancelOrder,
                          ),

                          // Preparing
                          _OrdersList(
                            label: 'Preparing',
                            orders: _preparing,
                            onTapOrder: _openOrder,
                            quickActions: const [
                              _QuickAction('Ready', 'ready'),
                            ],
                            onQuickAction: _setStatus,
                            secondaryActionLabel: 'Cancel',
                            onSecondaryAction: _cancelOrder,
                          ),

                          // Ready
                          _OrdersList(
                            label: 'Ready',
                            orders: _ready,
                            onTapOrder: _openOrder,
                            quickActions: const [
                              _QuickAction('Out', 'out_for_delivery'),
                            ],
                            onQuickAction: _setStatus,
                            secondaryActionLabel: 'Cancel',
                            onSecondaryAction: _cancelOrder,
                          ),

                          // Out
                          _OrdersList(
                            label: 'Out',
                            orders: _out,
                            onTapOrder: _openOrder,
                            quickActions: const [
                              _QuickAction('Delivered', 'delivered'),
                            ],
                            onQuickAction: _setStatus,
                            secondaryActionLabel: 'Cancel',
                            onSecondaryAction: _cancelOrder,
                          ),

                          // Delivered: no actions
                          _OrdersList(
                            label: 'Delivered',
                            orders: _delivered,
                            onTapOrder: _openOrder,
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction {
  final String label;
  final String status;
  const _QuickAction(this.label, this.status);
}

class _OrdersList extends StatelessWidget {
  final String label;
  final List<Map<String, dynamic>> orders;

  final String? ringingOrderId;

  final String? primaryActionLabel;
  final void Function(String id)? onPrimaryAction;

  final String? secondaryActionLabel;
  final void Function(String id)? onSecondaryAction;

  final List<_QuickAction> quickActions;
  final void Function(String id, String status, {String? note})? onQuickAction;

  final void Function(String orderId) onTapOrder;

  const _OrdersList({
    required this.label,
    required this.orders,
    required this.onTapOrder,
    this.ringingOrderId,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.quickActions = const [],
    this.onQuickAction,
  });

  String _idOf(Map<String, dynamic> o) => (o['id'] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(child: Text('No $label orders'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final o = orders[i];
        final id = _idOf(o);
        final name = (o['customer_name'] ?? 'Customer').toString();
        final phone = (o['customer_phone'] ?? '').toString();
        final area = (o['area'] ?? '').toString();
        final total = (o['total_aed'] ?? '').toString();
        final pay = (o['payment_method'] ?? '').toString();

        final isRingingOne = ringingOrderId != null && ringingOrderId == id;

        return Card(
          child: ListTile(
            leading: isRingingOne
                ? const Icon(Icons.notifications_active_rounded)
                : const Icon(Icons.receipt_long_rounded),
            title: Text('$name  ${phone.isNotEmpty ? "• $phone" : ""}'),
            subtitle: Text('${area.isNotEmpty ? area : "RAK"} • $pay'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('AED $total',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                if (primaryActionLabel != null && onPrimaryAction != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 32,
                        child: FilledButton(
                          onPressed: () => onPrimaryAction!(id),
                          child: Text(primaryActionLabel!),
                        ),
                      ),
                      if (secondaryActionLabel != null &&
                          onSecondaryAction != null) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 32,
                          child: OutlinedButton(
                            onPressed: () => onSecondaryAction!(id),
                            child: Text(secondaryActionLabel!),
                          ),
                        ),
                      ]
                    ],
                  )
                else if (quickActions.isNotEmpty && onQuickAction != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final qa in quickActions) ...[
                        SizedBox(
                          height: 32,
                          child: OutlinedButton(
                            onPressed: () => onQuickAction!(id, qa.status),
                            child: Text(qa.label),
                          ),
                        ),
                      ],
                      if (secondaryActionLabel != null &&
                          onSecondaryAction != null) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 32,
                          child: OutlinedButton(
                            onPressed: () => onSecondaryAction!(id),
                            child: Text(secondaryActionLabel!),
                          ),
                        ),
                      ]
                    ],
                  ),
              ],
            ),
            onTap: () => onTapOrder(id),
          ),
        );
      },
    );
  }
}
