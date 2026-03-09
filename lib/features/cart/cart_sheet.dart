import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/phone_auth_screen.dart';
import '../cart/cart_models.dart';
import '../cart/cart_provider.dart';
import '../checkout/checkout_screen.dart';

import '../../services/push_service.dart';

class CartSheet extends ConsumerWidget {
  const CartSheet({super.key});

  static Future<void> show(BuildContext context) async {
    // Backward-compatible alias: older code calls CartSheet.show(context)
    await open(context);
  }

  static Future<void> open(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CartSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);

    final mq = MediaQuery.of(context);
    final bottomPad = mq.viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: _GlassContainer(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: mq.size.height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text(
                        'Your Cart',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      if (lines.isNotEmpty)
                        TextButton(
                          onPressed: () => ref.read(cartProvider.notifier).clear(),
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: lines.isEmpty
                      ? const _EmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          itemCount: lines.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _LineTile(line: lines[i]),
                        ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      _RowKV(
                        label: 'Subtotal',
                        value: 'AED ${total.toStringAsFixed(2)}',
                        bold: true,
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: lines.isEmpty
                              ? null
                              : () async {
                                  // IMPORTANT: after pop(), this widget's BuildContext
                                  // can get disposed. Grab the *root* navigator first.
                                  final nav = Navigator.of(context, rootNavigator: true);
                                  nav.pop();

                                  // Let the sheet close cleanly
                                  await Future.delayed(const Duration(milliseconds: 50));

                                  // 1) If not logged-in → OTP Login (only at checkout)
                                  if (FirebaseAuth.instance.currentUser == null) {
                                    final ok = await nav.push<bool>(
                                      MaterialPageRoute(
                                        builder: (_) => const PhoneAuthScreen(
                                          defaultCountryCode: "+971",
                                        ),
                                      ),
                                    );

                                    // User backed out or login failed
                                    if (ok != true || FirebaseAuth.instance.currentUser == null) {
                                      return;
                                    }
                                  }

                                  // ✅ Register device for push notifications (best-effort; never blocks checkout)
                                  try {
                                    await PushService.registerFromFirebaseUser();
                                  } catch (_) {
                                    // ignore - push is optional
                                  }

                                  // 2) Now go to checkout
                                  nav.push(
                                    MaterialPageRoute(
                                      builder: (_) => const CheckoutScreen(),
                                    ),
                                  );
                                },
                          child: const Text('Proceed to Checkout'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LineTile extends ConsumerWidget {
  final CartLine line;
  const _LineTile({required this.line});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cartProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.restaurant_menu_rounded, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.itemName, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  line.variantName,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withOpacity(0.55),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'AED ${line.unitPriceAed.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 8),

                // Remove line (your provider expects String variantId)
                TextButton.icon(
                  onPressed: () => notifier.removeLine(line.variantId),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              _QtyStepper(
                qty: line.qty,
                onMinus: () => notifier.decLine(line.variantId),
                onPlus: () => notifier.addLine(
                  itemId: line.itemId,
                  itemName: line.itemName,
                  variantId: line.variantId,
                  variantName: line.variantName,
                  unitPriceAed: line.unitPriceAed,
                  qty: 1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'AED ${line.lineTotal.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _QtyStepper({
    required this.qty,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onMinus,
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          Text('$qty', style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onPlus,
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_bag_outlined, size: 48, color: Colors.black.withOpacity(0.35)),
            const SizedBox(height: 10),
            Text(
              'Your cart is empty',
              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black.withOpacity(0.75)),
            ),
            const SizedBox(height: 4),
            Text(
              'Add items from the menu to place an order.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black.withOpacity(0.55)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowKV extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _RowKV({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      color: Colors.black.withOpacity(0.82),
    );
    return Row(
      children: [
        Text(label, style: style),
        const Spacer(),
        Text(value, style: style),
      ],
    );
  }
}

class _GlassContainer extends StatelessWidget {
  final Widget child;
  const _GlassContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.78),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: Colors.white.withOpacity(0.55)),
          ),
          child: child,
        ),
      ),
    );
  }
}