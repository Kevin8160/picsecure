import 'dart:io';
import 'package:image/image.dart' as img; // Added for compression
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:picsecure/services/face_clustering_service.dart';
import 'dart:convert'; // For base64
import 'package:photo_manager/photo_manager.dart'; // For AssetEntity
import 'package:picsecure/services/auth_service.dart';
import 'package:picsecure/services/encryption_service.dart'; // Added
import 'package:picsecure/services/friend_service.dart';
import 'dart:typed_data';

class MatchedUser {
  final String uid;
  final String phone;
  final double similarity;
  final String? publicKey; // Added for encryption

  MatchedUser({
    required this.uid,
    required this.phone,
    required this.similarity,
    this.publicKey,
  });
}

class SecureSharingService {
  static final SecureSharingService _instance =
      SecureSharingService._internal();

  factory SecureSharingService() {
    return _instance;
  }

  SecureSharingService._internal();

  final EncryptionService _encryptionService = EncryptionService();

  /// matches a cluster's representative face against trusted friends locally
  Future<MatchedUser?> findFriendMatch(FaceCluster cluster) async {
    try {
      // 1. Ask FriendService (Local Match)
      // Note: FriendService must be initialized.
      // We use the singleton.
      // Import FriendService if needed (it is not imported yet in this file, adding imports)
      // Actually replace_file_content cannot verify imports easily without adding them.
      // I will assume FriendService is imported or I will add the import in a separate chunk/step or here if I can.
      // But let's look at the replacement.

      final result = await FriendService().identifyFace(
        cluster.representativeFace.embedding,
      );

      if (result != null) {
        final uid = result['uid'];
        final dist = result['distance'];

        // 2. Fetch details (Name/Phone/PublicKey) from Firestore
        // We do NOT fetch embedding here.
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (doc.exists) {
          return MatchedUser(
            uid: uid,
            phone: doc.data()?['phone'] ?? "Unknown Friend",
            similarity: dist,
            publicKey: doc.data()?['publicKey'],
          );
        }
      }
      return null;
    } catch (e) {
      print("Error finding match: $e");
      return null;
    }
  }

  /// Sends photos to a friend securely using Hybrid Encryption (AES + RSA)
  Future<void> sendPhotosToFriend(
    MatchedUser friend,
    List<String> assetIds,
  ) async {
    final myUid = AuthService().currentUser?.uid;
    if (friend.publicKey == null) {
      throw Exception("Friend has no Public Key. Cannot share securely.");
    }

    // 1. Create a Sharing Session/Batch ID
    final batchId = FirebaseFirestore.instance
        .collection('shared_batches')
        .doc()
        .id;

    for (var assetId in assetIds) {
      final asset = await AssetEntity.fromId(assetId);
      if (asset == null) continue;

      final file = await asset.file;
      if (file == null) continue;

      final bytes = await file.readAsBytes();

      // 1.5 Compress/Resize Image to fit in Firestore (Limit 1MB)
      // Note: Decoding/Encoding is heavy on main thread. Ideally isolate.
      // For MVP we do it here.
      // We rely on 'image' package which is already imported in project, we need to import it here.

      final img.Image? originalImage = img.decodeImage(bytes);
      List<int> compressedBytes = bytes;

      if (originalImage != null) {
        // Resize if too big (max 800px)
        img.Image resized = originalImage;
        if (originalImage.width > 800 || originalImage.height > 800) {
          resized = img.copyResize(
            originalImage,
            width: originalImage.width > originalImage.height ? 800 : null,
            height: originalImage.height >= originalImage.width ? 800 : null,
          );
        }
        // Encode to JPEG with quality 70
        compressedBytes = img.encodeJpg(resized, quality: 70);
      }

      // 2. Encrypt Photo
      final encryptedPayload = await _encryptionService.hybridEncrypt(
        Uint8List.fromList(compressedBytes),
        friend.publicKey!,
      );

      // 3. Upload (Simulating Storage via Firestore for MVP, ideally use Cloud Storage)
      // We split largely because Firestore docs have size limits (1MB).
      // For MVP, if image is large, this might fail. Ideally upload 'cipher' to Storage.
      // Here we assume small/medium images or demo purposes.

      await FirebaseFirestore.instance.collection('messages').add({
        'batchId': batchId,
        'from': myUid,
        'to': friend.uid,
        'type': 'encrypted_photo',
        'iv': encryptedPayload['iv'],
        'key': encryptedPayload['encryptedKey'], // Encrypted Session Key
        // In real app, upload 'cipher' to Storage and put URL here.
        // For text-based demo limit, we store base64 here (Warning: Limit 1MB)
        'payload': encryptedPayload['cipher'],
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
      });
    }
  }
}
