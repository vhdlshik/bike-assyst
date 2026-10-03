import 'package:http/http.dart' as http;

import '../../geo/geo.dart';
import '../route.dart';
import 'maps_link.dart';
import 'routes_api.dart';

/// Turns a pasted or shared Google Maps link into a bike [NavRoute].
class MapsImporter {
  MapsImporter({required this.apiKey, required this.currentLocation, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;

  /// Called only when the link starts (or ends) at "my location".
  final Future<LatLng> Function() currentLocation;
  final http.Client _client;

  Future<NavRoute> import(String text) async {
    var uri = MapsLink.findUrl(text);
    if (uri == null) throw MapsLinkException('Paste a Google Maps link');
    if (MapsLink.isShortLink(uri)) uri = await MapsLink.resolveShortLink(uri, _client);

    final stops = MapsLink.parseStops(uri);
    LatLng? here;
    final resolved = <Stop>[
      for (final s in stops)
        if (s.isCurrentLocation) Stop.location(here ??= await currentLocation()) else s,
    ];
    final dest = stops.last;
    final name = dest.address != null ? 'To ${dest.address}' : 'Google Maps route';
    return GoogleRoutesClient(apiKey: apiKey, client: _client).fetchBikeRoute(resolved, name: name);
  }
}
