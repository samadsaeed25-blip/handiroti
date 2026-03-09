class CartLine {
  final String itemId;
  final String itemName;
  final String variantId;
  final String variantName;

  /// Unit price in AED (numeric, safe for calculations).
  final double unitPriceAed;

  final int qty;

  const CartLine({
    required this.itemId,
    required this.itemName,
    required this.variantId,
    required this.variantName,
    required this.unitPriceAed,
    required this.qty,
  });

  /// Unique key per cart line (variant is unique per line).
  String get key => variantId;

  /// Backward/forward compatible aliases used by older/newer UI code.
  /// Some screens expect `priceAed`, others `unitPriceAed`.
  double get priceAed => unitPriceAed;

  /// Formatted helper (e.g., "22.00") for display.
  String get priceAedText => unitPriceAed.toStringAsFixed(2);

  CartLine copyWith({int? qty}) => CartLine(
        itemId: itemId,
        itemName: itemName,
        variantId: variantId,
        variantName: variantName,
        unitPriceAed: unitPriceAed,
        qty: qty ?? this.qty,
      );

  double get lineTotal => unitPriceAed * qty;
}
