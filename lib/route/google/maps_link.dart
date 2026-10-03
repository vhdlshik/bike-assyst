import 'package:http/http.dart' as http;

import '../../geo/geo.dart';

class MapsLinkException implements Exception {
  MapsLinkException(this.message);
  final String message;
  @override
  String toString() => 'MapsLinkException: $message';
}

/// One stop of a Google Maps route: a place name/address, coordinates, or the
/// rider's current location.
class Stop {
  const Stop.address(String this.address) : location = null;
  const Stop.location(LatLng this.location) : address = null;
  const Stop.current()
      : address = null,
        location = null;

  final String? address;
  final LatLng? location;

  bool get isCurrentLocation => address == null && location == null;

  @override
  bool operator ==(Object other) =>
      other is Stop && other.address == address && other.location == location;

  @override
  int get hashCode => Object.hash(address, location);

  @override
  String toString() => isCurrentLocation ? 'Stop.current()' : 'Stop(${address ?? location})';
}

/// Reads the stops out of a Google Maps link.
///
/// Handles the URL shapes Google Maps produces:
/// - `/maps/dir/A/B/C/@lat,lng,zoom/data=...` (directions in the browser)
/// - `/maps/dir/?api=1&origin=..&destination=..&waypoints=a|b` (Maps URLs API)
/// - `/maps?saddr=..&daddr=B+to:C` (older links)
/// - `/maps/place/Name/@...` and `?q=` (a single place: ride there from here)
/// - `maps.app.goo.gl/...` short links, after [resolveShortLink].
class MapsLink {
  MapsLink._();

  static final _urlInText = RegExp(r'https?://\S+');
  static final _latLng = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$');
  static const _currentNames = {'my location', 'your location', 'current location'};

  /// Finds the first URL in pasted text (the Maps app shares "Place name
  /// https://maps.app.goo.gl/...").
  static Uri? findUrl(String text) {
    final m = _urlInText.firstMatch(text.trim());
    return m == null ? null : Uri.tryParse(m.group(0)!);
  }

  static bool isShortLink(Uri uri) =>
      uri.host == 'maps.app.goo.gl' || (uri.host == 'goo.gl' && uri.path.startsWith('/maps'));

  /// Follows redirects of a short link until it reaches a full Maps URL.
  static Future<Uri> resolveShortLink(Uri uri, http.Client client) async {
    var current = uri;
    for (var hop = 0; hop < 5 && isShortLink(current); hop++) {
      final req = http.Request('GET', current)..followRedirects = false;
      final res = await client.send(req);
      await res.stream.drain<void>();
      final location = res.headers['location'];
      if (res.statusCode < 300 || res.statusCode >= 400 || location == null) {
        throw MapsLinkException('Could not open the short link (HTTP ${res.statusCode})');
      }
      current = current.resolve(location);
    }
    return current;
  }

  /// Returns the stops in riding order: origin, any waypoints, destination.
  static List<Stop> parseStops(Uri uri) {
    if (!_isGoogleMaps(uri)) throw MapsLinkException('This is not a Google Maps link');
    final q = uri.queryParameters;
    // Raw (still percent-encoded) segments, so '+' and '%2B' stay distinguishable.
    final segments = uri.path.split('/').skip(1).toList();
    final dirIndex = segments.indexOf('dir');

    if (dirIndex >= 0 && q['api'] == '1') {
      final dest = q['destination'];
      if (dest == null || dest.isEmpty) throw MapsLinkException('The link has no destination');
      return [
        _stop(q['origin']),
        for (final w in (q['waypoints'] ?? '').split('|'))
          if (w.trim().isNotEmpty) _stop(w),
        _stop(dest),
      ];
    }

    if (dirIndex >= 0) {
      final parts = <String>[];
      for (final s in segments.skip(dirIndex + 1)) {
        if (s.startsWith('@') || s.startsWith('data=')) break;
        parts.add(s);
      }
      // A trailing slash yields an empty last segment; an empty first one means
      // "from my location".
      while (parts.isNotEmpty && parts.last.isEmpty) {
        parts.removeLast();
      }
      if (parts.isEmpty) throw MapsLinkException('The link has no destination');
      final stops = parts.map((p) => _stop(_decodePath(p))).toList();
      if (stops.length == 1) stops.insert(0, const Stop.current());
      return stops;
    }

    if (q.containsKey('daddr')) {
      final dests = q['daddr']!.split(RegExp(r'\s+to:', caseSensitive: false));
      return [_stop(q['saddr']), for (final d in dests) _stop(d)];
    }

    final placeIndex = segments.indexOf('place');
    if (placeIndex >= 0 && placeIndex + 1 < segments.length) {
      return [const Stop.current(), _placeStop(segments, placeIndex)];
    }
    final query = q['q'] ?? q['query'] ?? q['destination'];
    if (query != null && query.isNotEmpty) return [const Stop.current(), _stop(query)];

    throw MapsLinkException('Could not find a route or place in this link');
  }

  static bool _isGoogleMaps(Uri uri) {
    final host = uri.host.toLowerCase();
    final isGoogle = RegExp(r'(^|\.)google\.[a-z.]+$').hasMatch(host);
    return (isGoogle && (uri.path.startsWith('/maps') || host.startsWith('maps.'))) ||
        isShortLink(uri);
  }

  static String _decodePath(String s) {
    try {
      return Uri.decodeComponent(s.replaceAll('+', ' '));
    } on ArgumentError {
      return s.replaceAll('+', ' ');
    }
  }

  static Stop _placeStop(List<String> segments, int placeIndex) {
    // Prefer the pin's exact coordinates from the "!3d<lat>!4d<lng>" data blob.
    final data = segments.firstWhere((s) => s.startsWith('data='), orElse: () => '');
    final m = RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)').firstMatch(data);
    if (m != null) return Stop.location(LatLng(double.parse(m.group(1)!), double.parse(m.group(2)!)));
    return _stop(_decodePath(segments[placeIndex + 1]));
  }

  static Stop _stop(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty || _currentNames.contains(s.toLowerCase())) return const Stop.current();
    final m = _latLng.firstMatch(s);
    if (m != null) {
      final lat = double.parse(m.group(1)!), lng = double.parse(m.group(2)!);
      if (lat.abs() <= 90 && lng.abs() <= 180) return Stop.location(LatLng(lat, lng));
    }
    return Stop.address(s);
  }
}
