import 'package:screen_brightness/screen_brightness.dart';

/// Turns the phone's own screen down while riding and back up on demand.
///
/// Only the app's window brightness changes, so the system setting is left
/// alone and comes back by itself when the app closes. On Android this dims
/// the phone panel's backlight; glasses on USB-C get their picture over
/// DisplayPort and keep their own brightness.
abstract class ScreenDimmer {
  Future<void> dim();
  Future<void> restore();
}

class BrightnessScreenDimmer implements ScreenDimmer {
  const BrightnessScreenDimmer();

  @override
  Future<void> dim() => _guard(() => ScreenBrightness.instance.setApplicationScreenBrightness(0));

  @override
  Future<void> restore() => _guard(ScreenBrightness.instance.resetApplicationScreenBrightness);

  // Brightness is a nicety: a platform that refuses it must not end the ride.
  Future<void> _guard(Future<void> Function() call) async {
    try {
      await call();
    } catch (_) {}
  }
}
