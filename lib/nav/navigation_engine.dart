import '../geo/geo.dart';
import '../route/route.dart';

/// What the HUD should show for the rider's current position.
class NavState {
  const NavState({
    required this.position,
    required this.distanceAlong,
    required this.distanceFromRoute,
    required this.nextManeuver,
    required this.distanceToManeuver,
    required this.remaining,
    required this.offRoute,
    required this.arrived,
  });

  final LatLng position;

  /// Meters travelled along the route (projection of [position]).
  final double distanceAlong;

  /// Meters between [position] and the closest point on the route.
  final double distanceFromRoute;

  final Maneuver? nextManeuver;
  final double distanceToManeuver;
  final double remaining;
  final bool offRoute;
  final bool arrived;
}

/// Matches GPS fixes to a [NavRoute] and works out the upcoming maneuver.
///
/// Progress only searches a window ahead of the last matched segment so that
/// routes which pass the same street twice don't snap backwards; when the
/// rider is off-route it falls back to a full search to re-acquire.
class NavigationEngine {
  NavigationEngine(
    this.route, {
    this.offRouteMeters = 40,
    this.arriveMeters = 15,
    this.passedManeuverMeters = 8,
    this.searchWindow = 40,
  });

  final NavRoute route;
  final double offRouteMeters;
  final double arriveMeters;

  /// A maneuver counts as done once the rider is this far past it.
  final double passedManeuverMeters;

  /// How many segments behind/ahead of the last match to search.
  final int searchWindow;

  int _segment = 0;
  bool _arrived = false;

  NavState update(LatLng position) {
    final pts = route.points;
    final cum = route.cumulativeDistances;

    var match = _bestMatch(position, (_segment - 2).clamp(0, pts.length - 2),
        (_segment + searchWindow).clamp(0, pts.length - 2));
    if (match.$2.distanceMeters > offRouteMeters) {
      final global = _bestMatch(position, 0, pts.length - 2);
      if (global.$2.distanceMeters < match.$2.distanceMeters) match = global;
    }
    final (seg, proj) = match;
    final onRoute = proj.distanceMeters <= offRouteMeters;
    if (onRoute) _segment = seg;

    final along = cum[seg] + proj.fraction * (cum[seg + 1] - cum[seg]);
    final remaining = (route.totalDistance - along).clamp(0.0, double.infinity);
    if (onRoute && remaining <= arriveMeters) _arrived = true;

    Maneuver? next;
    for (final m in route.maneuvers) {
      if (m.distanceFromStart + passedManeuverMeters > along) {
        next = m;
        break;
      }
    }

    return NavState(
      position: position,
      distanceAlong: along,
      distanceFromRoute: proj.distanceMeters,
      nextManeuver: _arrived ? null : next,
      distanceToManeuver:
          next == null ? 0 : (next.distanceFromStart - along).clamp(0.0, double.infinity),
      remaining: remaining,
      offRoute: !onRoute,
      arrived: _arrived,
    );
  }

  (int, SegmentProjection) _bestMatch(LatLng p, int from, int to) {
    final pts = route.points;
    var bestSeg = from;
    var best = projectOntoSegment(p, pts[from], pts[from + 1]);
    for (var i = from + 1; i <= to; i++) {
      final proj = projectOntoSegment(p, pts[i], pts[i + 1]);
      if (proj.distanceMeters < best.distanceMeters) {
        best = proj;
        bestSeg = i;
      }
    }
    return (bestSeg, best);
  }
}
