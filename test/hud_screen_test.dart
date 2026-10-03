import 'dart:async';

import 'package:bike_assyst/geo/geo.dart';
import 'package:bike_assyst/nav/position_source.dart';
import 'package:bike_assyst/route/demo_route.dart';
import 'package:bike_assyst/ui/hud_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSource implements PositionSource {
  final controller = StreamController<LatLng>();
  @override
  Stream<LatLng> get positions => controller.stream;
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
    await tester.pumpWidget(MaterialApp(home: HudScreen(route: route, source: source)));

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
}
