import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:picsecure/services/friend_service.dart';
import 'package:picsecure/services/gallery_service.dart';
import 'package:picsecure/services/secure_sharing_service.dart';

class FriendDetailView extends StatefulWidget {
  const FriendDetailView({super.key});

  @override
  State<FriendDetailView> createState() => _FriendDetailViewState();
}

class _FriendDetailViewState extends State<FriendDetailView> {
  // Arguments passed from FriendsView
  late Map<String, dynamic> _friendData;
  final FriendService _friendService = FriendService();
  final SecureSharingService _sharingService = SecureSharingService();

  // List of matching Asset IDs
  List<String> _matchedAssetIds = [];
  bool _isScanning = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _friendData = Get.arguments;
    _findMatches();
  }

  Future<void> _findMatches() async {
    final Box<ScannedPhoto> box = Hive.box<ScannedPhoto>('scanned_photos');
    final String friendUid = _friendData['uid'];

    // We need to check all photos for this face.
    // For efficiency, we should have clustered them, but for now we iterate
    // and check against the local trusted embedding of this friend.

    // Note: FriendService has 'identifyFace' which checks an embedding against ALL friends.
    // But here we want to check ALL photos against ONE friend.
    // Ideally we iterate photos -> check if identity == friendUid.

    // Better Optimization:
    // If we already assigned 'clusterId' to faces, and we knew which cluster belongs to which friend.
    // But we haven't linked clusters to friends persistently yet.

    List<String> found = [];

    // Iterate all scanned photos
    for (var photo in box.values) {
      for (var face in photo.faces) {
        final match = await _friendService.identifyFace(face.embedding);
        if (match != null && match['uid'] == friendUid) {
          found.add(photo.assetId);
          break; // One match per photo is enough to send it
        }
      }
    }

    if (mounted) {
      setState(() {
        _matchedAssetIds = found;
        _isScanning = false;
      });
    }
  }

  Future<void> _sendAll() async {
    setState(() => _isSending = true);
    try {
      // Create MatchedUser object for service
      final user = MatchedUser(
        uid: _friendData['uid'],
        phone: _friendData['phone'] ?? "Unknown",
        similarity: 0.0, // Not relevant here
        publicKey: _friendData['publicKey'],
      );

      await _sharingService.sendPhotosToFriend(user, _matchedAssetIds);

      Get.snackbar(
        "Success",
        "Sent ${_matchedAssetIds.length} photos securely!",
      );
    } catch (e) {
      Get.snackbar("Error", "Failed to send: $e");
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_friendData['phone'] ?? "Friend")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
            const SizedBox(height: 20),
            Text(
              "Secure Connection Established",
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),

            if (_isScanning)
              const CircularProgressIndicator()
            else ...[
              Text(
                "${_matchedAssetIds.length}",
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text("Photos found in your gallery"),
              const SizedBox(height: 40),

              if (_matchedAssetIds.isNotEmpty)
                ElevatedButton.icon(
                  icon: const Icon(Icons.send),
                  label: Text(_isSending ? "Sending..." : "Send All Securely"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 15,
                    ),
                  ),
                  onPressed: _isSending ? null : _sendAll,
                )
              else
                const Text("No matching photos found yet."),
            ],
          ],
        ),
      ),
    );
  }
}
