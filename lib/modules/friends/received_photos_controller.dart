import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:picsecure/services/auth_service.dart';
import 'package:picsecure/services/encryption_service.dart';
import 'package:gal/gal.dart';

class ReceivedPhoto {
  final String id;
  final String fromUid;
  final String localPath;
  final DateTime timestamp;

  ReceivedPhoto({
    required this.id,
    required this.fromUid,
    required this.localPath,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fromUid': fromUid,
      'localPath': localPath,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory ReceivedPhoto.fromMap(Map<dynamic, dynamic> map) {
    return ReceivedPhoto(
      id: map['id'],
      fromUid: map['fromUid'],
      localPath: map['localPath'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
    );
  }
}

class ReceivedPhotosController extends GetxController {
  final EncryptionService _encryptionService = EncryptionService();
  final String? _myUid = AuthService().currentUser?.uid;

  Box? _receivedBox;
  RxList<ReceivedPhoto> photos = <ReceivedPhoto>[].obs;
  RxBool isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    _init();
  }

  Future<void> _init() async {
    if (_myUid == null) return;

    // 1. Open Local Hive Box
    _receivedBox = await Hive.openBox('received_photos_meta');
    _loadLocalPhotos();

    // 2. Start Listening to Firestore
    _listenToIncoming();
  }

  void _loadLocalPhotos() {
    if (_receivedBox == null) return;
    final List<ReceivedPhoto> loaded = [];
    for (var key in _receivedBox!.keys) {
      final map = _receivedBox!.get(key);
      if (map != null) {
        loaded.add(ReceivedPhoto.fromMap(map));
      }
    }
    // Sort by Date Descending
    loaded.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    photos.assignAll(loaded);
    isLoading.value = false;
  }

  void _listenToIncoming() {
    FirebaseFirestore.instance
        .collection('messages')
        .where('to', isEqualTo: _myUid)
        .snapshots()
        .listen((snapshot) async {
          for (var doc in snapshot.docs) {
            // Process each new message
            await _processMessage(doc);
          }
        });
  }

  Future<void> _processMessage(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final messageId = doc.id;

    // Check if already processed (though we delete from FS, slight chance of race or local reprocessing)
    if (_receivedBox!.containsKey(messageId)) {
      // Already have it, ensure it's deleted from FS
      try {
        await doc.reference.delete();
      } catch (e) {}
      return;
    }

    try {
      final String fromUid = data['from'];
      final encryptedKey = data['key'];
      final iv = data['iv'];
      final cipherText = data['payload'];
      final Timestamp? ts = data['timestamp'];

      // 1. Decrypt
      final encryptedData = {
        'iv': iv,
        'encryptedKey': encryptedKey,
        'cipher': cipherText,
      };

      final decryptedBytes = await _encryptionService.hybridDecrypt(
        encryptedData,
      );

      // 2. Save to Local File
      final directory = await getApplicationDocumentsDirectory();
      final String filePath = '${directory.path}/received_$messageId.jpg';
      final file = File(filePath);
      await file.writeAsBytes(decryptedBytes);

      // 3. Save Meta to Hive
      final newPhoto = ReceivedPhoto(
        id: messageId,
        fromUid: fromUid,
        localPath: filePath,
        timestamp: ts?.toDate() ?? DateTime.now(),
      );

      await _receivedBox!.put(messageId, newPhoto.toMap());

      // 4. Update State
      photos.insert(0, newPhoto); // Add to top

      // 5. Delete from Firestore (Gone Forever)
      await doc.reference.delete();

      print("✅ Processed & Deleted Message $messageId");
    } catch (e) {
      print("❌ Failed to process message $messageId: $e");
    }
  }

  Future<void> downloadPhoto(ReceivedPhoto photo) async {
    try {
      // Check permission if needed (Gal handles it mostly)
      // Save using Gal
      await Gal.putImage(photo.localPath);
      Get.snackbar("Saved", "Photo saved to your gallery!");
    } catch (e) {
      Get.snackbar("Error", "Failed to save: $e");
    }
  }

  // Helper to filter by user
  List<ReceivedPhoto> getPhotosFrom(String? uid) {
    if (uid == null) return photos;
    return photos.where((p) => p.fromUid == uid).toList();
  }

  // Get list of unique senders
  List<String> getUniqueSenders() {
    return photos.map((p) => p.fromUid).toSet().toList();
  }
}
