import 'package:flutter/material.dart';


class OrderSuccessScreen extends StatelessWidget {
  final String orderId;
  final String totalAed;
  final String? etaText;

  const OrderSuccessScreen({
    super.key,
    required this.orderId,
    required this.totalAed,
    this.etaText,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.88),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 62),
                  const SizedBox(height: 10),
                  Text(
                    'Order Placed',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Thank you for ordering from Handi Roti.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),

                  _Row(label: 'Order ID', value: orderId),
                  _Row(label: 'Total', value: 'AED $totalAed'),
                  if (etaText != null && etaText!.trim().isNotEmpty)
                    _Row(label: 'ETA', value: etaText!),

                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Back to Menu'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
