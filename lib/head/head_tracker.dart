import 'dart:async';

import 'package:flutter/services.dart';

import 'head_turn_detector.dart';
import 'xreal_air.dart';

/// Tells the HUD when the rider looks over a shoulder.
abstract class HeadTracker {
  /// Starts tracking. Returns null when running, or why it isn't.
  Future<String?> start();

  /// Changes of look; starts with the first change after [start].
  Stream<HeadLook> get looks;

  Future<void> stop();
}

/// Reads the motion sensor of XREAL/Nreal Air glasses plugged into the phone.
///
/// The Android side (GlassesImu.kt) only finds the glasses, asks for USB
/// permission and moves bytes; the protocol lives in [XrealAir] so it can be
/// tested here. Reports arrive in batches of [XrealAir.packetSize]-byte
/// slots to keep the thousand-a-second stream off the platform channel.
class XrealHeadTracker implements HeadTracker {
  XrealHeadTracker({HeadTurnDetector? detector}) : _detector = detector ?? HeadTurnDetector();

  static const _methods = MethodChannel('bike_assyst/glasses_imu');
  static const _reports = EventChannel('bike_assyst/glasses_imu/reports');

  final HeadTurnDetector _detector;
  final _looks = StreamController<HeadLook>.broadcast();
  StreamSubscription<dynamic>? _sub;

  @override
  Stream<HeadLook> get looks => _looks.stream;

  @override
  Future<String?> start() async {
    try {
      final error = await _methods.invokeMethod<String>(
          'start', {'command': XrealAir.imuStreamCommand(on: true), 'packetSize': XrealAir.packetSize});
      if (error != null) return error;
    } on MissingPluginException {
      return 'Head tracking needs Android';
    } on PlatformException catch (e) {
      return 'Glasses motion sensor unavailable: ${e.message ?? e.code}';
    }
    _sub = _reports.receiveBroadcastStream().listen(
      (batch) => addBatch(batch as Uint8List),
      // Unplugged mid-ride: stop looking anywhere but ahead.
      onError: (Object _) {
        if (_looks.isClosed) return;
        _looks.add(HeadLook.ahead);
        _looks.addError('Glasses motion sensor disconnected');
      },
    );
    return null;
  }

  /// Decodes a batch of reports and forwards look changes.
  void addBatch(Uint8List batch) {
    for (var at = 0; at + XrealAir.packetSize <= batch.length; at += XrealAir.packetSize) {
      final sample = XrealAir.parseReport(Uint8List.sublistView(batch, at, at + XrealAir.packetSize));
      if (sample == null) continue;
      final before = _detector.look;
      final after = _detector.add(sample);
      if (after != before) _looks.add(after);
    }
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _methods.invokeMethod<void>('stop', {'command': XrealAir.imuStreamCommand(on: false)});
    } on MissingPluginException {
      // Nothing was started.
    } on PlatformException {
      // Unplugged already; nothing to stop.
    }
    await _looks.close();
  }
}
