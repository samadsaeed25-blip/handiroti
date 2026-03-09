import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'staff_config.dart';
import 'staff_session.dart';
import 'staff_orders_screen.dart';

import '../../services/push_service.dart';

class StaffLoginScreen extends ConsumerStatefulWidget {
  const StaffLoginScreen({super.key});

  @override
  ConsumerState<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends ConsumerState<StaffLoginScreen> {
  final _pinC = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinC.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final pin = _pinC.text.trim();
    if (pin != StaffConfig.staffPin) {
      setState(() => _error = 'Invalid PIN');
      return;
    }

    ref.read(staffAuthedProvider.notifier).state = true;

    // Register this device as STAFF so it receives new-order alerts
    final registered = await PushService.registerStaffFromPin(pin);

    if (!registered && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Staff device push registration failed. Push alerts may not ring.'),
        ),
      );
    }
Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => StaffOrdersScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Enter Staff PIN',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinC,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'PIN',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) { _login(); },
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () { _login(); },
                child: const Text('Login'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
