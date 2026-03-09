import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/handi_api.dart';
import '../../core/auth/current_user_phone.dart';
import '../cart/cart_provider.dart';
import 'offers_screen.dart';
import 'order_success_screen.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameC = TextEditingController();
  final _phoneC = TextEditingController();
  final _voucherCodeC = TextEditingController();
  final _address1C = TextEditingController();
  final _areaC = TextEditingController();
  final _buildingC = TextEditingController();
  final _apartmentC = TextEditingController();
  final _notesC = TextEditingController();

  bool _busy = false;
  bool _profileLoading = false;
  bool _applyingVoucher = false;
  String? _deletingAddressId;
  Timer? _phoneDebounce;

  String _payment = 'cod';
  String _addressLabel = 'Home';
  String? _selectedAddressId;
  String? _loadedPhone;
  List<SavedAddress> _savedAddresses = const [];

  String? _voucherId;
  String? _appliedVoucherCode;
  double _voucherDiscountAed = 0.0;
  String? _voucherError;

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      final phone = (await CurrentUserPhone.get())?.trim() ?? '';
      if (!mounted) return;
      if (phone.isNotEmpty && _phoneC.text.trim().isEmpty) {
        _phoneC.text = phone;
        await _loadCustomerProfile(phone, showLoader: true, silent: true);
      }
    });

    _phoneC.addListener(_onPhoneChanged);
  }

  @override
  void dispose() {
    _phoneDebounce?.cancel();
    _phoneC.removeListener(_onPhoneChanged);
    _nameC.dispose();
    _phoneC.dispose();
    _voucherCodeC.dispose();
    _address1C.dispose();
    _areaC.dispose();
    _buildingC.dispose();
    _apartmentC.dispose();
    _notesC.dispose();
    super.dispose();
  }

  void _onPhoneChanged() {
    final phone = _phoneC.text.trim();
    if (phone == _loadedPhone) return;

    _phoneDebounce?.cancel();
    if (phone.length < 7) {
      setState(() {
        _savedAddresses = const [];
        _selectedAddressId = null;
        _loadedPhone = null;
      });
      return;
    }

    _phoneDebounce = Timer(const Duration(milliseconds: 650), () {
      _loadCustomerProfile(phone, silent: true);
    });
  }

  Future<void> _loadCustomerProfile(
    String phone, {
    bool showLoader = false,
    bool silent = false,
  }) async {
    final normalized = phone.trim();
    if (normalized.length < 7) return;

    setState(() {
      _profileLoading = showLoader || !silent;
    });

    try {
      final result = await HandiApi().getCustomerProfile(normalized);
      if (!mounted) return;

      if (result.ok) {
        final addresses = result.addresses;
        final prefillName = (result.name ?? '').trim();

        setState(() {
          _loadedPhone = normalized;
          _savedAddresses = addresses;
          if (_nameC.text.trim().isEmpty && prefillName.isNotEmpty) {
            _nameC.text = prefillName;
          }
          if (addresses.isNotEmpty) {
            final selected = addresses.firstWhere(
              (a) => a.isDefault,
              orElse: () => addresses.first,
            );
            _selectSavedAddress(selected, animate: false);
          }
        });
      }
    } catch (_) {
      if (!mounted) return;
    } finally {
      if (mounted) {
        setState(() => _profileLoading = false);
      }
    }
  }

  void _selectSavedAddress(SavedAddress address, {bool animate = true}) {
    _selectedAddressId = address.id;
    _addressLabel = address.label.trim().isEmpty ? 'Other' : address.label;
    _address1C.text = address.addressLine1;
    _areaC.text = address.area;

    final line2 = address.addressLine2.trim();
    String building = '';
    String apartment = '';
    if (line2.isNotEmpty) {
      final parts = line2.split(',');
      if (parts.isNotEmpty) {
        building = parts.first.trim();
      }
      if (parts.length > 1) {
        apartment = parts.sublist(1).join(',').replaceFirst(RegExp(r'^Apt\s*', caseSensitive: false), '').trim();
      }
    }
    _buildingC.text = building;
    _apartmentC.text = apartment;

    if (mounted) setState(() {});
  }

  void _startNewAddress() {
    setState(() {
      _selectedAddressId = null;
      _addressLabel = 'Home';
      _address1C.clear();
      _areaC.clear();
      _buildingC.clear();
      _apartmentC.clear();
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  double _deliveryFeeFor(double subtotal) => subtotal < 50.0 ? 5.0 : 0.0;

  Future<void> _openOffers() async {
    final phone = _phoneC.text.trim().isNotEmpty
        ? _phoneC.text.trim()
        : ((await CurrentUserPhone.get())?.trim() ?? '');

    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => OffersScreen(phone: phone.isNotEmpty ? phone : null),
      ),
    );

    if (picked != null && picked.trim().isNotEmpty) {
      setState(() {
        _voucherCodeC.text = picked.trim().toUpperCase();
        _voucherError = null;
      });
      await _applyVoucher();
    }
  }

  Future<void> _applyVoucher() async {
    final code = _voucherCodeC.text.trim();
    if (code.isEmpty) {
      setState(() {
        _voucherError = 'Please enter a voucher code';
        _voucherId = null;
        _voucherDiscountAed = 0.0;
      });
      return;
    }

    if (_voucherId != null) {
      setState(() {
        _voucherError =
            'Only one voucher can be applied per order. Remove it first.';
      });
      return;
    }

    final subtotal = ref.read(cartTotalProvider);
    if (subtotal <= 0) {
      setState(() {
        _voucherError = 'Add items to cart first';
        _voucherId = null;
        _voucherDiscountAed = 0.0;
      });
      return;
    }

    setState(() {
      _applyingVoucher = true;
      _voucherError = null;
    });

    try {
      final customerKey = _phoneC.text.trim();
      final result = await HandiApi().validateVoucher(
        voucherCode: code,
        subtotalAed: subtotal,
        customerKey: customerKey.isEmpty ? null : customerKey,
      );

      if (!mounted) return;

      if (result.ok && result.voucherId != null && result.discountAed > 0) {
        setState(() {
          _voucherId = result.voucherId;
          _appliedVoucherCode = code;
          _voucherDiscountAed = result.discountAed;
          _voucherError = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Voucher applied: -AED ${result.discountAed.toStringAsFixed(2)}'),
          ),
        );
      } else {
        setState(() {
          _voucherId = null;
          _voucherDiscountAed = 0.0;
          _voucherError = result.error ?? 'Invalid voucher';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _voucherId = null;
        _voucherDiscountAed = 0.0;
        _voucherError = 'Failed to validate voucher';
      });
    } finally {
      if (mounted) setState(() => _applyingVoucher = false);
    }
  }

  Future<void> _placeOrder() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final cartLines = ref.read(cartProvider);
    if (cartLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty')),
      );
      return;
    }

    setState(() => _busy = true);

    try {
      final subtotal = ref.read(cartTotalProvider);
      final deliveryFee = _deliveryFeeFor(subtotal);
      final voucherDisc = (_voucherDiscountAed <= 0)
          ? 0.0
          : (_voucherDiscountAed > subtotal ? subtotal : _voucherDiscountAed);
      final subtotalAfterVoucher = subtotal - voucherDisc;
      final total = subtotalAfterVoucher + deliveryFee;

      final building = _buildingC.text.trim();
      final apartment = _apartmentC.text.trim();
      final addressLine2 = <String>[
        if (building.isNotEmpty) building,
        if (apartment.isNotEmpty) 'Apt $apartment',
      ].join(', ');

      final payload = <String, dynamic>{
        'customer': {
          'name': _nameC.text.trim(),
          'phone': _phoneC.text.trim(),
        },
        'payment_method': _payment == 'card' ? 'card_on_delivery' : 'cod',
        if ((_appliedVoucherCode ?? '').trim().isNotEmpty)
          'voucher_code': (_appliedVoucherCode ?? '').trim(),
        if (_notesC.text.trim().isNotEmpty) 'notes': _notesC.text.trim(),
        'items': cartLines
            .map((e) => {
                  'item_id': e.itemId,
                  'variant_id': e.variantId,
                  'quantity': e.qty,
                })
            .toList(),
      };

      if ((_selectedAddressId ?? '').trim().isNotEmpty) {
        payload['address_id'] = _selectedAddressId!.trim();
      } else {
        payload['address'] = {
          'label': _addressLabel,
          'address_line1': _address1C.text.trim(),
          if (addressLine2.isNotEmpty) 'address_line2': addressLine2,
          'area': _areaC.text.trim(),
          'emirate': 'Ras Al Khaimah',
        };
      }

      final res = await HandiApi().createOrder(payload);

      if (res['ok'] == true) {
        final order = (res['order'] as Map?) ?? {};
        final orderId = (order['id'] ?? '').toString();

        ref.read(cartProvider.notifier).clear();

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OrderSuccessScreen(
              orderId: orderId,
              totalAed: total.toStringAsFixed(2),
            ),
          ),
        );
      } else {
        final msg = (res['error'] ?? 'Failed to place order').toString();
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _input(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE4D8CC)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE4D8CC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD9A441), width: 1.3),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }


  IconData _addressIcon(String label) {
    switch (label.trim().toLowerCase()) {
      case 'home':
        return Icons.home_rounded;
      case 'work':
        return Icons.work_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  Color _addressIconBg(String label) {
    switch (label.trim().toLowerCase()) {
      case 'home':
        return const Color(0xFFFFF3DC);
      case 'work':
        return const Color(0xFFEAF3FF);
      default:
        return const Color(0xFFF2F0EC);
    }
  }

  Future<void> _deleteAddress(SavedAddress address) async {
    final phone = _phoneC.text.trim();
    if (phone.isEmpty) {
      _toast('Phone is missing for this account.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete address?'),
          content: Text(
            'Remove "${address.label}" from saved addresses? This will not affect past orders.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;

    setState(() => _deletingAddressId = address.id);
    try {
      final res = await HandiApi().deleteSavedAddress(
        phone: phone,
        addressId: address.id,
      );
      if (!mounted) return;

      if (res['ok'] == true) {
        _savedAddresses = _savedAddresses.where((a) => a.id != address.id).toList();
        if (_selectedAddressId == address.id) {
          _selectedAddressId = null;
          if (_savedAddresses.isNotEmpty) {
            _selectSavedAddress(_savedAddresses.first, animate: false);
          } else {
            _startNewAddress();
          }
        }
        setState(() {});
        _toast('Saved address deleted');
      } else {
        _toast((res['error'] ?? 'Could not delete address').toString());
      }
    } catch (e) {
      if (mounted) _toast('Could not delete address');
    } finally {
      if (mounted) setState(() => _deletingAddressId = null);
    }
  }

  Widget _sectionCard({
    required String title,
    String? subtitle,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFDFBF8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8DDD1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if ((subtitle ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.black.withOpacity(0.60),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _savedAddressTile(SavedAddress address) {
    final selected = _selectedAddressId == address.id;
    final deleting = _deletingAddressId == address.id;
    final icon = _addressIcon(address.label);

    return InkWell(
      onTap: deleting ? null : () => setState(() => _selectSavedAddress(address)),
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFF7E8), Color(0xFFFFF1D4)],
                )
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, Color(0xFFFCFAF7)],
                ),
          border: Border.all(
            color: selected ? const Color(0xFFD9A441) : const Color(0xFFE5DED6),
            width: selected ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? const Color(0x14D9A441)
                  : const Color(0x0E000000),
              blurRadius: selected ? 18 : 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _addressIconBg(address.label),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFD9A441).withOpacity(0.25)
                      : Colors.black12,
                ),
              ),
              child: Icon(
                icon,
                color: selected ? const Color(0xFFB98219) : const Color(0xFF4A4A4A),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          address.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (address.isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF7EE),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFCAE3CC)),
                          ),
                          child: const Text(
                            'Default',
                            style: TextStyle(
                              color: Color(0xFF2D7A32),
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    address.fullAddress,
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.68),
                      height: 1.35,
                      fontSize: 13.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? const Color(0xFFD9A441) : const Color(0xFFF3F1ED),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          selected ? 'Selected' : 'Tap to use',
                          style: TextStyle(
                            color: selected ? Colors.white : const Color(0xFF5F5A52),
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: deleting ? null : () => _deleteAddress(address),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F1),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFF0CACA)),
                          ),
                          child: deleting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.delete_outline_rounded,
                                      size: 16,
                                      color: Color(0xFFC03A2B),
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Delete',
                                      style: TextStyle(
                                        color: Color(0xFFC03A2B),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? const Color(0xFFD9A441) : Colors.black38,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String left, String right, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      fontSize: bold ? 15.5 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(left, style: style)),
          Text(right, style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartLines = ref.watch(cartProvider);
    final subtotal = ref.watch(cartTotalProvider);
    final deliveryFee = _deliveryFeeFor(subtotal);
    final voucherDisc = (_voucherDiscountAed <= 0)
        ? 0.0
        : (_voucherDiscountAed > subtotal ? subtotal : _voucherDiscountAed);
    final subtotalAfterVoucher = subtotal - voucherDisc;
    final total = subtotalAfterVoucher + deliveryFee;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F2EC),
      appBar: AppBar(
        title: const Text('Checkout'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _sectionCard(
                title: 'Customer details',
                subtitle:
                    'We’ll remember your profile and saved delivery addresses for next time.',
                trailing: _profileLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        tooltip: 'Reload profile',
                        onPressed: () =>
                            _loadCustomerProfile(_phoneC.text.trim(), showLoader: true),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                children: [
                  TextFormField(
                    controller: _nameC,
                    decoration: _input('Full name'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneC,
                    keyboardType: TextInputType.phone,
                    decoration: _input('Phone', hint: '+9715xxxxxxx'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter phone' : null,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_savedAddresses.isNotEmpty)
                _sectionCard(
                  title: 'Saved delivery addresses',
                  subtitle:
                      'Choose a premium saved address, or add a new location for this order.',
                  trailing: TextButton.icon(
                    onPressed: _startNewAddress,
                    icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                    label: const Text('New'),
                  ),
                  children: _savedAddresses.map(_savedAddressTile).toList(),
                ),
              if (_savedAddresses.isNotEmpty) const SizedBox(height: 16),
              _sectionCard(
                title: _selectedAddressId != null
                    ? 'Selected delivery address'
                    : 'New delivery address',
                subtitle: 'Ras Al Khaimah delivery',
                children: [
                  if (_selectedAddressId == null) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['Home', 'Work', 'Other'].map((label) {
                        final selected = _addressLabel == label;
                        return ChoiceChip(
                          label: Text(label),
                          selected: selected,
                          onSelected: (_) => setState(() => _addressLabel = label),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _address1C,
                      decoration: _input('Address line 1'),
                      validator: (v) {
                        if (_selectedAddressId != null) return null;
                        return (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _areaC,
                      decoration: _input('Area'),
                      validator: (v) {
                        if (_selectedAddressId != null) return null;
                        return (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _buildingC,
                      decoration: _input('Building / Villa'),
                      validator: (v) {
                        if (_selectedAddressId != null) return null;
                        return (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _apartmentC,
                      decoration: _input('Apartment (optional)'),
                    ),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5DED6)),
                      ),
                      child: Text(
                        _savedAddresses
                            .firstWhere((a) => a.id == _selectedAddressId)
                            .fullAddress,
                        style: const TextStyle(
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _startNewAddress,
                        icon: const Icon(Icons.edit_location_alt_outlined),
                        label: const Text('Use a different address'),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              _sectionCard(
                title: 'Payment & notes',
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'cod',
                        icon: Icon(Icons.payments_outlined),
                        label: Text('Cash on delivery'),
                      ),
                      ButtonSegment(
                        value: 'card',
                        icon: Icon(Icons.credit_card_outlined),
                        label: Text('Card'),
                      ),
                    ],
                    selected: {_payment},
                    onSelectionChanged: (set) => setState(() => _payment = set.first),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _notesC,
                    decoration: _input('Notes (optional)',
                        hint: 'Landmark, door color, rider instructions'),
                    maxLines: 3,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _sectionCard(
                title: 'Offers & vouchers',
                trailing: TextButton.icon(
                  onPressed: _openOffers,
                  icon: const Icon(Icons.local_offer_outlined, size: 18),
                  label: const Text('View offers'),
                ),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _voucherCodeC,
                          textCapitalization: TextCapitalization.characters,
                          decoration: _input('Voucher code', hint: 'e.g. HANDI20'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 52,
                        child: FilledButton.tonal(
                          onPressed: _applyingVoucher ? null : _applyVoucher,
                          child: _applyingVoucher
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                  if (_voucherId != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Applied: ${_appliedVoucherCode ?? ''}  •  -AED ${_voucherDiscountAed.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Color(0xFF2D7A32),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _voucherCodeC.clear();
                            setState(() {
                              _voucherId = null;
                              _appliedVoucherCode = null;
                              _voucherDiscountAed = 0.0;
                              _voucherError = null;
                            });
                          },
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  ],
                  if (_voucherError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _voucherError!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              _sectionCard(
                title: 'Order summary',
                subtitle: '${cartLines.length} item(s) in your cart',
                children: [
                  _summaryRow('Subtotal', 'AED ${subtotal.toStringAsFixed(2)}'),
                  if (voucherDisc > 0)
                    _summaryRow('Voucher', '-AED ${voucherDisc.toStringAsFixed(2)}'),
                  _summaryRow('Delivery', 'AED ${deliveryFee.toStringAsFixed(2)}'),
                  const Divider(height: 20),
                  _summaryRow('Total', 'AED ${total.toStringAsFixed(2)}', bold: true),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: _busy ? null : _placeOrder,
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Place Order',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15.5,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
