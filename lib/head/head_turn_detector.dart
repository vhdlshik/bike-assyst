import 'dart:math' as math;

import 'xreal_air.dart';

enum HeadLook { ahead, left, right }

/// Spots a look over the shoulder in the glasses' motion data.
///
/// The gyroscope's rotation around the "up" direction (taken from the
/// accelerometer, so it doesn't matter how the sensor is mounted or how the
/// head is tilted) gives the head's heading. The bike turning moves that
/// heading too, but slowly; a shoulder check is a quick swing. So the heading
/// is compared with a trailing average of itself: a quick swing gets well
/// ahead of it, a gentle bike turn doesn't. While a look lasts, the average is
/// held where the look began, and the look ends when the head comes back.
/// A look that times out instead waits for the head to settle, and for a
/// while afterwards a swing back to where it began counts as coming back,
/// not as a look over the other shoulder.
class HeadTurnDetector {
  HeadTurnDetector({
    this.lookDegrees = 35,
    this.backDegrees = 15,
    this.followSeconds = 0.5,
    this.maxLookSeconds = 4,
  });

  /// Swing this far ahead of the trailing heading to count as a look.
  final double lookDegrees;

  /// The look ends once the head is back within this of where it started.
  final double backDegrees;

  /// How quickly the trailing heading follows; longer catches slower looks
  /// but also mistakes quick bike turns for them.
  final double followSeconds;

  /// A look held longer than this ends anyway (the rider has turned the bike
  /// or settled into a new heading).
  final double maxLookSeconds;

  HeadLook _look = HeadLook.ahead;
  bool _settling = false;
  Vec3? _up;
  int? _lastMicros;
  double _heading = 0;
  double _trailing = 0;
  double _lookStarted = 0;
  double _lookBase = 0;
  // Where a timed-out look began, and until when a swing back there is a return.
  double? _returnTo;
  double _returnUntil = 0;
  double _clock = 0;

  HeadLook get look => _look;

  /// Feeds one sample and returns the look after it.
  HeadLook add(ImuSample s) {
    final last = _lastMicros;
    _lastMicros = s.micros;
    final dt = last == null ? 0.0 : (s.micros - last) / 1e6;
    // A gap or a clock jump (reconnect) would integrate garbage; skip it.
    if (dt <= 0 || dt > 0.1) {
      _up ??= s.accel.unit;
      return _look;
    }
    _clock += dt;

    // Gravity changes slowly; average out road bumps and head nods.
    final upAlpha = 1 - math.exp(-dt / 0.5);
    _up = (_up! * (1 - upAlpha) + s.accel.unit * upAlpha).unit;
    // Right-hand rule around "up": positive is anticlockwise seen from
    // above, which is turning left.
    _heading += s.gyro.dot(_up!) * dt;

    // Back where a timed-out look began: nothing left to return from.
    final returnTo = _returnTo;
    if (returnTo != null && ((_heading - returnTo).abs() <= backDegrees || _clock > _returnUntil)) {
      _returnTo = null;
    }

    final ahead = _heading - _trailing;
    final follow = 1 - math.exp(-dt / followSeconds);
    if (_settling) {
      // Back to where the look began, or settled on a new heading.
      final sinceLook = _heading - _lookBase;
      _trailing += ahead * follow;
      if (sinceLook.abs() <= backDegrees || (_heading - _trailing).abs() <= backDegrees) {
        _settling = false;
        _trailing = _heading;
      }
    } else if (_look == HeadLook.ahead) {
      _trailing += ahead * follow;
      if (ahead.abs() >= lookDegrees) {
        final back = _returnTo;
        _returnTo = null;
        if (back != null && (back - _trailing).sign == ahead.sign) {
          // Swinging back toward where a timed-out look began.
          _settling = true;
          _lookBase = back;
        } else {
          _look = ahead > 0 ? HeadLook.left : HeadLook.right;
          _lookStarted = _clock;
          _lookBase = _trailing;
        }
      }
    } else if (ahead.abs() <= backDegrees) {
      _look = HeadLook.ahead;
      _trailing = _heading;
    } else if (_clock - _lookStarted > maxLookSeconds) {
      _look = HeadLook.ahead;
      _settling = true;
      _returnTo = _lookBase;
      _returnUntil = _clock + 10;
    }
    return _look;
  }
}
