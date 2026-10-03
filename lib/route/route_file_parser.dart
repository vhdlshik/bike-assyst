import 'package:xml/xml.dart';

import '../geo/geo.dart';

class RouteParseException implements Exception {
  RouteParseException(this.message);
  final String message;
  @override
  String toString() => 'RouteParseException: $message';
}

class ParsedTrack {
  const ParsedTrack(this.name, this.points);
  final String? name;
  final List<LatLng> points;
}

/// Parses GPX (tracks, routes) and KML (LineString, gx:Track) files into a
/// single ordered list of points.
///
/// KML is what Google My Maps exports; GPX is what most Google-Maps-link
/// converters and bike apps produce.
class RouteFileParser {
  static ParsedTrack parse(String content, {String? fileName}) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(content);
    } on XmlException catch (e) {
      throw RouteParseException('Not a valid XML file: ${e.message}');
    }
    final root = doc.rootElement.localName.toLowerCase();
    final track = switch (root) {
      'gpx' => _parseGpx(doc),
      'kml' => _parseKml(doc),
      _ => throw RouteParseException('Unsupported file type <$root>; expected GPX or KML'),
    };
    if (track.points.length < 2) {
      throw RouteParseException('The file has no route with at least two points');
    }
    return ParsedTrack(track.name ?? fileName, track.points);
  }

  static ParsedTrack _parseGpx(XmlDocument doc) {
    LatLng pt(XmlElement e) {
      final lat = double.tryParse(e.getAttribute('lat') ?? '');
      final lon = double.tryParse(e.getAttribute('lon') ?? '');
      if (lat == null || lon == null) throw RouteParseException('Point without lat/lon');
      return LatLng(lat, lon);
    }

    var points = doc.descendants
        .whereType<XmlElement>()
        .where((e) => e.localName == 'trkpt')
        .map(pt)
        .toList();
    if (points.isEmpty) {
      points = doc.descendants
          .whereType<XmlElement>()
          .where((e) => e.localName == 'rtept')
          .map(pt)
          .toList();
    }
    return ParsedTrack(_firstName(doc, const ['trk', 'rte', 'metadata']), points);
  }

  static ParsedTrack _parseKml(XmlDocument doc) {
    final points = <LatLng>[];
    for (final e in doc.descendants.whereType<XmlElement>()) {
      if (e.localName == 'LineString') {
        final coords = e.childElements.where((c) => c.localName == 'coordinates');
        for (final c in coords) {
          for (final tuple in c.innerText.trim().split(RegExp(r'\s+'))) {
            final parts = tuple.split(',');
            if (parts.length < 2) continue;
            final lng = double.tryParse(parts[0]);
            final lat = double.tryParse(parts[1]);
            if (lat != null && lng != null) points.add(LatLng(lat, lng));
          }
        }
      } else if (e.localName == 'coord' && e.namespacePrefix == 'gx') {
        final parts = e.innerText.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          final lng = double.tryParse(parts[0]);
          final lat = double.tryParse(parts[1]);
          if (lat != null && lng != null) points.add(LatLng(lat, lng));
        }
      }
    }
    return ParsedTrack(_firstName(doc, const ['Placemark', 'Document']), points);
  }

  static String? _firstName(XmlDocument doc, List<String> parents) {
    for (final parent in parents) {
      for (final e in doc.descendants.whereType<XmlElement>().where((e) => e.localName == parent)) {
        final name = e.childElements.where((c) => c.localName == 'name').firstOrNull?.innerText.trim();
        if (name != null && name.isNotEmpty) return name;
      }
    }
    return null;
  }
}
