import 'package:bike_assyst/geo/geo.dart';
import 'package:bike_assyst/route/demo_route.dart';
import 'package:bike_assyst/route/maneuver_detector.dart';
import 'package:bike_assyst/route/route.dart';
import 'package:bike_assyst/route/route_file_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo route has right, slight left, left, right turns then arrival', () {
    final r = demoRoute();
    expect(r.maneuvers.map((m) => m.direction), [
      TurnDirection.right,
      TurnDirection.slightLeft,
      TurnDirection.left,
      TurnDirection.right,
      TurnDirection.arrive,
    ]);
    expect(r.maneuvers.first.distanceFromStart, closeTo(300, 2));
    expect(r.totalDistance, closeTo(1150, 15));
  });

  test('classify maps angles to directions', () {
    expect(ManeuverDetector.classify(40), TurnDirection.slightRight);
    expect(ManeuverDetector.classify(-90), TurnDirection.left);
    expect(ManeuverDetector.classify(130), TurnDirection.sharpRight);
    expect(ManeuverDetector.classify(-170), TurnDirection.uTurn);
  });

  test('a straight jittery track has no turns', () {
    final pts = [
      for (var i = 0; i < 50; i++)
        // ~1 m sideways jitter on a 500 m straight line.
        LatLng(50 + i * 0.0001, 30 + (i.isEven ? 0.00001 : -0.00001)),
    ];
    final r = const ManeuverDetector().build('straight', pts);
    expect(r.maneuvers.single.direction, TurnDirection.arrive);
  });

  test('parses GPX tracks', () {
    const gpx = '''<?xml version="1.0"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>Morning ride</name><trkseg>
    <trkpt lat="50.0" lon="30.0"/><trkpt lat="50.001" lon="30.0"/><trkpt lat="50.001" lon="30.002"/>
  </trkseg></trk>
</gpx>''';
    final t = RouteFileParser.parse(gpx);
    expect(t.name, 'Morning ride');
    expect(t.points, hasLength(3));
    expect(t.points.last.lng, 30.002);
  });

  test('parses GPX routes when there is no track', () {
    const gpx = '<gpx><rte><rtept lat="1" lon="2"/><rtept lat="1.1" lon="2"/></rte></gpx>';
    expect(RouteFileParser.parse(gpx).points, hasLength(2));
  });

  test('parses KML LineStrings (Google My Maps export)', () {
    const kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"><Document><name>Trip</name>
  <Placemark><name>Directions to Park</name><LineString><coordinates>
    30.0,50.0,0 30.0,50.001,0
    30.002,50.001,0
  </coordinates></LineString></Placemark>
</Document></kml>''';
    final t = RouteFileParser.parse(kml);
    expect(t.name, 'Directions to Park');
    expect(t.points, hasLength(3));
    expect(t.points.first.lat, 50.0);
    expect(t.points.first.lng, 30.0);
  });

  test('rejects files without a usable route', () {
    expect(() => RouteFileParser.parse('<gpx/>'), throwsA(isA<RouteParseException>()));
    expect(() => RouteFileParser.parse('<html/>'), throwsA(isA<RouteParseException>()));
    expect(() => RouteFileParser.parse('not xml'), throwsA(isA<RouteParseException>()));
  });
}
