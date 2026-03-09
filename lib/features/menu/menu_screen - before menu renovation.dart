import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/phone_auth_screen.dart';
import '../cart/cart_provider.dart';
import '../cart/cart_sheet.dart';
import '../orders/order_history_screen.dart';
import '../checkout/offers_screen.dart';

import 'dart:async';
import '../staff/staff_login_screen.dart';

import '../../core/api/api_client.dart';
import 'menu_models.dart';

final menuProvider = FutureProvider<MenuResponse>((ref) async {
  final res = await ApiClient.dio.get('/api/menu');
  return MenuResponse.fromJson(res.data as Map<String, dynamic>);
});

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  bool _guestMode = false;

  bool get _isLoggedIn => FirebaseAuth.instance.currentUser != null;

  @override
  void initState() {
    super.initState();
    // Rebuild automatically when auth state changes (login/logout)
    FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _openLogin() async {
    final nav = Navigator.of(context, rootNavigator: true);
    final ok = await nav.push<bool>(
      MaterialPageRoute(
        builder: (_) => const PhoneAuthScreen(defaultCountryCode: "+971"),
      ),
    );

    if (ok == true && FirebaseAuth.instance.currentUser != null) {
      if (!mounted) return;
      setState(() => _guestMode = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logged in successfully')),
      );
    }
  }

  Future<void> _logout() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Do you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (sure != true) return;

    await FirebaseAuth.instance.signOut();
    if (!mounted) return;

    setState(() => _guestMode = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logged out')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final menuAsync = ref.watch(menuProvider);

    final cartCount = ref.watch(cartCountProvider);
    final cartTotal = ref.watch(cartTotalProvider);

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: _HoldToStaff(
          child: const Text('Handi Roti', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.2)),
        ),
        centerTitle: true,
        actions: [
          // My Orders (only when logged in)
          if (_isLoggedIn)
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
                );
              },
              icon: const Icon(Icons.receipt_long_rounded),
              tooltip: 'My Orders',
            ),

          // Offers
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OffersScreen(
                    phone: _isLoggedIn ? FirebaseAuth.instance.currentUser?.phoneNumber : null,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.local_offer_outlined),
            tooltip: 'Offers',
          ),

          // Login / Logout toggle
          if (_isLoggedIn)
            IconButton(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Logout',
            )
          else
            IconButton(
              onPressed: _openLogin,
              icon: const Icon(Icons.login_rounded),
              tooltip: 'Login',
            ),

          IconButton(
            onPressed: () => ref.refresh(menuProvider),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            menuAsync.when(
              loading: () => const _Loading(),
              error: (e, _) => _ErrorState(
                error: e.toString(),
                onRetry: () => ref.refresh(menuProvider),
              ),
              data: (data) {
                final categories = data.menu.where((c) => c.isActive).toList()
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

                return ListView(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
                  children: [
                    const _BrandHeader(),
                    const SizedBox(height: 12),
                    Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _GlassHero(
                      title: 'Order in minutes',
                      subtitle: 'Premium taste delivered in\nRas Al Khaimah',
                      leadingAsset: 'assets/branding/handiroti_scooter.png',
                      glow: cs.primary.withOpacity(0.12),
                    ),
                  ),
                    const SizedBox(height: 14),
                    for (final cat in categories) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          cat.name,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.1,
                                color: const Color(0xFFD1AE63),
                              ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (cat.items.where((i) => i.isActive).isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'No items yet',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      for (final item in cat.items.where((i) => i.isActive))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: _MenuItemCard(
                            name: item.name,
                            desc: (item.description ?? '').trim().isEmpty
                                ? ' '
                                : item.description!,
                            price: _fromPriceLabel(item),
                            imageUrl: item.imageUrl,
                            onAdd: () => _pickVariant(context, ref, item),
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ],
                );
              },
            ),

            // Welcome / Guest overlay (only when logged out and guest not chosen)
            if (!_isLoggedIn && !_guestMode)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.35),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            width: 520,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.92),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.65)),
                              boxShadow: const [
                                BoxShadow(
                                  blurRadius: 22,
                                  offset: Offset(0, 12),
                                  color: Color(0x22000000),
                                )
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        color: cs.primary.withOpacity(0.10),
                                      ),
                                      child: Icon(Icons.restaurant_menu_rounded, color: cs.primary),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'Welcome to Handi Roti',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Explore the menu as a guest.\nLogin is required only when placing an order.',
                                  style: TextStyle(color: Colors.black.withOpacity(0.65)),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => setState(() => _guestMode = true),
                                        child: const Text('Continue as Guest'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: _openLogin,
                                        child: const Text('Login with Phone'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'You will still be asked to login at checkout if you continue as guest.',
                                  style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: _FloatingCartBar(
        total: 'AED ${cartTotal.toStringAsFixed(2)}',
        count: cartCount,
        onTap: () => CartSheet.show(context),
      ),
    );
  }
}


String _fromPriceLabel(MenuItem item) {
  final active = item.variants.where((v) => v.isActive).toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  if (active.isEmpty) return 'Price unavailable';

  double min = double.tryParse(active.first.priceAed) ?? 0;
  for (final v in active) {
    final p = double.tryParse(v.priceAed) ?? min;
    if (p < min) min = p;
  }
  return 'From AED ${min.toStringAsFixed(0)}';
}

Future<void> _pickVariant(BuildContext context, WidgetRef ref, MenuItem item) async {
  final variants = item.variants.where((v) => v.isActive).toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  if (variants.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No active variants for this item yet.')),
    );
    return;
  }

  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white.withOpacity(0.96),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(item.description ?? '',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 14),
              for (final v in variants)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(v.name,
                      style: Theme.of(context).textTheme.bodyLarge),
                  subtitle: Text('AED ${v.priceAed}',
                      style: Theme.of(context).textTheme.bodySmall),
                  trailing: FilledButton(
                    onPressed: () {
                      final price = double.tryParse(v.priceAed) ?? 0.0;

                      ref.read(cartProvider.notifier).addLine(
                        itemId: item.id,
                        itemName: item.name,
                        variantId: v.id,
                        variantName: v.name,
                        unitPriceAed: price,
                        qty: 1,
                      );

                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Added: ${item.name} • ${v.name}'),
                        ),
                      );
                    },
                    child: const Text('Add'),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load menu',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(error,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}


class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    // Full-width premium dark hero (professional)
    return Container(
      height: 270,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF19171D),
            Color(0xFF0F0E13),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Subtle warm glows
          Positioned(
            top: -140,
            left: -120,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFD9B15F).withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -180,
            right: -140,
            child: Container(
              width: 420,
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFFB300).withOpacity(0.06),
              ),
            ),
          ),
          Center(
            child: Image.asset(
              'assets/branding/handiroti_logo.png',
              height: 175,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}


class _GlassHero extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData? icon;
  final String? leadingAsset;
  final Color glow;

  const _GlassHero({
    required this.title,
    required this.subtitle,
    this.icon,
    this.leadingAsset,
    required this.glow,
  }) : assert(icon != null || leadingAsset != null);

  @override
  Widget build(BuildContext context) {
    // More "premium card" than glassy blur (professional)
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 10),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF6EEE7),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE9DDD4)),
          ),
          child: Row(
            children: [
              if (leadingAsset != null)
                SizedBox(
                  width: 92,
                  height: 58,
                  child: Image.asset(
                    leadingAsset!,
                    fit: BoxFit.contain,
                  ),
                )
              else
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: glow.withOpacity(0.22),
                  ),
                  child: Icon(icon!, size: 22),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.1,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.25,
                            color: const Color(0xFF6B7280),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _MenuItemCard extends StatelessWidget {
  final String name;
  final String desc;
  final String? imageUrl;
  final String price;
  final VoidCallback onAdd;

  const _MenuItemCard({
    required this.name,
    required this.desc,
    required this.imageUrl,
    required this.price,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD6A21A);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F3),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE9DDD4)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 10),
            color: Color(0x12000000),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: const Color(0xFFF1F3F6),
              ),
              clipBehavior: Clip.antiAlias,
              child: (imageUrl == null || imageUrl!.trim().isEmpty)
                  ? const Icon(Icons.restaurant_rounded, size: 30, color: Color(0xFF111827))
                  : Image.network(
                      imageUrl!.trim(),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.restaurant_rounded, size: 30, color: Color(0xFF111827)),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                          height: 1.15,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    desc,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.25,
                          color: const Color(0xFF6B7280),
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3DEB8),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      price,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF111827),
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: onAdd,
                style: ElevatedButton.styleFrom(
                  backgroundColor: gold,
                  foregroundColor: const Color(0xFF111827),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text(
                  'Add',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _FloatingCartBar extends StatelessWidget {
  final String total;
  final int count;
  final VoidCallback onTap;

  const _FloatingCartBar({
    required this.total,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).dividerColor;
    final bool disabled = count <= 0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: GestureDetector(
          onTap: disabled ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.94),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 16,
                  offset: Offset(0, 10),
                  color: Color(0x10000000),
                )
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFFF2F4F7),
                  ),
                  child: const Icon(Icons.shopping_bag_outlined, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    count == 0 ? 'Your cart is empty' : '$count item(s) • $total',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _HoldToStaff extends StatefulWidget {
  final Widget child;
  const _HoldToStaff({required this.child});

  @override
  State<_HoldToStaff> createState() => _HoldToStaffState();
}

class _HoldToStaffState extends State<_HoldToStaff> {
  Timer? _timer;

  void _startHold() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const StaffLoginScreen()),
      );
    });
  }

  void _cancelHold() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _startHold(),
      onTapUp: (_) => _cancelHold(),
      onTapCancel: _cancelHold,
      child: widget.child,
    );
  }
}
