import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../camera/rear_camera.dart';
import '../head/head_tracker.dart';
import '../nav/position_source.dart';
import '../route/demo_route.dart';
import '../route/google/maps_import.dart';
import '../route/google/maps_link.dart';
import '../route/google/routes_api.dart';
import '../route/maneuver_detector.dart';
import '../route/route.dart';
import '../route/route_file_parser.dart';
import 'format.dart';
import 'hud_screen.dart';
import 'turn_arrow.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  NavRoute? _route;
  bool _simulate = false;
  bool _loading = false;
  RearLens? _rearLens = RearLens.front;
  bool _headTracking = true;

  Future<void> _importLink() async {
    if (GoogleRoutesClient.buildTimeApiKey.isEmpty) {
      _snack('No Google Maps API key in this build. See README: Google Maps API key.');
      return;
    }
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _LinkDialog(initial: MapsLink.findUrl(clip) != null ? clip.trim() : ''),
    );
    if (text == null || text.trim().isEmpty) return;

    setState(() => _loading = true);
    try {
      final importer = MapsImporter(
        apiKey: GoogleRoutesClient.buildTimeApiKey,
        currentLocation: () async {
          final error = await GpsPositionSource.ensurePermission();
          if (error != null) throw MapsLinkException('$error, needed for a route from your location');
          return GpsPositionSource.current();
        },
      );
      final route = await importer.import(text);
      if (mounted) setState(() => _route = route);
    } on MapsLinkException catch (e) {
      _snack(e.message);
    } on RoutesApiException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not load the route: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _import() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Import a route (GPX or KML)',
      type: FileType.custom,
      allowedExtensions: const ['gpx', 'kml'],
    );
    if (file == null) return;
    try {
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      final track = RouteFileParser.parse(text, fileName: file.name);
      setState(() => _route = const ManeuverDetector().build(track.name ?? file.name, track.points));
    } on RouteParseException catch (e) {
      _snack(e.message);
    }
  }

  void _loadDemo() => setState(() {
        _route = demoRoute();
        _simulate = true;
      });

  Future<void> _start() async {
    final route = _route;
    if (route == null) return;
    final PositionSource source;
    if (_simulate) {
      source = SimulatedPositionSource(route);
    } else {
      final error = await GpsPositionSource.ensurePermission();
      if (error != null) {
        _snack(error);
        return;
      }
      source = GpsPositionSource();
    }
    if (!mounted) return;
    final lens = _rearLens;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HudScreen(
        route: route,
        source: source,
        rearCamera: lens == null ? null : DeviceRearCamera(lens),
        headTracker: lens != null && _headTracking ? XrealHeadTracker() : null,
      ),
    ));
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final route = _route;
    return Scaffold(
      appBar: AppBar(title: const Text('Bike Assyst')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Route', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _loading ? null : _importLink,
              icon: const Icon(Icons.map),
              label: const Text('Google Maps link'),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _import,
              icon: const Icon(Icons.file_open),
              label: const Text('GPX / KML file'),
            ),
            OutlinedButton.icon(
              onPressed: _loadDemo,
              icon: const Icon(Icons.route),
              label: const Text('Demo route'),
            ),
          ]),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (route == null)
            const Text('No route loaded. Copy a Google Maps directions link, or import a GPX/KML file.')
          else ...[
            Card(
              child: ListTile(
                title: Text(route.name),
                subtitle: Text(
                    '${formatDistance(route.totalDistance)} · ${route.maneuvers.length - 1} turns'),
              ),
            ),
            SwitchListTile(
              title: const Text('Simulate ride'),
              subtitle: const Text('Move along the route without GPS'),
              value: _simulate,
              onChanged: (v) => setState(() => _simulate = v),
            ),
            ListTile(
              title: const Text('Rear view'),
              subtitle: Text(_rearLens?.hint ?? 'No camera picture before turns'),
              trailing: DropdownButton<RearLens?>(
                value: _rearLens,
                onChanged: (v) => setState(() => _rearLens = v),
                items: [
                  for (final lens in RearLens.values) DropdownMenuItem(value: lens, child: Text(lens.label)),
                  const DropdownMenuItem(value: null, child: Text('Off')),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Head tracking'),
              subtitle: const Text('XREAL Air glasses: show the rear view when you look over a shoulder, '
                  'instead of before turns'),
              value: _headTracking && _rearLens != null,
              onChanged: _rearLens == null ? null : (v) => setState(() => _headTracking = v),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _start, child: const Text('Start ride')),
            const SizedBox(height: 16),
            Text('Turns', style: Theme.of(context).textTheme.titleMedium),
            for (final m in route.maneuvers)
              ListTile(
                dense: true,
                leading: TurnArrow(direction: m.direction, size: 28, color: Theme.of(context).colorScheme.primary),
                title: Text(m.direction.label),
                subtitle: m.instruction == null ? null : Text(m.instruction!),
                trailing: Text(formatDistance(m.distanceFromStart)),
              ),
          ],
        ],
      ),
    );
  }
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.initial});
  final String initial;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Google Maps link'),
        content: TextField(
          controller: _controller,
          autofocus: widget.initial.isEmpty,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'https://maps.app.goo.gl/…',
            helperText: 'Directions or a place. A place is routed from where you are.',
            helperMaxLines: 2,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Get bike route')),
        ],
      );
}
