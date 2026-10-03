import 'dart:math' as math;
import 'dart:typed_data';

/// The USB protocol of the XREAL (Nreal) Air family's motion sensor.
///
/// Worked out from the open-source ar-drivers-rs (MIT) and XRLinuxDriver
/// projects. The glasses expose a HID interface that, once enabled, streams
/// about a thousand gyroscope and accelerometer reports a second.
abstract final class XrealAir {
  static const vendorId = 0x3318;

  /// Product ids, each with the HID interface number that carries the IMU.
  static const imuInterfaceByProduct = {
    0x0424: 3, // Nreal / XREAL Air
    0x0428: 3, // XREAL Air 2
    0x0432: 3, // XREAL Air 2 Pro
    0x0426: 2, // XREAL Air 2 Ultra
  };

  /// Every report and command is sent in a packet of this size.
  static const packetSize = 64;

  static const _commandHead = 0xaa;
  static const _streamImu = 0x19;

  /// The command that turns the IMU stream on (or off).
  static Uint8List imuStreamCommand({required bool on}) => command(_streamImu, [on ? 1 : 0]);

  /// A command packet: 0xaa, CRC-32 (little endian) of what follows the
  /// CRC, length (command byte + data + 2), command byte, data, zero padding.
  static Uint8List command(int id, List<int> data) {
    final p = Uint8List(packetSize);
    final length = data.length + 3;
    p[0] = _commandHead;
    p[5] = length & 0xff;
    p[6] = length >> 8;
    p[7] = id;
    p.setRange(8, 8 + data.length, data);
    final crc = crc32(Uint8List.sublistView(p, 5, 5 + length));
    ByteData.sublistView(p).setUint32(1, crc, Endian.little);
    return p;
  }

  /// Decodes a sensor report, or returns null for anything else (command
  /// acknowledgements, other report types, short reads).
  static ImuSample? parseReport(Uint8List r) {
    if (r.length < 42 || r[0] != 1 || r[1] != 2) return null;
    final b = ByteData.sublistView(r);
    // Bytes 2-3 are the temperature; then a nanosecond timestamp, and for each
    // sensor a scale (multiplier, divisor) and three signed 24-bit axes.
    final nanos = b.getUint64(4, Endian.little);
    final gyroScale = b.getUint16(12, Endian.little) / b.getUint32(14, Endian.little);
    final accelScale = b.getUint16(27, Endian.little) / b.getUint32(29, Endian.little);
    return ImuSample(
      micros: nanos ~/ 1000,
      gyro: Vec3(_i24(r, 18) * gyroScale, _i24(r, 21) * gyroScale, _i24(r, 24) * gyroScale),
      accel: Vec3(_i24(r, 33) * accelScale, _i24(r, 36) * accelScale, _i24(r, 39) * accelScale),
    );
  }

  static int _i24(Uint8List r, int at) {
    final v = r[at] | r[at + 1] << 8 | r[at + 2] << 16;
    return v & 0x800000 != 0 ? v - 0x1000000 : v;
  }

  /// Standard CRC-32 (IEEE 802.3), as used by the glasses' packets.
  static int crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var k = 0; k < 8; k++) {
        crc = crc & 1 != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    return crc ^ 0xffffffff;
  }
}

class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x, y, z;

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);
  double get length => math.sqrt(dot(this));
  Vec3 get unit {
    final l = length;
    return l == 0 ? this : this * (1 / l);
  }
}

/// One reading of the glasses' sensors, in the sensor's own axes.
class ImuSample {
  const ImuSample({required this.micros, required this.gyro, required this.accel});

  final int micros;

  /// Rotation rate, degrees per second.
  final Vec3 gyro;

  /// Acceleration, in g. At rest it points up (the sensor feels the push
  /// that holds it against gravity).
  final Vec3 accel;
}
