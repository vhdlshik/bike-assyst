import 'package:bike_assyst/geo/geo.dart';
import 'package:bike_assyst/nav/navigation_engine.dart';
import 'package:bike_assyst/nav/position_source.dart';
import 'package:bike_assyst/route/demo_route.dart';
import 'package:bike_assyst/route/route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final route = demoRoute();

  test('at the start the next maneuver is the first turn, 300 m ahead', () {
    final s = NavigationEngine(route).update(route.points.first);
    expect(s.nextManeuver!.direction, TurnDirection.right);
    expect(s.distanceToManeuver, closeTo(300, 5));
    expect(s.offRoute, isFalse);
  });

  test('a point 20 m beside the route is still on route; 100 m is off route', () {
    final p = route.points[5];
    final engine = NavigationEngine(route);
    expect(engine.update(LatLng(p.lat, p.lng + 20 / 71600)).offRoute, isFalse);
    expect(engine.update(LatLng(p.lat, p.lng + 100 / 71600)).offRoute, isTrue);
  });

  test('riding the whole route visits every maneuver in order and arrives', () async {
    final engine = NavigationEngine(route);
    final source = SimulatedPositionSource(route, speedMps: 5000, tick: const Duration(milliseconds: 1));
    final seen = <TurnDirection>[];
    NavState? last;
    await for (final p in source.positions) {
      last = engine.update(p);
      final m = last.nextManeuver;
      if (m != null && route.maneuvers.indexOf(m) == seen.length) seen.add(m.direction);
    }
    expect(last!.arrived, isTrue);
    expect(last.nextManeuver, isNull);
    expect(seen, route.maneuvers.map((m) => m.direction).toList());
  });
}
