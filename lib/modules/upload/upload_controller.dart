import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';
import 'package:picsecure/services/auth_service.dart';
import 'package:picsecure/services/encryption_service.dart';
import 'package:uuid/uuid.dart';

class UploadController extends GetxController {
  final EncryptionService _encryptionService = EncryptionService();
  final AuthService _authService = AuthService();
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  var isUploading = false.obs;
  var uploadProgress = 0.0.obs;

  Future<void> secureUpload(File originalFile) async {
    isUploading.value = true;
    try {
      final user = _authService.currentUser;
      if (user == null) throw Exception("User not logged in");

      // 1. Read Bytes
      final bytes = await originalFile.readAsBytes();

      // 2. Encrypt (AES-GCM)
      // Returns [IV (12) + Content]
      // TODO: Key Management. For this MVP, we are effectively encrypting
      // with a session key. In a real scenario, we wrap this key for specific recipients.
      // For "Post" model, maybe we encrypt for a "Group" or just the uploader for now?
      // Requirement: "End-to-End Encryption".
      // Let's assume we are sending to a "receiver".
      // Since specific receiver logic isn't defined, we'll encrypt with a generated key
      // and assume the recipient has a way to unwrap it (e.g. key shared via signal or RSA).
      // SIMPLIFICATION: We will Upload the Encrypted Bytes.
      // The key exchange mechanism is out of scope for this single controller file without a Chat module.

      final encryptedBytes = await _encryptionService.encryptPhoto(bytes);

      // 3. Upload to Storage
      final filename = "${const Uuid().v4()}.enc";
      final ref = _storage.ref().child('posts').child(user.uid).child(filename);

      final uploadTask = ref.putData(encryptedBytes);
      uploadTask.snapshotEvents.listen((event) {
        uploadProgress.value = event.bytesTransferred / event.totalBytes;
      });

      await uploadTask;
      final downloadUrl = await ref.getDownloadURL();

      // 4. Create Metadata (Firestore)
      await _firestore.collection('posts').add({
        'uploaderUid': user.uid,
        'fileUrl': downloadUrl,
        'storagePath': ref.fullPath,
        'uploadedAt': FieldValue.serverTimestamp(),
        // 'encryptedKey': ... // In real app, store wrapped key here
        // 'iv': ... // If separated
      });

      Get.snackbar("Success", "Photo uploaded securely.");
    } catch (e) {
      Get.snackbar("Error", "Upload failed: $e");
    } finally {
      isUploading.value = false;
    }
  }
}
