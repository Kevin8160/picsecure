import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:picsecure/services/auth_service.dart';
import 'package:picsecure/services/encryption_service.dart';
import 'package:picsecure/services/face_ml_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FaceSetupView extends StatefulWidget {
  const FaceSetupView({super.key});

  @override
  State<FaceSetupView> createState() => _FaceSetupViewState();
}

class _FaceSetupViewState extends State<FaceSetupView> {
  File? _imageFile;
  bool _isProcessing = false;
  String _statusMessage = "Take a selfie to secure your identity";

  final ImagePicker _picker = ImagePicker();
  final FaceMLService _faceMLService = FaceMLService();
  final EncryptionService _encryptionService = EncryptionService();
  final AuthService _authService = AuthService();

  Future<void> _pickImage() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
    );

    if (photo != null) {
      setState(() {
        _imageFile = File(photo.path);
        _statusMessage = "Processing face...";
        _isProcessing = true;
      });
      _processFace();
    }
  }

  Future<void> _processFace() async {
    if (_imageFile == null) return;

    try {
      // 1. Detect Face
      final face = await _faceMLService.detect(_imageFile!);
      if (face == null) {
        setState(() {
          _statusMessage = "No face detected. Please try again.";
          _isProcessing = false;
          _imageFile = null;
        });
        return;
      }

      // 2. Recognize (Generate Embedding)
      final embedding = await _faceMLService.recognize(_imageFile!, face);

      // 3. Encrypt Embedding
      final encryptedEmbedding = await _encryptionService.encryptEmbedding(
        embedding,
      );

      // 4. Save to Firestore
      final user = _authService.currentUser;
      if (user != null) {
        // Ensure keys are generated
        await _encryptionService.init();
        final publicKeyPem = _encryptionService.getPublicKeyPem();

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'phone': user.phoneNumber,
          'encryptedFaceEmbedding': encryptedEmbedding,
          'publicEmbedding': embedding, // Restored for Discovery
          'publicKey': publicKeyPem, // For Hybrid Encryption
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        setState(() {
          _statusMessage = "Identity Secured!";
          _isProcessing = false;
        });

        // Navigate to Home
        Get.offAllNamed('/home');
      } else {
        setState(() {
          _statusMessage = "Error: Use not logged in.";
          _isProcessing = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Error: $e";
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 50),
                      Text(
                        "SecureFace Setup",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 50),
                      Center(
                        child: Container(
                          width: 250,
                          height: 250,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.blueAccent,
                              width: 3,
                            ),
                            image: _imageFile != null
                                ? DecorationImage(
                                    image: FileImage(_imageFile!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _imageFile == null
                              ? Icon(Icons.face, size: 100, color: Colors.grey)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 30),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ),
                      const Spacer(),
                      if (_isProcessing)
                        const CircularProgressIndicator()
                      else
                        ElevatedButton.icon(
                          onPressed: _pickImage,
                          icon: Icon(Icons.camera_alt),
                          label: Text("Take Secure Selfie"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            padding: EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 15,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                      const SizedBox(height: 50),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
