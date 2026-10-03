import 'dart:math' as math;

/// A WGS84 coordinate in degrees.
class LatLng {
  const LatLng(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) =>
      other is LatLng && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'LatLng($lat, $lng)';
}

const double _earthRadiusM = 6371000;

double _rad(double deg) => deg * math.pi / 180;
double _deg(double rad) => rad * 180 / math.pi;

/// Great-circle distance in meters.
double distanceMeters(LatLng a, LatLng b) {
  final dLat = _rad(b.lat - a.lat);
  final dLng = _rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
}

/// Initial bearing from [a] to [b], in degrees clockwise from north [0, 360).
double bearingDegrees(LatLng a, LatLng b) {
  final y = math.sin(_rad(b.lng - a.lng)) * math.cos(_rad(b.lat));
  final x = math.cos(_rad(a.lat)) * math.sin(_rad(b.lat)) -
      math.sin(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.cos(_rad(b.lng - a.lng));
  return (_deg(math.atan2(y, x)) + 360) % 360;
}

/// Signed smallest difference `to - from` in degrees, in (-180, 180].
/// Positive means a clockwise (right) turn.
double bearingDelta(double from, double to) {
  var d = (to - from) % 360;
  if (d > 180) d -= 360;
  if (d <= -180) d += 360;
  return d;
}

/// Result of projecting a point onto a segment.
class SegmentProjection {
  const SegmentProjection(this.point, this.fraction, this.distanceMeters);

  /// Closest point on the segment.
  final LatLng point;

  /// Position along the segment, 0 at start and 1 at end.
  final double fraction;

  /// Distance from the query point to [point].
  final double distanceMeters;
}

/// Projects [p] onto segment [a]-[b] using a local equirectangular
/// approximation, which is accurate enough for segments of a few km.
SegmentProjection projectOntoSegment(LatLng p, LatLng a, LatLng b) {
  final cosLat = math.cos(_rad(a.lat));
  final ax = 0.0, ay = 0.0;
  final bx = (b.lng - a.lng) * cosLat, by = b.lat - a.lat;
  final px = (p.lng - a.lng) * cosLat, py = p.lat - a.lat;
  final len2 = (bx - ax) * (bx - ax) + (by - ay) * (by - ay);
  var t = len2 == 0 ? 0.0 : ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / len2;
  t = t.clamp(0.0, 1.0);
  final proj = LatLng(a.lat + t * (b.lat - a.lat), a.lng + t * (b.lng - a.lng));
  return SegmentProjection(proj, t, distanceMeters(p, proj));
}

/// Point at [fraction] between [a] and [b] (linear interpolation).
LatLng lerp(LatLng a, LatLng b, double fraction) =>
    LatLng(a.lat + (b.lat - a.lat) * fraction, a.lng + (b.lng - a.lng) * fraction);
