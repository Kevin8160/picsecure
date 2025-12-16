import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Worker that runs Face Recognition in a separate Isolate
class FaceRecognitionWorker {
  Isolate? _isolate;
  SendPort? _sendPort;
  final Completer<void> _initCompleter = Completer<void>();

  // Stream for responses from the worker
  final StreamController<dynamic> _responseStream =
      StreamController<dynamic>.broadcast();

  Future<void> init() async {
    if (_initCompleter.isCompleted) return;

    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_workerEntry, receivePort.sendPort);

    // Listen for the initial handshake and subsequent messages
    receivePort.listen(
      (message) {
        if (message is SendPort) {
          _sendPort = message;
          if (!_initCompleter.isCompleted) {
            _initCompleter.complete();
          }
        } else {
          _responseStream.add(message);
        }
      },
      onError: (e) {
        print("Worker Isolate Error: $e");
      },
    );

    await _initCompleter.future;
  }

  Future<List<double>> recognize({
    required File imageFile,
    required Map<String, int> boundingBox,
    required String modelPath,
  }) async {
    if (_sendPort == null) await init();

    final completer = Completer<List<double>>();
    final requestId = DateTime.now().microsecondsSinceEpoch.toString();

    // Temporary subscription for this specific request
    final subscription = _responseStream.stream.listen((message) {
      if (message is Map && message['id'] == requestId) {
        if (message['error'] != null) {
          completer.completeError(message['error']);
        } else {
          completer.complete(List<double>.from(message['result']));
        }
      }
    });

    _sendPort!.send({
      'command': 'recognize',
      'id': requestId,
      'imagePath': imageFile.path,
      'box': boundingBox,
      'modelPath': modelPath,
    });

    try {
      final result = await completer.future;
      await subscription.cancel();
      return result;
    } catch (e) {
      await subscription.cancel();
      rethrow;
    }
  }

  void dispose() {
    _sendPort?.send({'command': 'dispose'});
    _isolate?.kill(priority: Isolate.immediate);
    _responseStream.close();
  }

  // --- Static Entry Point (Runs in separate thread) ---
  static void _workerEntry(SendPort sendPort) async {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort); // Handshake

    Interpreter? interpreter;

    await for (final message in receivePort) {
      if (message is Map) {
        final command = message['command'];

        if (command == 'dispose') {
          interpreter?.close();
          Isolate.exit();
        } else if (command == 'recognize') {
          final id = message['id'];
          try {
            final String imagePath = message['imagePath'];
            final Map<dynamic, dynamic> box = message['box'];
            final String modelPath = message['modelPath'];

            // Initialize Model if needed
            if (interpreter == null) {
              final options = InterpreterOptions()..threads = 4;
              interpreter = Interpreter.fromFile(
                File(modelPath),
                options: options,
              );
            }

            // Load & Process Image
            final bytes = await File(imagePath).readAsBytes();
            final image = img.decodeImage(bytes);

            if (image == null) throw Exception("Failed to decode image");

            // Crop
            final cropped = img.copyCrop(
              image,
              x: box['x'],
              y: box['y'],
              width: box['w'],
              height: box['h'],
            );

            // Resize
            final resized = img.copyResize(cropped, width: 112, height: 112);

            // Preprocess to Float32 Batch [2, 112, 112, 3]
            List input = _imageToFloat32ListBatch2(resized);

            // Run Inference
            var outputBuffer = List.filled(2 * 192, 0.0).reshape([2, 192]);
            interpreter.run(input, outputBuffer);

            // Normalize
            List<double> embedding = List<double>.from(outputBuffer[0]);
            embedding = _normalize(embedding);

            sendPort.send({'id': id, 'result': embedding});
          } catch (e) {
            sendPort.send({'id': id, 'error': e.toString()});
          }
        }
      }
    }
  }

  static List _imageToFloat32ListBatch2(img.Image image) {
    var singleImageTotal = 112 * 112 * 3;
    var convertedBytes = Float32List(2 * singleImageTotal);
    var buffer = Float32List.view(convertedBytes.buffer);

    int pixelIndex = 0;
    for (var i = 0; i < 112; i++) {
      for (var j = 0; j < 112; j++) {
        var pixel = image.getPixel(j, i);
        var r = (pixel.r - 128) / 128;
        var g = (pixel.g - 128) / 128;
        var b = (pixel.b - 128) / 128;
        buffer[pixelIndex++] = r;
        buffer[pixelIndex++] = g;
        buffer[pixelIndex++] = b;
      }
    }
    // Duplicate for batch size 2
    for (int i = 0; i < singleImageTotal; i++) {
      buffer[pixelIndex++] = buffer[i];
    }
    return convertedBytes.reshape([2, 112, 112, 3]);
  }

  static List<double> _normalize(List<double> embedding) {
    double sum = 0;
    for (var x in embedding) {
      sum += x * x;
    }
    double norm = sqrt(sum);
    if (norm == 0) return embedding;
    return embedding.map((x) => x / norm).toList();
  }
}
