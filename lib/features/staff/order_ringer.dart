import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Foreground (in-app) order ringer for Staff/Kitchen panel.
///
/// Why this implementation:
/// - Uses rootBundle to load the exact Flutter asset key: `assets/sounds/order_ring.mp3`
/// - Plays via BytesSource + PlayerMode.mediaPlayer (reliable on emulator + real devices)
/// - Loops until stopped
class OrderRinger {
  static const String _assetKey = 'assets/sounds/order_ring.mp3';

  final AudioPlayer _player = AudioPlayer();
  Uint8List? _bytes;
  bool _isRinging = false;

  Future<Uint8List> _loadBytesOnce() async {
    if (_bytes != null) return _bytes!;
    final data = await rootBundle.load(_assetKey);
    _bytes = data.buffer.asUint8List();
    return _bytes!;
  }

  /// Start looping ring (safe to call repeatedly).
  Future<void> start() async {
    if (_isRinging) return;
    _isRinging = true;

    try {
      // MediaPlayer path works best for MP3 on emulator/real phones.
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
    } catch (_) {}

    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);

      final bytes = await _loadBytesOnce();
      await _player.play(BytesSource(bytes));
      // ignore: avoid_print
      print('[OrderRinger] started');
    } catch (e) {
      _isRinging = false;
      // ignore: avoid_print
      print('[OrderRinger] start failed: $e');
      rethrow;
    }
  }

  /// Stop ring (safe to call repeatedly).
  Future<void> stop() async {
    if (!_isRinging) return;
    _isRinging = false;
    try {
      await _player.stop();
      // ignore: avoid_print
      print('[OrderRinger] stopped');
    } catch (e) {
      // ignore: avoid_print
      print('[OrderRinger] stop failed: $e');
    }
  }

  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
