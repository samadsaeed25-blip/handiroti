import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'cart_models.dart';

final cartProvider = NotifierProvider<CartNotifier, List<CartLine>>(CartNotifier.new);

class CartNotifier extends Notifier<List<CartLine>> {
  @override
  List<CartLine> build() => const [];

  void addLine({
    required String itemId,
    required String itemName,
    required String variantId,
    required String variantName,
    required double unitPriceAed,
    int qty = 1,
  }) {
    final idx = state.indexWhere((l) => l.variantId == variantId);
    if (idx >= 0) {
      final current = state[idx];
      final updated = current.copyWith(qty: current.qty + qty);
      state = [
        ...state.sublist(0, idx),
        updated,
        ...state.sublist(idx + 1),
      ];
    } else {
      state = [
        ...state,
        CartLine(
          itemId: itemId,
          itemName: itemName,
          variantId: variantId,
          variantName: variantName,
          unitPriceAed: unitPriceAed,
          qty: qty,
        ),
      ];
    }
  }

  void decLine(String variantId) {
    final idx = state.indexWhere((l) => l.variantId == variantId);
    if (idx < 0) return;
    final current = state[idx];
    if (current.qty <= 1) {
      removeLine(variantId);
      return;
    }
    final updated = current.copyWith(qty: current.qty - 1);
    state = [
      ...state.sublist(0, idx),
      updated,
      ...state.sublist(idx + 1),
    ];
  }

  void removeLine(String variantId) {
    state = state.where((l) => l.variantId != variantId).toList(growable: false);
  }

  void clear() => state = const [];

  int get itemCount => state.fold<int>(0, (sum, l) => sum + l.qty);

  double get totalAed => state.fold<double>(0, (sum, l) => sum + l.lineTotal);
}

final cartCountProvider = Provider<int>((ref) {
  final lines = ref.watch(cartProvider);
  return lines.fold<int>(0, (sum, l) => sum + l.qty);
});

final cartTotalProvider = Provider<double>((ref) {
  final lines = ref.watch(cartProvider);
  return lines.fold<double>(0, (sum, l) => sum + l.lineTotal);
});
