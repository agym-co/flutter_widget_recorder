import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_recorder/flutter_widget_recorder.dart';
import 'package:share_plus/share_plus.dart';

class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Camera')),
      body: SafeArea(child: const _Body()),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  CameraController? _cameraController;

  final WidgetRecorderController _controller = WidgetRecorderController(
    captureFps: 30,
    isWithTicker: false,
  );

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final cameras = await availableCameras();
    final camera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );
    _cameraController = CameraController(
      camera,
      ResolutionPreset.max,
      enableAudio: false,
    );
    await _cameraController!.initialize();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
          child: WidgetRecorderWrapper(
            controller: _controller,
            child: CameraPreview(_cameraController!),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 10,
          children: [
            ListenableBuilder(
              listenable: _controller,
              builder: (context, child) {
                return ElevatedButton(
                  onPressed: () {
                    if (_controller.isRecording) {
                      _controller.stopRecording();
                    } else {
                      _controller.startRecording('camera', pixelRatio: 1);
                    }
                  },
                  child: Text(
                    _controller.isRecording
                        ? 'Stop Recording'
                        : 'Start Recording',
                  ),
                );
              },
            ),

            ElevatedButton(
              onPressed: () {
                if (_controller.path != null) {
                  Share.shareXFiles([XFile(_controller.path!)]);
                }
              },
              child: const Text('Share'),
            ),
          ],
        ),
      ],
    );
  }
}
