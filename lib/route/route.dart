import '../geo/geo.dart';

enum TurnDirection {
  slightLeft,
  left,
  sharpLeft,
  uTurn,
  slightRight,
  right,
  sharpRight,
  arrive;

  bool get isLeft => this == slightLeft || this == left || this == sharpLeft || this == uTurn;
  bool get isRight => this == slightRight || this == right || this == sharpRight;

  String get label => switch (this) {
        slightLeft => 'Slight left',
        left => 'Turn left',
        sharpLeft => 'Sharp left',
        uTurn => 'U-turn',
        slightRight => 'Slight right',
        right => 'Turn right',
        sharpRight => 'Sharp right',
        arrive => 'Arrive',
      };
}

/// A turn (or the arrival) at a specific vertex of the route polyline.
class Maneuver {
  const Maneuver({
    required this.pointIndex,
    required this.direction,
    required this.distanceFromStart,
    this.angle = 0,
    this.instruction,
  });

  /// Index into [NavRoute.points] where the maneuver happens.
  final int pointIndex;
  final TurnDirection direction;

  /// Distance along the route from the start to this maneuver, meters.
  final double distanceFromStart;

  /// Signed heading change in degrees, positive is right.
  final double angle;

  /// Spoken-style instruction from the routing service, e.g. "Turn left onto
  /// Main St". Null for routes imported from files.
  final String? instruction;
}

/// A route the rider follows: a polyline plus the maneuvers along it.
class NavRoute {
  NavRoute({required this.name, required this.points, required this.maneuvers})
      : cumulativeDistances = _cumulative(points);

  final String name;
  final List<LatLng> points;
  final List<Maneuver> maneuvers;

  /// Distance from the start to each point, meters. Same length as [points].
  final List<double> cumulativeDistances;

  double get totalDistance => cumulativeDistances.isEmpty ? 0 : cumulativeDistances.last;

  static List<double> _cumulative(List<LatLng> points) {
    final out = <double>[];
    var acc = 0.0;
    for (var i = 0; i < points.length; i++) {
      if (i > 0) acc += distanceMeters(points[i - 1], points[i]);
      out.add(acc);
    }
    return out;
  }
}
