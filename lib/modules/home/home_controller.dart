import 'package:flutter/services.dart'; // For MethodCall
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:picsecure/services/gallery_service.dart';

class HomeController extends GetxController {
  final GalleryService _galleryService = GalleryService();

  @override
  void onInit() {
    super.onInit();
    _initServices();
  }

  void _initServices() async {
    // 1. Immediate Permission Request
    final PermissionState ps = await PhotoManager.requestPermissionExtend();

    if (ps.isAuth) {
      update(); // Update UI if needed

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

  void _onGalleryChange(MethodCall call) {
    // Triggered when gallery changes (e.g., new photo taken)
    // We ask GalleryService to check for the latest photo
    _galleryService.processLatestPhoto();
  }

  @override
  void onClose() {
    PhotoManager.removeChangeCallback(_onGalleryChange);
    PhotoManager.stopChangeNotify();
    super.onClose();
  }
}
