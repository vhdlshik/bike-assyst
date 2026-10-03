import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../nav/position_source.dart';
import '../route/demo_route.dart';
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
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HudScreen(route: route, source: source),
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
              onPressed: _import,
              icon: const Icon(Icons.file_open),
              label: const Text('Import GPX / KML'),
            ),
            OutlinedButton.icon(
              onPressed: _loadDemo,
              icon: const Icon(Icons.route),
              label: const Text('Demo route'),
            ),
          ]),
          const SizedBox(height: 16),
          if (route == null)
            const Text('No route loaded. Export your Google Maps route as GPX or KML and import it here.')
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
            const SizedBox(height: 8),
            FilledButton(onPressed: _start, child: const Text('Start ride')),
            const SizedBox(height: 16),
            Text('Turns', style: Theme.of(context).textTheme.titleMedium),
            for (final m in route.maneuvers)
              ListTile(
                dense: true,
                leading: TurnArrow(direction: m.direction, size: 28, color: Theme.of(context).colorScheme.primary),
                title: Text(m.direction.label),
                trailing: Text(formatDistance(m.distanceFromStart)),
              ),
          ],
        ],
      ),
    );
  }
}
