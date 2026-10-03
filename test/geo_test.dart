import 'package:bike_assyst/geo/geo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('distance of one degree of latitude is about 111 km', () {
    expect(distanceMeters(const LatLng(0, 0), const LatLng(1, 0)), closeTo(111195, 50));
  });

  test('bearings point the right way', () {
    const o = LatLng(50, 30);
    expect(bearingDegrees(o, const LatLng(50.01, 30)), closeTo(0, 0.1));
    expect(bearingDegrees(o, const LatLng(50, 30.01)), closeTo(90, 0.1));
    expect(bearingDegrees(o, const LatLng(49.99, 30)), closeTo(180, 0.1));
  });

  test('bearingDelta wraps around north', () {
    expect(bearingDelta(350, 10), 20);
    expect(bearingDelta(10, 350), -20);
    expect(bearingDelta(0, 180), 180);
  });

  test('projection clamps to segment ends', () {
    const a = LatLng(50, 30), b = LatLng(50.001, 30);
    expect(projectOntoSegment(const LatLng(50.0005, 30.0001), a, b).fraction, closeTo(0.5, 0.01));
    expect(projectOntoSegment(const LatLng(49.9, 30), a, b).fraction, 0);
  });
}
