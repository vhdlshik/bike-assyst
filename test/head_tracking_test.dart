import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bike_assyst/head/head_tracker.dart';
import 'package:bike_assyst/head/head_turn_detector.dart';
import 'package:bike_assyst/head/xreal_air.dart';
import 'package:flutter_test/flutter_test.dart';

/// Writes a sensor report the way the glasses lay it out.
Uint8List report({required int nanos, required List<int> gyro, required List<int> accel}) {
  final r = Uint8List(XrealAir.packetSize);
  final b = ByteData.sublistView(r);
  r[0] = 1;
  r[1] = 2;
  b.setUint64(4, nanos, Endian.little);
  void axes(int scaleAt, List<int> v) {
    b.setUint16(scaleAt, 1, Endian.little); // multiplier
    b.setUint32(scaleAt + 2, 1000, Endian.little); // divisor
    for (var i = 0; i < 3; i++) {
      final u = v[i] & 0xffffff;
      r[scaleAt + 6 + i * 3] = u & 0xff;
      r[scaleAt + 7 + i * 3] = u >> 8 & 0xff;
      r[scaleAt + 8 + i * 3] = u >> 16;
    }
  }

  axes(12, gyro);
  axes(27, accel);
  return r;
}

/// Feeds the detector a head turning at [degPerSec] around [up] for
/// [seconds], at the glasses' 1000 reports a second.
class Rider {
  Rider(this.detector, {Vec3 up = const Vec3(0, -1, 0)}) : _up = up.unit;
  final HeadTurnDetector detector;
  final Vec3 _up;
  int _micros = 0;
  final looks = <HeadLook>[];

  HeadLook turn(double degPerSec, double seconds, {double biasDegPerSec = 0}) {
    for (var i = 0; i < (seconds * 1000).round(); i++) {
      _micros += 1000;
      final look = detector.add(ImuSample(
        micros: _micros,
        gyro: _up * (degPerSec + biasDegPerSec),
        accel: _up,
      ));
      if (looks.isEmpty || looks.last != look) looks.add(look);
    }
    return detector.look;
  }

  HeadLook hold(double seconds, {double biasDegPerSec = 0}) => turn(0, seconds, biasDegPerSec: biasDegPerSec);
}

void main() {
  group('XREAL Air protocol', () {
    test('CRC-32 matches the standard check value', () {
      expect(XrealAir.crc32('123456789'.codeUnits), 0xcbf43926);
    });

    test('IMU stream command matches the reference packet', () {
      final p = XrealAir.imuStreamCommand(on: true);
      expect(p.length, 64);
      // Built independently with zlib.crc32, following ar-drivers-rs.
      expect(p.sublist(0, 9), [0xaa, 0xc5, 0xd1, 0x21, 0x42, 0x04, 0x00, 0x19, 0x01]);
      expect(p.sublist(9).every((b) => b == 0), isTrue);
    });

    test('decodes sensor reports, including negative axes', () {
      final s = XrealAir.parseReport(report(nanos: 5000000, gyro: [1500, -2500, 0], accel: [0, -1000, 250]))!;
      expect(s.micros, 5000);
      expect([s.gyro.x, s.gyro.y, s.gyro.z], [1.5, -2.5, 0]);
      expect([s.accel.x, s.accel.y, s.accel.z], [0, -1, 0.25]);
    });

    test('ignores other packets', () {
      expect(XrealAir.parseReport(XrealAir.imuStreamCommand(on: true)), isNull);
      expect(XrealAir.parseReport(Uint8List(10)), isNull);
    });

    test('tracker decodes a batch of report slots into look changes', () async {
      final tracker = XrealHeadTracker();
      final looks = <HeadLook>[];
      tracker.looks.listen(looks.add);
      final batch = BytesBuilder();
      // Head swings left at 200 degrees/s; the sensor's z axis points up.
      for (var i = 1; i <= 400; i++) {
        batch.add(report(nanos: i * 1000000, gyro: [0, 0, 200000], accel: [0, 0, 1000]));
      }
      tracker.addBatch(batch.toBytes());
      await Future<void>.delayed(Duration.zero);
      expect(looks, [HeadLook.left]);
    });
  });

  group('head turn detector', () {
    test('a quick look over the left shoulder and back', () {
      final r = Rider(HeadTurnDetector());
      expect(r.hold(1), HeadLook.ahead);
      expect(r.turn(200, 0.4), HeadLook.left); // 80 degrees
      expect(r.hold(1), HeadLook.left);
      expect(r.turn(-200, 0.4), HeadLook.ahead);
      expect(r.hold(1), HeadLook.ahead);
      expect(r.looks, [HeadLook.ahead, HeadLook.left, HeadLook.ahead]);
    });

    test('a look over the right shoulder', () {
      final r = Rider(HeadTurnDetector());
      r.hold(0.5);
      expect(r.turn(-250, 0.3), HeadLook.right);
      expect(r.turn(250, 0.3), HeadLook.ahead);
    });

    test('the bike turning a corner is not a look', () {
      final r = Rider(HeadTurnDetector());
      r.hold(0.5);
      r.turn(30, 3); // 90 degree corner over 3 s
      r.turn(-25, 2);
      r.hold(1);
      expect(r.looks, [HeadLook.ahead]);
    });

    test('gyro drift is not a look', () {
      final r = Rider(HeadTurnDetector());
      r.hold(60, biasDegPerSec: 2);
      expect(r.looks, [HeadLook.ahead]);
    });

    test('works with the head tilted and the sensor mounted any way', () {
      final tilted = Vec3(math.sin(0.5), math.cos(0.5) * 0.6, math.cos(0.5) * 0.8);
      final r = Rider(HeadTurnDetector(), up: tilted);
      r.hold(1);
      expect(r.turn(200, 0.4), HeadLook.left);
      expect(r.turn(-200, 0.4), HeadLook.ahead);
    });

    test('a look held too long ends, and turning back is not a look the other way', () {
      final r = Rider(HeadTurnDetector());
      r.hold(1);
      r.turn(200, 0.4);
      expect(r.hold(5), HeadLook.ahead);
      r.turn(-200, 0.4);
      r.hold(1);
      expect(r.looks, [HeadLook.ahead, HeadLook.left, HeadLook.ahead]);
      // And the next look still registers.
      expect(r.turn(-200, 0.4), HeadLook.right);
    });

    test('a timed-out look that comes straight back leaves the next look alone', () {
      final r = Rider(HeadTurnDetector());
      r.hold(1);
      r.turn(200, 0.4);
      expect(r.hold(3.8), HeadLook.left); // the 4 s limit is about to pass
      expect(r.turn(-200, 0.4), HeadLook.ahead); // times out on the way back
      r.turn(-25, 2.4); // the bike turns 60 degrees right
      r.hold(0.5);
      expect(r.turn(200, 0.4), HeadLook.left);
    });
  });
}
