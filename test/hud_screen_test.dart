import 'dart:async';

import 'package:bike_assyst/camera/rear_camera.dart';
import 'package:bike_assyst/geo/geo.dart';
import 'package:bike_assyst/nav/position_source.dart';
import 'package:bike_assyst/route/demo_route.dart';
import 'package:bike_assyst/ui/hud_screen.dart';
import 'package:bike_assyst/ui/screen_dimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSource implements PositionSource {
  final controller = StreamController<LatLng>();
  @override
  Stream<LatLng> get positions => controller.stream;
}

class _FakeDimmer implements ScreenDimmer {
  final calls = <String>[];
  bool get dimmed => calls.isNotEmpty && calls.last == 'dim';
  @override
  Future<void> dim() async => calls.add('dim');
  @override
  Future<void> restore() async => calls.add('restore');
}

class _FakeRearCamera implements RearCamera {
  _FakeRearCamera([this.error]);
  final String? error;
  final calls = <String>[];
  Completer<void>? opening;
  bool get running => calls.lastWhere((c) => c == 'pause' || c == 'resume', orElse: () => '') == 'resume';
  @override
  Future<String?> start() async {
    calls.add('start');
    await opening?.future;
    calls.add('opened');
    return error;
  }

  @override
  Widget preview() => const ColoredBox(color: Colors.blue);
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> resume() async => calls.add('resume');
  @override
  Future<void> dispose() async => calls.add('dispose');
}

void main() {
  setUp(() {
    // Wakelock talks to the platform; answer its calls with nothing.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
            (_) async => const StandardMessageCodec().encodeMessage(<Object?>[]));
  });

  testWidgets('HUD is empty far from a turn and shows the arrow near one', (tester) async {
    final route = demoRoute();
    final source = _FakeSource();
    await tester.pumpWidget(MaterialApp(home: HudScreen(route: route, source: source, dimmer: _FakeDimmer())));

    source.controller.add(route.points.first); // 300 m before the first turn
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('turn-cue')), findsNothing);

    source.controller.add(route.points[10]); // 100 m before it
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('turn-cue')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Turn right · (99|100) m$')), findsOneWidget);
  });

  testWidgets('phone screen is dimmed for the ride and lights up on demand', (tester) async {
    final route = demoRoute();
    final source = _FakeSource();
    final dimmer = _FakeDimmer();
    await tester.pumpWidget(MaterialApp(home: HudScreen(route: route, source: source, dimmer: dimmer)));
    expect(dimmer.dimmed, isTrue);

    await tester.tap(find.byType(HudScreen));
    await tester.pump();
    expect(dimmer.dimmed, isFalse);
    expect(find.text('End ride'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('End ride'), findsNothing);
    expect(dimmer.dimmed, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
    await tester.pump();
    expect(dimmer.dimmed, isFalse);
    expect(find.text('End ride'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(dimmer.dimmed, isTrue);

    source.controller.add(route.points.last);
    await tester.pump();
    await tester.pump();
    expect(find.text('Arrived'), findsOneWidget);
    expect(dimmer.dimmed, isFalse);

    await tester.pumpWidget(const SizedBox());
    expect(dimmer.calls.last, 'restore');
  });

  testWidgets('rear view shows on the side of a coming turn and runs only then', (tester) async {
    final route = demoRoute();
    final source = _FakeSource();
    final camera = _FakeRearCamera();
    await tester.pumpWidget(MaterialApp(
      home: HudScreen(route: route, source: source, dimmer: _FakeDimmer(), rearCamera: camera),
    ));
    await tester.pump();
    expect(camera.calls, ['start', 'opened', 'pause']);

    final rearView = find.byKey(const Key('rear-view'));
    final width = tester.getSize(find.byType(HudScreen)).width;

    source.controller.add(route.points.first); // 300 m before a right turn
    await tester.pump();
    await tester.pump();
    expect(rearView, findsNothing);
    expect(camera.running, isFalse);

    source.controller.add(route.points[10]); // 100 m before it
    await tester.pump();
    await tester.pump();
    expect(rearView, findsOneWidget);
    expect(tester.getTopLeft(rearView).dx, greaterThan(width / 2));
    expect(tester.getTopLeft(rearView).dy, lessThan(50));
    expect(camera.running, isTrue);

    source.controller.add(route.points[16]); // past it, 200 m before a slight left
    await tester.pump();
    await tester.pump();
    expect(rearView, findsNothing);
    expect(camera.running, isFalse);

    source.controller.add(route.points[20]); // 120 m before the slight left
    await tester.pump();
    await tester.pump();
    expect(rearView, findsOneWidget);
    expect(tester.getTopRight(rearView).dx, lessThan(width / 2));
    expect(camera.running, isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(camera.calls.last, 'dispose');
  });

  testWidgets('a rear camera that cannot start says why and stays hidden', (tester) async {
    final route = demoRoute();
    final source = _FakeSource();
    await tester.pumpWidget(MaterialApp(
      home: HudScreen(
          route: route, source: source, dimmer: _FakeDimmer(), rearCamera: _FakeRearCamera('No camera here')),
    ));
    await tester.pump();
    expect(find.text('No camera here'), findsOneWidget);

    source.controller.add(route.points[10]);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('turn-cue')), findsOneWidget);
    expect(find.byKey(const Key('rear-view')), findsNothing);
  });

  testWidgets('a ride ended while the camera opens still releases it', (tester) async {
    final camera = _FakeRearCamera()..opening = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      home: HudScreen(route: demoRoute(), source: _FakeSource(), dimmer: _FakeDimmer(), rearCamera: camera),
    ));
    await tester.pumpWidget(const SizedBox());
    camera.opening!.complete();
    await tester.pump();
    expect(camera.calls.skipWhile((c) => c != 'opened'), contains('dispose'));
  });
}
