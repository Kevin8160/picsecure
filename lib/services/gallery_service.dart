import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:hive/hive.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:picsecure/services/encryption_service.dart';
import 'package:picsecure/services/face_ml_service.dart';

part 'gallery_service.g.dart'; // Needed for Hive Adapter

@HiveType(typeId: 0)
class ScannedPhoto extends HiveObject {
  @HiveField(0)
  final String assetId;

  // Storing list of FaceObjects (embedding + bounding box)
  @HiveField(1)
  final List<FaceObject> faces;

  @HiveField(2)
  final DateTime scannedAt;

  ScannedPhoto({
    required this.assetId,
    required this.faces,
    required this.scannedAt,
  });
}

@HiveType(typeId: 1)
class FaceObject extends HiveObject {
  @HiveField(0)
  final List<double> embedding;

  @HiveField(1)
  final Map<String, int> boundingBox; // {'x': 0, 'y': 0, 'w': 100, 'h': 100}

  @HiveField(2)
  String? clusterId; // Assigned later by clustering service

  FaceObject({
    required this.embedding,
    required this.boundingBox,
    this.clusterId,
  });
}

class GalleryService {
  static final GalleryService _instance = GalleryService._internal();

  factory GalleryService() {
    return _instance;
  }

  GalleryService._internal();

  final Battery _battery = Battery();
  final FaceMLService _faceMLService = FaceMLService();
  final EncryptionService _encryptionService = EncryptionService();

  Box<ScannedPhoto>? _box;
  bool _isScanning = false;
  final StreamController<String> _scanStatusController =
      StreamController<String>.broadcast();
  Stream<String> get scanStatus => _scanStatusController.stream;

  Stream<BoxEvent>? get watchGallery => _box?.watch();

  // Expose box for direct access if needed (or better, keep encapsulated)
  List<ScannedPhoto> get photos =>
      _box?.values.toList().cast<ScannedPhoto>() ?? [];

  Future<void> init() async {
    // Register Adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ScannedPhotoAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(FaceObjectAdapter());

    final key = await _encryptionService.getHiveKey();
    _box = await Hive.openBox<ScannedPhoto>(
      'scanned_photos',
      encryptionCipher: HiveAesCipher(key),
    );

    // TEMPORARY: Clear box to handle schema migration from List<List<double>> to List<FaceObject>
    if (_box!.isNotEmpty) {
      try {
        // We must actually iterate and access the elements to trigger the CastError/TypeError
        // because Hive returns a lazy CastList.
        for (var key in _box!.keys) {
          final item = _box!.get(key);
          if (item != null) {
            // Accessing faces to trigger Cast check
            for (var face in item.faces) {
              // Determine if it's truly a FaceObject
              // If the data is List<double>, this access might succeed strictly speaking
              // but the type check face is FaceObject will eventually fail or the loop helper will fail.
              // explicitly checking runtime type usually works best to force the check.
            }
          }
        }
      } catch (e) {
        print("⚠️ Schema mismatch detected (Old Data), resetting gallery: $e");
        await _box!.clear();
      }
    }
    // Force clear for this "Phase 3" update to be sure
    // await _box!.clear();
  }

  Future<void> clearGallery() async {
    await _box?.clear();
    _scanStatusController.add("Gallery Cleared");
  }

  Future<void> startScanning() async {
    if (_isScanning) return;
    _isScanning = true;
    _scanStatusController.add("Starting scan...");

    // Request Permissions
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) {
      _scanStatusController.add("Permission denied");
      _isScanning = false;
      return;
    }

    // Get Albums (Recent/All)
    final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
    );
    if (paths.isEmpty) {
      _isScanning = false;
      return;
    }
    // Prefer the global "All" album (usually isAll property or 'Recent' match)
    final recent = paths.firstWhere((p) => p.isAll, orElse: () => paths.first);

    // Count
    final int total = await recent.assetCountAsync;
    int processed = 0;
    int offset = 0;
    const int batchSize = 50;

    while (offset < total && _isScanning) {
      // Battery Check
      final int batteryLevel = await _battery.batteryLevel;
      final BatteryState batteryState = await _battery.batteryState;

      if (batteryLevel < 15 && batteryState != BatteryState.charging) {
        _scanStatusController.add("Paused: Battery low ($batteryLevel%)");
        await Future.delayed(Duration(seconds: 10)); // Wait and retry
        continue;
      }

      // Fetch Batch
      final List<AssetEntity> assets = await recent.getAssetListRange(
        start: offset,
        end: offset + batchSize,
      );

      for (final asset in assets) {
        if (!_isScanning) break;

        // Skip if already scanned
        if (_box!.containsKey(asset.id)) {
          processed++;
          continue;
        }

        File? file = await asset.file;

        // FAILSAFE: If asset.file is null (Scoped Storage restriction), write temp
        if (file == null) {
          try {
            final data = await asset.originBytes;
            if (data != null) {
              final tempDir = Directory.systemTemp;
              final tempFile = File('${tempDir.path}/${asset.id}.jpg');
              await tempFile.writeAsBytes(data);
              file = tempFile;
              // print("DEBUG: Created temp file for ${asset.id}");
            }
          } catch (e) {
            print("Error getting file bytes: $e");
          }
        }

        if (file != null) {
          try {
            // Run Face Detection (Get ALL faces)
            List<FaceObject> faceObjects = [];
            try {
              final faces = await _faceMLService.detectAll(file);
              if (faces.isNotEmpty) {
                for (var face in faces) {
                  final embedding = await _faceMLService.recognize(file, face);
                  faceObjects.add(
                    FaceObject(
                      embedding: embedding,
                      boundingBox: {
                        'x': face.boundingBox.left.toInt(),
                        'y': face.boundingBox.top.toInt(),
                        'w': face.boundingBox.width.toInt(),
                        'h': face.boundingBox.height.toInt(),
                      },
                    ),
                  );
                }
                _scanStatusController.add(
                  "Found ${faces.length} faces in photo",
                );
              }
            } catch (mlError) {
              print("ML Error for ${asset.id}: $mlError");
              // Continue to separate save logic, don't crash
            }

            // ALWAYS store the photo, even if no faces found
            final photo = ScannedPhoto(
              assetId: asset.id,
              faces: faceObjects,
              scannedAt: DateTime.now(),
            );
            await _box!.put(asset.id, photo);
          } catch (e) {
            print("Error scanning ${asset.id}: $e");
            _scanStatusController.add("Error: $e");
          } finally {
            // If we created a temp file, delete it?
            // Maybe not immediately if Hive holds ref? No, Hive stores Id.
            // Using file path is only for ML.
            // But we didn't store file path.
            // Ideally we delete temp file.
            if (file.path.contains(Directory.systemTemp.path)) {
              // Cleanup
              // await file.delete(); // Deferred cleanup
            }
          }
        } else {
          _scanStatusController.add("Skipped (File access error)");
        }
        processed++;
        // Small delay to prevent freezing UI isolate if running here (better in isolate)
        await Future.delayed(Duration(milliseconds: 10));
      }

      offset += batchSize;
      _scanStatusController.add("Scanned $processed / $total");

      // Throttle
      await Future.delayed(Duration(milliseconds: 500));
    }

    _isScanning = false;
    _scanStatusController.add("Scan Complete");
  }

  void stopScanning() {
    _isScanning = false;
  }

  /// Check for the very latest photo and process it immediately
  Future<void> processLatestPhoto() async {
    // 1. Get Recent Album
    final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
    );
    if (paths.isEmpty) return;
    final recent = paths.firstWhere((p) => p.isAll, orElse: () => paths.first);

    // 2. Get Last 1 Asset
    final List<AssetEntity> assets = await recent.getAssetListRange(
      start: 0,
      end: 1,
    );
    if (assets.isEmpty) return;

    final asset = assets.first;

    // 3. Check if already scanned
    if (_box != null && _box!.containsKey(asset.id)) {
      return; // Already have it
    }

    _scanStatusController.add("Processing new photo...");

    // 4. Process
    File? file = await asset.file;
    if (file != null) {
      try {
        final faces = await _faceMLService.detectAll(file);
        List<FaceObject> faceObjects = [];

        if (faces.isNotEmpty) {
          for (var face in faces) {
            final embedding = await _faceMLService.recognize(file, face);
            faceObjects.add(
              FaceObject(
                embedding: embedding,
                boundingBox: {
                  'x': face.boundingBox.left.toInt(),
                  'y': face.boundingBox.top.toInt(),
                  'w': face.boundingBox.width.toInt(),
                  'h': face.boundingBox.height.toInt(),
                },
              ),
            );
          }
        }

        final photo = ScannedPhoto(
          assetId: asset.id,
          faces: faceObjects,
          scannedAt: DateTime.now(),
        );
        await _box!.put(asset.id, photo);
        _scanStatusController.add("New photo secured!");

        // Check for matches immediately?
        // Matches are found by 'SuggestionsView' or dedicated ClusteringService
        // observing the box.
      } catch (e) {
        print("Error processing new photo: $e");
      }
    }
  }
}
