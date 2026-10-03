import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../geo/geo.dart';
import '../route.dart';
import 'maps_link.dart';
import 'polyline.dart';

class RoutesApiException implements Exception {
  RoutesApiException(this.message);
  final String message;
  @override
  String toString() => 'RoutesApiException: $message';
}

/// Fetches bike routes from the Google Routes API (`computeRoutes`), the
/// current version of Google's directions service.
class GoogleRoutesClient {
  GoogleRoutesClient({required this.apiKey, http.Client? client}) : _client = client ?? http.Client();

  /// Set at build time: `--dart-define=GOOGLE_MAPS_API_KEY=...`.
  static const buildTimeApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  static final endpoint = Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes');
  static const fieldMask = 'routes.distanceMeters,'
      'routes.legs.steps.polyline.encodedPolyline,'
      'routes.legs.steps.navigationInstruction';

  final String apiKey;
  final http.Client _client;

  /// [stops] must not contain [Stop.current]; resolve it to coordinates first.
  Future<NavRoute> fetchBikeRoute(List<Stop> stops, {required String name}) async {
    if (stops.length < 2) throw RoutesApiException('A route needs at least two stops');
    final body = {
      'origin': _waypoint(stops.first),
      'destination': _waypoint(stops.last),
      if (stops.length > 2) 'intermediates': [for (final s in stops.sublist(1, stops.length - 1)) _waypoint(s)],
      'travelMode': 'BICYCLE',
      'languageCode': 'en',
    };
    final res = await _client.post(
      endpoint,
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': fieldMask,
      },
      body: jsonEncode(body),
    );
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw RoutesApiException('Google returned an unreadable response (HTTP ${res.statusCode})');
    }
    if (res.statusCode != 200) {
      final err = json is Map ? json['error'] : null;
      final msg = err is Map ? err['message'] : null;
      final detail = msg == null ? '' : ': $msg';
      throw RoutesApiException('Google Routes API error (HTTP ${res.statusCode})$detail');
    }
    return parseResponse(json as Map<String, dynamic>, name: name);
  }

  static Map<String, dynamic> _waypoint(Stop s) {
    if (s.location != null) {
      return {
        'location': {
          'latLng': {'latitude': s.location!.lat, 'longitude': s.location!.lng},
        },
      };
    }
    if (s.address != null) return {'address': s.address};
    throw ArgumentError('Current location must be resolved before calling the Routes API');
  }

  /// Turns a `computeRoutes` response into a [NavRoute], keeping Google's own
  /// turn instructions. A step's maneuver happens where that step starts.
  static NavRoute parseResponse(Map<String, dynamic> json, {required String name}) {
    final routes = json['routes'] as List?;
    if (routes == null || routes.isEmpty) {
      throw RoutesApiException('Google found no bike route between these places');
    }
    final points = <LatLng>[];
    final pending = <(int, TurnDirection, String?)>[];
    var firstStep = true;
    for (final leg in (routes.first['legs'] as List? ?? const [])) {
      for (final step in (leg['steps'] as List? ?? const [])) {
        final encoded = (step['polyline'] as Map?)?['encodedPolyline'] as String?;
        if (encoded == null) continue;
        final stepPoints = decodePolyline(encoded);
        if (stepPoints.isEmpty) continue;
        // Consecutive steps share their joining point.
        final startIndex = points.isNotEmpty && points.last == stepPoints.first ? points.length - 1 : points.length;
        points.addAll(startIndex == points.length ? stepPoints : stepPoints.skip(1));

        final nav = step['navigationInstruction'] as Map?;
        final direction = firstStep ? null : directionFor(nav?['maneuver'] as String?);
        if (direction != null) pending.add((startIndex, direction, nav?['instructions'] as String?));
        firstStep = false;
      }
    }
    if (points.length < 2) throw RoutesApiException('Google returned an empty route');

    final probe = NavRoute(name: name, points: points, maneuvers: const []);
    final cum = probe.cumulativeDistances;
    final maneuvers = [
      for (final (i, dir, text) in pending)
        if (i > 0 && i < points.length - 1)
          Maneuver(pointIndex: i, direction: dir, distanceFromStart: cum[i], instruction: text),
      Maneuver(pointIndex: points.length - 1, direction: TurnDirection.arrive, distanceFromStart: cum.last),
    ];
    return NavRoute(name: name, points: points, maneuvers: maneuvers);
  }

  /// Maps a Routes API maneuver to the arrow the HUD shows. Returns null for
  /// steps that don't need a cue (straight on, name change, merge, depart).
  static TurnDirection? directionFor(String? maneuver) => switch (maneuver) {
        'TURN_SLIGHT_LEFT' || 'FORK_LEFT' || 'RAMP_LEFT' => TurnDirection.slightLeft,
        'TURN_LEFT' || 'ROUNDABOUT_LEFT' => TurnDirection.left,
        'TURN_SHARP_LEFT' => TurnDirection.sharpLeft,
        'UTURN_LEFT' || 'UTURN_RIGHT' => TurnDirection.uTurn,
        'TURN_SLIGHT_RIGHT' || 'FORK_RIGHT' || 'RAMP_RIGHT' => TurnDirection.slightRight,
        'TURN_RIGHT' || 'ROUNDABOUT_RIGHT' => TurnDirection.right,
        'TURN_SHARP_RIGHT' => TurnDirection.sharpRight,
        _ => null,
      };
}

