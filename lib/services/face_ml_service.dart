import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img; // Need 'image' package for processing
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceMLService {
  static final FaceMLService _instance = FaceMLService._internal();

  factory FaceMLService() {
    return _instance;
  }

  FaceMLService._internal();

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableContours: true,
      enableLandmarks: true,
    ),
  );

  Interpreter? _interpreter;
  bool _isModelLoaded = false;

  Future<void> init() async {
    if (_isModelLoaded) return;
    try {
      // Load MobileFaceNet model
      // Ensure 'mobilefacenet.tflite' is in assets
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset(
        'assets/models/mobilefacenet.tflite',
        options: options,
      );

      print("✅ Model Loaded");

      // We are NOT resizing the tensor anymore because the model graph prevents it (Reshape layer issue).
      // Instead, we will feed [2, 112, 112, 3] in recognize().

      _isModelLoaded = true;
    } catch (e) {
      print("❌ Error loading model: $e");
      // Rethrow to ensure UI knows about it
      throw Exception("Model load failed: $e");
    }
  }

  /// Detects face in an image file and returns the Face object (MLKit)
  Future<Face?> detect(File imageFile) async {
    final faces = await detectAll(imageFile);
    if (faces.isNotEmpty) {
      return faces.first; // Process the primary face
    }
    return null;
  }

  /// Detects ALL faces in an image file
  Future<List<Face>> detectAll(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    return await _faceDetector.processImage(inputImage);
  }

  /// Recognizes the face and returns a 192-d or 128-d embedding
  Future<List<double>> recognize(File imageFile, Face face) async {
    if (!_isModelLoaded) await init();
    if (_interpreter == null) throw Exception("Interpreter not initialized");

    // 1. Load image

    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception("Could not decode image");

    // 2. Crop Face
    // Bounding box from MLKit
    final x = face.boundingBox.left.toInt();
    final y = face.boundingBox.top.toInt();
    final w = face.boundingBox.width.toInt();
    final h = face.boundingBox.height.toInt();

    // Ensure crop is within bounds
    final cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);

    // 3. Resize to 112x112
    final resized = img.copyResize(cropped, width: 112, height: 112);

    // 4. Preprocess (Float32 Normalized) -> Create Batch of 2
    // Model expects [2, 112, 112, 3]
    List input = _imageToFloat32ListBatch2(resized);

    // 5. Run Inference
    // Output expects [2, 192]
    var outputBuffer = List.filled(2 * 192, 0.0).reshape([2, 192]);

    _interpreter!.run(input, outputBuffer);

    // Return the first embedding (ignore the duplicate)
    List<double> rawEmbedding = List<double>.from(outputBuffer[0]);
    return normalize(rawEmbedding);
  }

  /// L2 Normalization (Public for use in Matching Service)
  List<double> normalize(List<double> embedding) {
    double sum = 0;
    for (var x in embedding) {
      sum += x * x;
    }
    double norm = sqrt(sum);
    if (norm == 0) return embedding; // precise zero check
    return embedding.map((x) => x / norm).toList();
  }

  /// Helper to convert Image to Float32 List [2, 112, 112, 3] (Doubled)
  List _imageToFloat32ListBatch2(img.Image image) {
    // 1 image = 112*112*3 = 37632 float values
    var singleImageTotal = 112 * 112 * 3;
    var convertedBytes = Float32List(2 * singleImageTotal); // Batch 2
    var buffer = Float32List.view(convertedBytes.buffer);

    int pixelIndex = 0;

    // Fill first image
    for (var i = 0; i < 112; i++) {
      for (var j = 0; j < 112; j++) {
        var pixel = image.getPixel(j, i);
        // Normalize -1..1
        var r = (pixel.r - 128) / 128;
        var g = (pixel.g - 128) / 128;
        var b = (pixel.b - 128) / 128;

        buffer[pixelIndex++] = r;
        buffer[pixelIndex++] = g;
        buffer[pixelIndex++] = b;
      }
    }

    // Copy first image to second slot
    for (int i = 0; i < singleImageTotal; i++) {
      buffer[pixelIndex++] = buffer[i];
    }

    return convertedBytes.reshape([2, 112, 112, 3]);
  }

  /// Helper to convert Image to Uint8 List (0..255)
  List _imageToUint8List(img.Image image, int width, int height) {
    var convertedBytes = Uint8List(1 * width * height * 3);
    int pixelIndex = 0;
    for (var i = 0; i < height; i++) {
      for (var j = 0; j < width; j++) {
        var pixel = image.getPixel(j, i);
        convertedBytes[pixelIndex++] = pixel.r.toInt();
        convertedBytes[pixelIndex++] = pixel.g.toInt();
        convertedBytes[pixelIndex++] = pixel.b.toInt();
      }
    }
    return convertedBytes.reshape([1, width, height, 3]);
  }

  /// Calculate Similarity
  double calculateSimilarity(List<double> emb1, List<double> emb2) {
    // Euclidean Distance
    double sum = 0;
    for (int i = 0; i < emb1.length; i++) {
      sum += pow(emb1[i] - emb2[i], 2);
    }
    return sqrt(sum);
  }

  void dispose() {
    _faceDetector.close();
    _interpreter?.close();
  }
}
