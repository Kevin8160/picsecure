import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:picsecure/services/face_clustering_service.dart';
import 'package:picsecure/services/secure_sharing_service.dart';

class PersonDetailView extends StatefulWidget {
  final FaceCluster cluster;

  const PersonDetailView({super.key, required this.cluster});

  @override
  State<PersonDetailView> createState() => _PersonDetailViewState();
}

class _PersonDetailViewState extends State<PersonDetailView> {
  MatchedUser? _matchedUser;
  bool _isLoadingMatch = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _checkMatch();
  }

  Future<void> _checkMatch() async {
    final match = await SecureSharingService().findFriendMatch(widget.cluster);
    if (mounted) {
      setState(() {
        _matchedUser = match;
        _isLoadingMatch = false;
      });
    }
  }

  Future<void> _sendPhotos() async {
    if (_matchedUser == null) return;
    setState(() {
      _isSending = true;
    });

    try {
      await SecureSharingService().sendPhotosToFriend(
        _matchedUser!,
        widget.cluster.photoIds,
      );
      Get.snackbar(
        "Success",
        "Securely sent ${widget.cluster.photoIds.length} photos!",
      );
    } catch (e) {
      Get.snackbar("Error", "Failed to send: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.cluster.label ?? "Unknown Person")),
      body: Column(
        children: [
          const SizedBox(height: 20),
          Center(
            child: CircleAvatar(
              radius: 60,
              backgroundColor: _matchedUser != null
                  ? Colors.green
                  : Colors.blueAccent,
              backgroundImage: null, // TODO: Extract Thumbnail
              child: const Icon(Icons.person, size: 60, color: Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          if (_isLoadingMatch)
            const Text("Checking if this is a friend...")
          else if (_matchedUser != null)
            Column(
              children: [
                Text(
                  "Matched Friend!",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                Text("ID: ${_matchedUser!.phone}"),
              ],
            )
          else
            const Text("No app user match found"),

          const SizedBox(height: 10),
          Text(
            "${widget.cluster.photoIds.length} Photos",
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 20),

          if (_matchedUser != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton.icon(
                onPressed: _isSending ? null : _sendPhotos,
                icon: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.lock_outline),
                label: Text(
                  _isSending
                      ? "Encrypting & Sending..."
                      : "Securely Share with ${_matchedUser!.phone}",
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

          const SizedBox(height: 20),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: widget.cluster.photoIds.length,
              itemBuilder: (context, index) {
                final assetId = widget.cluster.photoIds[index];
                return FutureBuilder<AssetEntity?>(
                  future: AssetEntity.fromId(assetId),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      return FutureBuilder<Uint8List?>(
                        future: snapshot.data!.thumbnailDataWithSize(
                          const ThumbnailSize.square(200),
                        ),
                        builder: (context, thumbSnapshot) {
                          if (thumbSnapshot.hasData &&
                              thumbSnapshot.data != null) {
                            return Image.memory(
                              thumbSnapshot.data!,
                              fit: BoxFit.cover,
                            );
                          }
                          return Container(color: Colors.grey.shade300);
                        },
                      );
                    }
                    return Container(color: Colors.grey.shade300);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
