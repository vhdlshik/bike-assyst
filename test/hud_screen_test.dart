import 'dart:async';

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
}
