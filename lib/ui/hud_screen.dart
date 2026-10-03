import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../nav/navigation_engine.dart';
import '../nav/position_source.dart';
import '../route/route.dart';
import 'format.dart';
import 'screen_dimmer.dart';
import 'turn_arrow.dart';

/// The ride view shown on the AR glasses.
///
/// Optical see-through glasses (Nreal/XREAL) render black as transparent, so
/// the screen stays pure black and the road stays visible. An arrow appears
/// only when a turn is coming up.
///
/// The phone's own screen is dimmed for the ride. Tapping it or pressing a
/// phone button (such as volume) lights it up and shows the ride controls for
/// a few seconds; it lights up for good on arrival.
class HudScreen extends StatefulWidget {
  const HudScreen({
    super.key,
    required this.route,
    required this.source,
    this.announceMeters = 150,
    this.dimmer = const BrightnessScreenDimmer(),
  });

  final NavRoute route;
  final PositionSource source;

  /// Show the turn arrow when the turn is this close.
  final double announceMeters;

  /// Dims the phone screen while riding; pass null to leave it alone.
  final ScreenDimmer? dimmer;

  @override
  State<HudScreen> createState() => _HudScreenState();
}

class _HudScreenState extends State<HudScreen> {
  late final NavigationEngine _engine = NavigationEngine(widget.route);
  StreamSubscription<dynamic>? _sub;
  NavState? _state;
  bool _controlsVisible = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    widget.dimmer?.dim();
    _sub = widget.source.positions.listen((p) {
      final arrivedBefore = _state?.arrived ?? false;
      setState(() => _state = _engine.update(p));
      if (_state!.arrived && !arrivedBefore) widget.dimmer?.restore();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hideTimer?.cancel();
    widget.dimmer?.restore();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _showControls() {
    if (!_controlsVisible) widget.dimmer?.restore();
    setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
      if (!(_state?.arrived ?? false)) widget.dimmer?.dim();
    });
  }

  // Wake on any phone button, but leave the press to the system too, so
  // volume keys still change the volume.
  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent) _showControls();
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final m = s?.nextManeuver;
    final showArrow = s != null && m != null && !s.offRoute && s.distanceToManeuver <= widget.announceMeters;
    // Turn cues sit on the side of the turn, leaving the centre of view clear.
    final alignment = m == null || !showArrow
        ? Alignment.center
        : m.direction.isLeft
            ? const Alignment(-0.7, 0.5)
            : m.direction.isRight
                ? const Alignment(0.7, 0.5)
                : const Alignment(0, 0.5);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showControls,
          child: Stack(
            children: [
              if (showArrow)
                Align(
                  alignment: alignment,
                  child: Column(
                    key: const Key('turn-cue'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TurnArrow(direction: m.direction, size: 140),
                      const SizedBox(height: 8),
                      Text(
                        m.direction == TurnDirection.arrive
                            ? formatDistance(s.distanceToManeuver)
                            : '${m.direction.label} · ${formatDistance(s.distanceToManeuver)}',
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              if (s != null && s.offRoute)
                const Align(
                  alignment: Alignment(0, -0.8),
                  child: Text('Off route',
                      style: TextStyle(color: Colors.amber, fontSize: 26, fontWeight: FontWeight.w600)),
                ),
              if (s != null && s.arrived)
                const Center(
                  child: Text('Arrived',
                      style: TextStyle(color: Colors.greenAccent, fontSize: 40, fontWeight: FontWeight.w700)),
                ),
              if (_controlsVisible) _controls(context, s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, NavState? s) => SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  s == null ? 'Waiting for GPS…' : '${formatDistance(s.remaining)} to go',
                  style: const TextStyle(color: Colors.white70, fontSize: 20),
                ),
                FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('End ride'),
                ),
              ],
            ),
          ),
        ),
      );
}
