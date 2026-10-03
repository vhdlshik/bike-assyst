import 'dart:math' as math;

import '../geo/geo.dart';
import 'maneuver_detector.dart';
import 'route.dart';

/// A short city loop with left and right turns, for trying the HUD without
/// importing a file.
NavRoute demoRoute() {
  // Legs as (heading degrees, meters).
  const legs = [(0.0, 300.0), (90.0, 220.0), (45.0, 200.0), (330.0, 250.0), (60.0, 180.0)];
  var p = const LatLng(50.4501, 30.5234);
  final pts = <LatLng>[p];
  for (final (heading, meters) in legs) {
    // Densify each leg so it looks like a real recorded track.
    const step = 20.0;
    for (var d = step; d <= meters; d += step) {
      pts.add(_offset(p, heading, d));
    }
    p = pts.last;
  }
  return const ManeuverDetector().build('Demo loop', pts);
}

LatLng _offset(LatLng from, double headingDeg, double meters) {
  final h = headingDeg * math.pi / 180;
  final dLat = meters * math.cos(h) / 111320;
  final dLng = meters * math.sin(h) / (111320 * math.cos(from.lat * math.pi / 180));
  return LatLng(from.lat + dLat, from.lng + dLng);
}
