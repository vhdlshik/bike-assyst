import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../geo/geo.dart';
import '../route/route.dart';

abstract class PositionSource {
  Stream<LatLng> get positions;
}

/// Real device GPS.
class GpsPositionSource implements PositionSource {
  /// Asks for location permission; returns an error message, or null on success.
  static Future<String?> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Location services are turned off';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return 'Location permission was denied';
    }
    return null;
  }

  static Future<LatLng> current() async {
    final p = await Geolocator.getCurrentPosition();
    return LatLng(p.latitude, p.longitude);
  }

  @override
  Stream<LatLng> get positions => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2,
        ),
      ).map((p) => LatLng(p.latitude, p.longitude));
}

/// Rides along the route at a fixed speed. Lets you try the HUD at a desk.
class SimulatedPositionSource implements PositionSource {
  SimulatedPositionSource(
    this.route, {
    this.speedMps = 7,
    this.tick = const Duration(milliseconds: 500),
  });

  final NavRoute route;
  final double speedMps;
  final Duration tick;

  @override
  Stream<LatLng> get positions async* {
    final pts = route.points;
    final cum = route.cumulativeDistances;
    var d = 0.0;
    var seg = 0;
    while (true) {
      while (seg < pts.length - 2 && cum[seg + 1] < d) {
        seg++;
      }
      final len = cum[seg + 1] - cum[seg];
      final f = len == 0 ? 0.0 : ((d - cum[seg]) / len).clamp(0.0, 1.0);
      yield lerp(pts[seg], pts[seg + 1], f);
      if (d >= route.totalDistance) return;
      await Future<void>.delayed(tick);
      d = (d + speedMps * tick.inMilliseconds / 1000).clamp(0.0, route.totalDistance);
    }
  }
}
