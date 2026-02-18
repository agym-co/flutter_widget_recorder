import 'package:flutter/material.dart';
import 'package:flutter_widget_recorder/flutter_widget_recorder.dart';
import 'package:flutter_widget_recorder_example/camera_screen.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: ExampleScreen());
  }
}

class ExampleScreen extends StatefulWidget {
  const ExampleScreen({super.key});

  @override
  State<ExampleScreen> createState() => _ExampleScreenState();
}

class _ExampleScreenState extends State<ExampleScreen> {
  final WidgetRecorderController _controller = WidgetRecorderController(
    captureFps: 30,
    isWithTicker: true,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Example')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          FloatingActionButton(
            heroTag: 'start',
            key: const Key('start_button'),
            onPressed: () =>
                _controller.startRecording('example', pixelRatio: pixelRatio),
            child: const Icon(Icons.play_arrow),
          ),
          FloatingActionButton(
            heroTag: 'stop',
            key: const Key('stop_button'),
            onPressed: _controller.stopRecording,
            child: const Icon(Icons.stop_circle),
          ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, child) {
              if (_controller.path == null) {
                return const SizedBox.shrink();
              }
              return FloatingActionButton(
                heroTag: 'share',
                key: const Key('share_button'),
                onPressed: () async {
                  if (_controller.path != null) {
                    await Share.shareXFiles([XFile(_controller.path!)]);
                  }
                },
                child: const Icon(Icons.share),
              );
            },
          ),
          FloatingActionButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CameraScreen()),
              );
            },
            child: const Icon(Icons.camera),
          ),
        ],
      ),
      body: Column(
        spacing: 10,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ColoredBox(
              color: Colors.red,
              child: SizedBox(
                width: 200,
                height: 200,
                child: WidgetRecorderWrapper(
                  controller: _controller,
                  child: ColoredBox(
                    color: Colors.blue,
                    child: const AnimationExample(),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, child) {
                if (_controller.path == null) {
                  return Text(
                    'No path',
                    key: const Key('no_path_text'),
                    style: Theme.of(context).textTheme.bodyLarge,
                  );
                }
                return Text(
                  'Path: ${_controller.path}',
                  key: const Key('path_text'),
                  style: Theme.of(context).textTheme.bodyLarge,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AnimationExample extends StatefulWidget {
  const AnimationExample({super.key});

  @override
  State<AnimationExample> createState() => _AnimationExampleState();
}

class _AnimationExampleState extends State<AnimationExample>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Stack(
              children: [
                Positioned(
                  left: _controller.value * (constraints.maxWidth - 100),
                  top: _controller.value * (constraints.maxHeight - 100),
                  child: ClipOval(
                    child: ColoredBox(
                      color: Colors.red,
                      child: SizedBox.square(dimension: 100),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
