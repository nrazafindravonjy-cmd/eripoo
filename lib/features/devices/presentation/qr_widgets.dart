import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/qr_codec.dart';

/// A QR code drawn black on white (whatever the theme: scanners need the
/// contrast), with the quiet zone the standard asks for.
class QrCodeView extends StatelessWidget {
  QrCodeView({super.key, required this.data, this.size = 260})
    : _modules = QrCodec.encode(data);

  /// The encoded text.
  final String data;
  final List<List<bool>> _modules;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    child: Container(
      color: EripooFixedColors.qrLight,
      width: size,
      height: size,
      child: CustomPaint(painter: _QrPainter(_modules)),
    ),
  );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.modules);
  final List<List<bool>> modules;

  @override
  void paint(Canvas canvas, Size size) {
    const quiet = 4;
    final count = modules.length + 2 * quiet;
    final cell = size.width / count;
    final paint = Paint()..color = EripooFixedColors.qrDark;
    for (var r = 0; r < modules.length; r++) {
      for (var c = 0; c < modules.length; c++) {
        if (!modules[r][c]) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            (c + quiet) * cell,
            (r + quiet) * cell,
            cell + 0.5,
            cell + 0.5,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.modules != modules;
}

/// Opens the scanner and returns the text of the first code starting with
/// [prefix], or null (cancelled, no camera). Overridden in tests.
typedef QrScan = Future<String?> Function(
  BuildContext context, {
  required String prefix,
});

final qrScanProvider = Provider<QrScan>(
  (ref) =>
      (context, {required prefix}) => Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => QrScanScreen(prefix: prefix)),
      ),
);

/// The camera preview; frames are decoded on a background isolate, about
/// four per second, so the preview stays fluid on entry-level phones.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key, required this.prefix});
  final String prefix;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  CameraController? _camera;
  bool _unavailable = false;
  bool _busy = false;
  bool _done = false;
  final _sinceLast = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final camera = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await camera.initialize();
      if (!mounted) {
        await camera.dispose();
        return;
      }
      setState(() => _camera = camera);
      await camera.startImageStream(_onFrame);
    } on Object {
      // Permission refused, no camera, camera busy.
      if (mounted) setState(() => _unavailable = true);
    }
  }

  void _onFrame(CameraImage image) {
    if (_busy || _done || _sinceLast.elapsedMilliseconds < 250) return;
    _busy = true;
    _sinceLast.reset();
    final plane = image.planes.first; // Y: grey levels
    final job = (
      Uint8List.fromList(plane.bytes),
      image.width,
      image.height,
      plane.bytesPerRow,
    );
    compute(_decodeFrame, job)
        .then((text) {
          _busy = false;
          if (text == null || _done || !text.startsWith(widget.prefix)) return;
          _done = true;
          if (mounted) Navigator.of(context).pop(text);
        })
        .catchError((Object _) {
          _busy = false;
          return null;
        });
  }

  @override
  void dispose() {
    final camera = _camera;
    if (camera != null) {
      unawaited(
        (camera.value.isStreamingImages
                ? camera.stopImageStream()
                : Future<void>.value())
            .catchError((Object _) {})
            .whenComplete(camera.dispose),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final camera = _camera;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scannerTitle)),
      body: _unavailable
          ? EripooMessageView(
              icon: Icons.no_photography_outlined,
              title: l10n.scannerTitle,
              message: l10n.scannerUnavailable,
            )
          : camera == null
          ? const EripooLoadingView()
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1 / camera.value.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(camera),
                          Center(
                            child: FractionallySizedBox(
                              widthFactor: 0.7,
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: EripooFixedColors.scannerFrame,
                                      width: 3,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(EripooSpacing.lg),
                  child: Text(l10n.scannerHint, textAlign: TextAlign.center),
                ),
              ],
            ),
    );
  }
}

String? _decodeFrame((Uint8List, int, int, int) job) =>
    QrCodec.decode(job.$1, width: job.$2, height: job.$3, rowStride: job.$4);
