import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

/// Which of the phone's cameras looks back at the road behind the rider.
///
/// On a handlebar mount with the screen toward the rider that is the front
/// (selfie) camera; on a rear rack or backpack facing backwards it is the
/// back camera.
enum RearLens {
  front('Front camera', 'Phone on the handlebar, screen toward you'),
  back('Back camera', 'Phone behind you, back camera facing the road');

  const RearLens(this.label, this.hint);
  final String label;
  final String hint;
}

/// A live picture of the road behind, shown in a corner of the HUD.
abstract class RearCamera {
  /// Opens the camera. Returns null when ready, or why it isn't.
  Future<String?> start();

  /// The live picture, mirrored like a rear-view mirror.
  Widget preview();

  /// Stop or restart frames while the picture is hidden, to save battery.
  Future<void> pause();
  Future<void> resume();

  Future<void> dispose();
}

class DeviceRearCamera implements RearCamera {
  DeviceRearCamera(this.lens);

  final RearLens lens;
  CameraController? _controller;

  @override
  Future<String?> start() async {
    try {
      final cameras = await availableCameras();
      final want = lens == RearLens.front ? CameraLensDirection.front : CameraLensDirection.back;
      final match = cameras.where((c) => c.lensDirection == want);
      if (match.isEmpty) return 'This phone has no ${lens.label.toLowerCase()}';
      // A small corner picture needs little resolution, and low saves battery.
      final controller = CameraController(match.first, ResolutionPreset.low, enableAudio: false);
      await controller.initialize();
      _controller = controller;
      return null;
    } on CameraException catch (e) {
      return e.code == 'CameraAccessDenied' || e.code == 'CameraAccessDeniedWithoutPrompt'
          ? 'Camera permission denied, so no rear view'
          : 'Rear camera unavailable: ${e.description ?? e.code}';
    }
  }

  @override
  Widget preview() {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    // The front camera's preview is already mirrored; the back camera's
    // isn't, so flip it to read like a mirror.
    final picture = CameraPreview(controller);
    return lens == RearLens.back ? Transform.flip(flipX: true, child: picture) : picture;
  }

  @override
  Future<void> pause() async => _guard(() => _controller?.pausePreview());

  @override
  Future<void> resume() async => _guard(() => _controller?.resumePreview());

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }

  Future<void> _guard(Future<void>? Function() call) async {
    try {
      await call();
    } on CameraException catch (_) {}
  }
}
