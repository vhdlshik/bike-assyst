import 'dart:convert';

import 'package:bike_assyst/geo/geo.dart';
import 'package:bike_assyst/route/google/maps_import.dart';
import 'package:bike_assyst/route/google/maps_link.dart';
import 'package:bike_assyst/route/google/polyline.dart';
import 'package:bike_assyst/route/google/routes_api.dart';
import 'package:bike_assyst/route/route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Reference encoder, used to build fake API responses.
String encodePolyline(List<LatLng> pts) {
  final out = StringBuffer();
  var pLat = 0, pLng = 0;
  void enc(int v) {
    var x = v < 0 ? ~(v << 1) : v << 1;
    while (x >= 0x20) {
      out.writeCharCode((0x20 | (x & 0x1f)) + 63);
      x >>= 5;
    }
    out.writeCharCode(x + 63);
  }

  for (final p in pts) {
    final lat = (p.lat * 1e5).round(), lng = (p.lng * 1e5).round();
    enc(lat - pLat);
    enc(lng - pLng);
    pLat = lat;
    pLng = lng;
  }
  return out.toString();
}

Map<String, dynamic> step(List<LatLng> pts, [String? maneuver, String? text]) => {
      'polyline': {'encodedPolyline': encodePolyline(pts)},
      if (maneuver != null) 'navigationInstruction': {'maneuver': maneuver, 'instructions': ?text},
    };

const a = LatLng(50.45, 30.52), b = LatLng(50.453, 30.52), c = LatLng(50.453, 30.525), d = LatLng(50.456, 30.525);

/// North, then right (east), then left (north).
final sampleResponse = {
  'routes': [
    {
      'distanceMeters': 1000,
      'legs': [
        {
          'steps': [
            step([a, b], 'DEPART', 'Head north'),
            step([b, c], 'TURN_RIGHT', 'Turn right onto Main St'),
            step([c, d], 'TURN_LEFT', 'Turn left onto Park Ave'),
          ],
        },
      ],
    },
  ],
};

void main() {
  group('decodePolyline', () {
    test('decodes Google\'s documented example', () {
      final pts = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(pts, const [LatLng(38.5, -120.2), LatLng(40.7, -120.95), LatLng(43.252, -126.453)]);
    });

    test('round-trips with the encoder', () {
      expect(decodePolyline(encodePolyline([a, b, c, d])), [a, b, c, d]);
    });
  });

  group('MapsLink.parseStops', () {
    List<Stop> parse(String url) => MapsLink.parseStops(Uri.parse(url));

    test('browser directions with names and a waypoint', () {
      expect(parse('https://www.google.com/maps/dir/Kyiv+Railway+Station/Maidan+Nezalezhnosti/Podil,+Kyiv/@50.45,30.5,14z/data=!4m2!4m1!3e1'), const [
        Stop.address('Kyiv Railway Station'),
        Stop.address('Maidan Nezalezhnosti'),
        Stop.address('Podil, Kyiv'),
      ]);
    });

    test('browser directions with coordinates and an empty origin', () {
      expect(parse('https://www.google.com/maps/dir//50.4501,30.5234/@50.45,30.52,15z'), const [
        Stop.current(),
        Stop.location(LatLng(50.4501, 30.5234)),
      ]);
    });

    test('percent-encoded names keep a literal plus', () {
      expect(parse('https://www.google.com/maps/dir/A%2BB/Caf%C3%A9+Central/').map((s) => s.address), ['A+B', 'Café Central']);
    });

    test('Maps URLs API form with waypoints', () {
      expect(parse('https://www.google.com/maps/dir/?api=1&origin=Home+St&destination=50.46,30.53&waypoints=Park|Bridge+Rd&travelmode=bicycling'), const [
        Stop.address('Home St'),
        Stop.address('Park'),
        Stop.address('Bridge Rd'),
        Stop.location(LatLng(50.46, 30.53)),
      ]);
    });

    test('Maps URLs API form without origin starts here', () {
      expect(parse('https://www.google.com/maps/dir/?api=1&destination=Zoo').first.isCurrentLocation, isTrue);
    });

    test('old saddr/daddr form with "to:" waypoints', () {
      expect(parse('https://maps.google.com/maps?saddr=My+Location&daddr=Park+to:Zoo'), const [
        Stop.current(),
        Stop.address('Park'),
        Stop.address('Zoo'),
      ]);
    });

    test('a place link routes from here to the pin coordinates', () {
      expect(parse('https://www.google.com/maps/place/Golden+Gate/@50.4,30.5,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d50.4485!4d30.5132'), const [
        Stop.current(),
        Stop.location(LatLng(50.4485, 30.5132)),
      ]);
    });

    test('rejects other sites and links without a destination', () {
      expect(() => parse('https://example.com/maps/dir/A/B'), throwsA(isA<MapsLinkException>()));
      expect(() => parse('https://www.google.com/maps/dir/'), throwsA(isA<MapsLinkException>()));
      expect(() => parse('https://www.google.com/search?q=bikes'), throwsA(isA<MapsLinkException>()));
    });
  });

  test('findUrl pulls the link out of shared text', () {
    expect(MapsLink.findUrl('Golden Gate\nhttps://maps.app.goo.gl/abc123 ').toString(), 'https://maps.app.goo.gl/abc123');
    expect(MapsLink.findUrl('no link here'), isNull);
  });

  test('resolveShortLink follows redirects without following the final page', () async {
    final client = MockClient.streaming((req, _) async {
      final loc = switch (req.url.toString()) {
        'https://maps.app.goo.gl/abc' => 'https://goo.gl/maps/xyz',
        'https://goo.gl/maps/xyz' => 'https://www.google.com/maps/dir/A/B/',
        _ => null,
      };
      expect(loc, isNotNull, reason: 'unexpected request to ${req.url}');
      return http.StreamedResponse(const Stream.empty(), 302, headers: {'location': loc!});
    });
    final out = await MapsLink.resolveShortLink(Uri.parse('https://maps.app.goo.gl/abc'), client);
    expect(out.toString(), 'https://www.google.com/maps/dir/A/B/');
  });

  group('GoogleRoutesClient', () {
    test('parseResponse keeps Google\'s turns at step starts and skips depart', () {
      final r = GoogleRoutesClient.parseResponse(sampleResponse, name: 'x');
      expect(r.points, [a, b, c, d]);
      expect(r.maneuvers.map((m) => m.direction), [TurnDirection.right, TurnDirection.left, TurnDirection.arrive]);
      expect(r.maneuvers.first.pointIndex, 1);
      expect(r.maneuvers.first.instruction, 'Turn right onto Main St');
      expect(r.maneuvers.first.distanceFromStart, closeTo(334, 2));
    });

    test('empty routes means no bike route', () {
      expect(() => GoogleRoutesClient.parseResponse({}, name: 'x'), throwsA(isA<RoutesApiException>()));
    });

    test('maps every turning maneuver and ignores the rest', () {
      expect(GoogleRoutesClient.directionFor('ROUNDABOUT_RIGHT'), TurnDirection.right);
      expect(GoogleRoutesClient.directionFor('FORK_LEFT'), TurnDirection.slightLeft);
      expect(GoogleRoutesClient.directionFor('UTURN_RIGHT'), TurnDirection.uTurn);
      expect(GoogleRoutesClient.directionFor('STRAIGHT'), isNull);
      expect(GoogleRoutesClient.directionFor('NAME_CHANGE'), isNull);
      expect(GoogleRoutesClient.directionFor(null), isNull);
    });

    test('sends a bicycle request with key and field mask', () async {
      late http.Request sent;
      final client = MockClient((req) async {
        sent = req;
        return http.Response(jsonEncode(sampleResponse), 200);
      });
      await GoogleRoutesClient(apiKey: 'KEY', client: client).fetchBikeRoute(const [
        Stop.location(LatLng(50.45, 30.52)),
        Stop.address('Park'),
        Stop.address('Zoo'),
      ], name: 'x');
      expect(sent.url, GoogleRoutesClient.endpoint);
      expect(sent.headers['X-Goog-Api-Key'], 'KEY');
      expect(sent.headers['X-Goog-FieldMask'], contains('navigationInstruction'));
      final body = jsonDecode(sent.body) as Map;
      expect(body['travelMode'], 'BICYCLE');
      expect(body['origin'], {
        'location': {
          'latLng': {'latitude': 50.45, 'longitude': 30.52},
        },
      });
      expect(body['intermediates'], [
        {'address': 'Park'},
      ]);
      expect(body['destination'], {'address': 'Zoo'});
    });

    test('surfaces Google\'s error message', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'error': {'code': 403, 'message': 'API key not valid.'},
          }),
          403));
      expect(
        GoogleRoutesClient(apiKey: 'bad', client: client)
            .fetchBikeRoute(const [Stop.address('A'), Stop.address('B')], name: 'x'),
        throwsA(isA<RoutesApiException>().having((e) => e.message, 'message', contains('API key not valid'))),
      );
    });
  });

  test('MapsImporter fills in the current location only when the link needs it', () async {
    var gpsCalls = 0;
    late Map body;
    final client = MockClient((req) async {
      body = jsonDecode(req.body) as Map;
      return http.Response(jsonEncode(sampleResponse), 200);
    });
    final importer = MapsImporter(
      apiKey: 'KEY',
      client: client,
      currentLocation: () async {
        gpsCalls++;
        return const LatLng(1, 2);
      },
    );

    final route = await importer.import('Zoo https://www.google.com/maps/dir/?api=1&destination=Zoo');
    expect(gpsCalls, 1);
    expect(route.name, 'To Zoo');
    expect((body['origin'] as Map)['location'], {
      'latLng': {'latitude': 1.0, 'longitude': 2.0},
    });

    await importer.import('https://www.google.com/maps/dir/Home/Zoo');
    expect(gpsCalls, 1);
  });
}
