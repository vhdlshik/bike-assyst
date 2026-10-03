import '../geo/geo.dart';
import 'route.dart';

/// Derives turn-by-turn maneuvers from a bare polyline (GPX/KML tracks carry
/// no turn instructions).
///
/// For each vertex it compares the heading of the path [lookMeters] before and
/// after it, so GPS jitter and short zig-zags don't register as turns. Vertices
/// whose heading change exceeds [minTurnDegrees] become candidates; candidates
/// closer than [mergeMeters] collapse into the sharpest one.
class ManeuverDetector {
  const ManeuverDetector({
    this.minTurnDegrees = 35,
    this.lookMeters = 25,
    this.mergeMeters = 30,
  });

  final double minTurnDegrees;
  final double lookMeters;
  final double mergeMeters;

  NavRoute build(String name, List<LatLng> rawPoints) {
    final points = _dedupe(rawPoints);
    final probe = NavRoute(name: name, points: points, maneuvers: const []);
    final cum = probe.cumulativeDistances;
    final candidates = <Maneuver>[];

    for (var i = 1; i < points.length - 1; i++) {
      final before = _pointAtDistance(points, cum, cum[i] - lookMeters);
      final after = _pointAtDistance(points, cum, cum[i] + lookMeters);
      if (distanceMeters(before, points[i]) < 1 || distanceMeters(points[i], after) < 1) continue;
      final delta = bearingDelta(
        bearingDegrees(before, points[i]),
        bearingDegrees(points[i], after),
      );
      if (delta.abs() >= minTurnDegrees) {
        candidates.add(Maneuver(
          pointIndex: i,
          direction: classify(delta),
          distanceFromStart: cum[i],
          angle: delta,
        ));
      }
    }

    final merged = <Maneuver>[];
    for (final m in candidates) {
      if (merged.isNotEmpty && m.distanceFromStart - merged.last.distanceFromStart < mergeMeters) {
        if (m.angle.abs() > merged.last.angle.abs()) merged[merged.length - 1] = m;
      } else {
        merged.add(m);
      }
    }

    if (points.length >= 2) {
      merged.add(Maneuver(
        pointIndex: points.length - 1,
        direction: TurnDirection.arrive,
        distanceFromStart: cum.last,
      ));
    }
    return NavRoute(name: name, points: points, maneuvers: merged);
  }

  static TurnDirection classify(double delta) {
    final a = delta.abs();
    if (a >= 160) return TurnDirection.uTurn;
    if (delta > 0) {
      if (a < 60) return TurnDirection.slightRight;
      if (a < 120) return TurnDirection.right;
      return TurnDirection.sharpRight;
    }
    if (a < 60) return TurnDirection.slightLeft;
    if (a < 120) return TurnDirection.left;
    return TurnDirection.sharpLeft;
  }

  static List<LatLng> _dedupe(List<LatLng> pts) {
    final out = <LatLng>[];
    for (final p in pts) {
      if (out.isEmpty || distanceMeters(out.last, p) > 0.5) out.add(p);
    }
    return out;
  }

  static LatLng _pointAtDistance(List<LatLng> pts, List<double> cum, double d) {
    if (d <= 0) return pts.first;
    if (d >= cum.last) return pts.last;
    var lo = 0, hi = cum.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (cum[mid] <= d) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final seg = cum[hi] - cum[lo];
    return lerp(pts[lo], pts[hi], seg == 0 ? 0 : (d - cum[lo]) / seg);
  }
}
