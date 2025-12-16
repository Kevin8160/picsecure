import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
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
      minFaceSize:
          0.15, // Default is 0.1, increasing slightly to avoid false positives, or keep 0.1?
      // Actually for "detected no face" issue, we want MORE sensitivity, so lower size?
      // But selfie face is big. The issue is likely something else.
      // Let's just remove the extra processing to be safe.
      // enableContours: true, // Removed for robustness/speed
      // enableLandmarks: true, // Removed
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
  Future<Face?> detect(File imageFile, {bool fixRotation = false}) async {
    File fileToProcess = imageFile;

    if (fixRotation) {
      try {
        final fixedPath = await compute(fixImageOrientation, imageFile.path);
        fileToProcess = File(fixedPath);
      } catch (e) {
        print("Rotation fix failed, using original: $e");
      }
    }

    var faces = await detectAll(fileToProcess);

    // Retry with rotation even if not explicitly requested if we find 0 faces?
    // No, keep it explicit to avoid scanning perf hit.

    if (faces.isNotEmpty) {
      return faces.first; // Process the primary face
    } else if (!fixRotation) {
      // Optional: Auto-retry if fixRotation was false initially?
      // Let's rely on the caller passing true.
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

    // 1. Read bytes (Main thread I/O is fine, but decoding should be offloaded)
    final bytes = await imageFile.readAsBytes();

    // 2. Offload Decoding, Cropping, Resizing, Normalization to Isolate
    // Pass necessary data: bytes + bounding box
    final processingData = ImageProcessingData(
      imageBytes: bytes,
      x: face.boundingBox.left.toInt(),
      y: face.boundingBox.top.toInt(),
      w: face.boundingBox.width.toInt(),
      h: face.boundingBox.height.toInt(),
    );

    try {
      final List input = await compute(processImageForTracking, processingData);

      // 3. Run Inference (Interpreter run must happen on the same thread it was created, usually main or its own isolate if structured that way.
      // TFLite Flutter interpreter is often thread-bound. For now, we run inference on main, but the heavy image op is gone.)
      // Output expects [2, 192]
      var outputBuffer = List.filled(2 * 192, 0.0).reshape([2, 192]);

      _interpreter!.run(input, outputBuffer);

      // Return the first embedding
      List<double> rawEmbedding = List<double>.from(outputBuffer[0]);
      return normalize(rawEmbedding);
    } catch (e) {
      print("Error in isolate processing: $e");
      rethrow;
    }
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

/// Data class to pass to Isolate
class ImageProcessingData {
  final Uint8List imageBytes;
  final int x;
  final int y;
  final int w;
  final int h;

  ImageProcessingData({
    required this.imageBytes,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });
}

/// Top-level function for Compute Isolate
/// Returns the Float32List input ready for TFLite
List processImageForTracking(ImageProcessingData data) {
  // 1. Decode
  final image = img.decodeImage(data.imageBytes);
  if (image == null) throw Exception("Could not decode image in isolate");

  // 2. Crop
  // Ensure crop is within bounds
  // Note: img handles out of bounds partially, but safe to clamp logic if needed.
  final cropped = img.copyCrop(
    image,
    x: data.x,
    y: data.y,
    width: data.w,
    height: data.h,
  );

  // 3. Resize
  final resized = img.copyResize(cropped, width: 112, height: 112);

  // 4. Convert to Float32 Batch [2, 112, 112, 3]
  return _imageToFloat32ListBatch2(resized);
}

/// Helper to convert Image to Float32 List [2, 112, 112, 3] (Doubled)
/// Copied here to be accessible by top-level function
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

/// Top-level function to fix image orientation by decoding and re-encoding
Future<String> fixImageOrientation(String path) async {
  final file = File(path);
  final bytes = await file.readAsBytes();

  // decodeImage will bake the EXIF orientation into the pixel data
  final image = img.decodeImage(bytes);

  if (image == null) throw Exception("Could not decode image for rotation fix");

  // Re-encode to JPG (removes EXIF orientation tag, pixels are now upright)
  final fixedBytes = img.encodeJpg(image);

  // Write to temp file
  final tempDir = Directory.systemTemp;
  final newPath = '${path}_fixed.jpg'; // Naive temp path
  final newFile = File(newPath);
  await newFile.writeAsBytes(fixedBytes);

  return newPath;
}
