import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:handi_roti_app/services/push_service.dart';

class PhoneAuthScreen extends StatefulWidget {
  final String defaultCountryCode; // e.g. "+971"

  const PhoneAuthScreen({
    super.key,
    this.defaultCountryCode = "+971",
  });

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  String? _verificationId;
  int? _resendToken;

  bool _sending = false;
  bool _verifying = false;

  String? _error;
  String? _info; // lightweight status text

  Timer? _resendTimer;
  int _resendSeconds = 0;

  bool _autoSubmitted = false;

  @override
  void initState() {
    super.initState();
    _phoneCtrl.text = widget.defaultCountryCode;
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _startResendCountdown([int seconds = 60]) {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendSeconds <= 1) {
        t.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  String _friendlyAuthError(FirebaseAuthException e) {
    final code = e.code.toLowerCase();
    final msg = (e.message ?? '').toLowerCase();

    // Common Firebase phone auth cases
    if (code.contains('invalid-phone-number') || msg.contains('invalid phone number')) {
      return "That phone number looks invalid. Please use international format, e.g. +9715xxxxxxx.";
    }
    if (code.contains('too-many-requests') || msg.contains('unusual activity') || msg.contains('blocked')) {
      return "Too many attempts from this device. Please wait a bit and try again, or switch network.";
    }
    if (code.contains('captcha-check-failed')) {
      return "Verification failed. Please try again (or switch network) and ensure Google Play services are updated.";
    }
    if (code.contains('quota-exceeded')) {
      return "OTP quota exceeded for now. Please try again later.";
    }
    if (code.contains('session-expired')) {
      return "OTP session expired. Please request a new code.";
    }
    if (code.contains('invalid-verification-code')) {
      return "Invalid OTP. Please check the code and try again.";
    }
    if (code.contains('missing-verification-code')) {
      return "Please enter the OTP code.";
    }
    return e.message ?? "Verification failed. Please try again.";
  }

  bool _isValidE164Like(String phone) {
    if (phone.isEmpty) return false;
    if (!phone.startsWith('+')) return false;
    if (phone.length < 8) return false;
    // very light validation: + then digits, spaces allowed
    final normalized = phone.replaceAll(' ', '');
    return RegExp(r'^\+[0-9]{7,15}$').hasMatch(normalized);
  }

  Future<void> _sendOtp({bool isResend = false}) async {
    final phone = _phoneCtrl.text.trim().replaceAll(' ', '');
    if (!_isValidE164Like(phone)) {
      setState(() => _error = "Enter phone in international format, e.g. +9715xxxxxxx");
      return;
    }

    // prevent hammering: disable while countdown is running
    if (_resendSeconds > 0) return;

    setState(() {
      _sending = true;
      _verifying = false;
      _autoSubmitted = false;
      _error = null;
      _info = null;
      if (!isResend) {
        _verificationId = null;
        _resendToken = null;
      }
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: isResend ? _resendToken : null,
        verificationCompleted: (PhoneAuthCredential cred) async {
          // Auto-retrieval on Android (best effort). If it succeeds, we sign in directly.
          try {
            await FirebaseAuth.instance.signInWithCredential(cred);
            await PushService.registerFromFirebaseUser();
            if (!mounted) return;
            Navigator.of(context).pop(true);
          } catch (_) {
            // If auto verification fails, user can still enter OTP manually.
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _error = _friendlyAuthError(e));
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _info = "OTP sent. Please check your SMS.";
          });
          _startResendCountdown(60);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // Still allow manual entry with the last verification id.
          setState(() {
            _verificationId = verificationId;
            _info ??= "Enter the OTP you received.";
          });
        },
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyAuthError(e));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyOtp({String? codeOverride}) async {
    final code = (codeOverride ?? _codeCtrl.text).trim();

    if (_verificationId == null) {
      setState(() => _error = "Tap 'Send OTP' first.");
      return;
    }

    // Firebase SMS codes are typically 6 digits, but keep a small tolerance
    if (code.length < 4) {
      setState(() => _error = "Enter the OTP code.");
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
      _info = null;
    });

    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );

      await FirebaseAuth.instance.signInWithCredential(cred);
      await PushService.registerFromFirebaseUser();

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyAuthError(e));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCode = _verificationId != null;

    final sendLabel = hasCode ? "Resend OTP" : "Send OTP";
    final sendDisabled = _sending || _resendSeconds > 0;

    final verifyDisabled = !hasCode || _verifying || _codeCtrl.text.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Login required to place an order.",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: "Phone (e.g. +9715xxxxxxx)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),

              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: sendDisabled ? null : () => _sendOtp(isResend: hasCode),
                  child: Text(_sending ? "Sending..." : sendLabel),
                ),
              ),

              if (_resendSeconds > 0) ...[
                const SizedBox(height: 8),
                Text(
                  "You can resend in $_resendSeconds seconds",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black.withOpacity(0.6)),
                ),
              ],

              const SizedBox(height: 14),

              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: (v) {
                  // Auto-submit when user enters 6 digits, but only once per send.
                  if (!hasCode) return;
                  if (_verifying) return;
                  if (_autoSubmitted) return;

                  final code = v.trim();
                  if (code.length == 6) {
                    _autoSubmitted = true;
                    _verifyOtp(codeOverride: code);
                  }
                  setState(() {}); // refresh Verify button enabled/disabled
                },
                decoration: const InputDecoration(
                  labelText: "OTP Code",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),

              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: verifyDisabled ? null : _verifyOtp,
                  child: Text(_verifying ? "Verifying..." : "Verify & Continue"),
                ),
              ),

              if (_info != null) ...[
                const SizedBox(height: 12),
                Text(_info!, style: TextStyle(color: Colors.black.withOpacity(0.75))),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Colors.red.shade700)),
              ],

             // if (kDebugMode) ...[
             //   const SizedBox(height: 14),
             //   Text(
              //    "Emulator tip: Use Firebase Authentication → Settings → Test phone numbers.\nExample: +971500000000 / code 123456",
             //     style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12),
             //   ),
            //  ],
            ],
          ),
        ),
      ),
    );
  }
}
