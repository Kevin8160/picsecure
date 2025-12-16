import 'dart:async';
import 'package:flutter/services.dart'; // For MethodCall
import 'package:get/get.dart';
import 'package:hive/hive.dart'; // For BoxEvent
import 'package:picsecure/services/face_clustering_service.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:picsecure/services/gallery_service.dart';

class HomeController extends GetxController {
  final GalleryService _galleryService = GalleryService();

  final RxList<FaceCluster> clusters = <FaceCluster>[].obs;
  final RxBool isLoadingClusters = true.obs;

  // Debounce timer
  Timer? _debounceTimer;

  @override
  void onInit() {
    super.onInit();
    _initServices();
  }

  void _initServices() async {
    // 0. Init Service (Ensure Hive is ready)
    await _galleryService.init();

    // Initial Load
    _refreshClusters();

    // Listen to Hive Changes
    _galleryService.watchGallery?.listen((event) {
      _triggerDebouncedRefresh();
    });

    // 1. Immediate Permission Request
    final PermissionState ps = await PhotoManager.requestPermissionExtend();

    if (ps.isAuth) {
      // 2. Start Background Scanner
      // This will scan existing photos in batches
      _galleryService.startScanning();

      // 3. Setup Live Watcher
      PhotoManager.addChangeCallback(_onGalleryChange);
      PhotoManager.startChangeNotify();
    } else {
      // Handle permission denial
      Get.snackbar(
        "Permission Required",
        "Please allow photo access to secure your memories.",
      );
    }
  }

  void _triggerDebouncedRefresh() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(seconds: 1), () {
      _refreshClusters();
    });
  }

  void _refreshClusters() async {
    // Run clustering in background (via Service which uses compute)
    final photos = _galleryService.photos;
    if (photos.isEmpty) {
      clusters.clear();
      isLoadingClusters.value = false;
      return;
    }

    try {
      final newClusters = await FaceClusteringService().clusterFaces(photos);
      clusters.assignAll(newClusters);
    } catch (e) {
      print("Error clustering: $e");
    } finally {
      isLoadingClusters.value = false;
    }
  }

  void _onGalleryChange(MethodCall call) {
    // Triggered when gallery changes (e.g., new photo taken)
    // We ask GalleryService to check for the latest photo
    _galleryService.processLatestPhoto();
  }

  @override
  void onClose() {
    _debounceTimer?.cancel();
    PhotoManager.removeChangeCallback(_onGalleryChange);
    PhotoManager.stopChangeNotify();
    super.onClose();
  }
}
