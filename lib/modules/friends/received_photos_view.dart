import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:picsecure/modules/friends/received_photos_controller.dart';
import 'package:picsecure/services/friend_service.dart';

class ReceivedPhotosView extends StatefulWidget {
  const ReceivedPhotosView({super.key});

  @override
  State<ReceivedPhotosView> createState() => _ReceivedPhotosViewState();
}

class _ReceivedPhotosViewState extends State<ReceivedPhotosView> {
  final ReceivedPhotosController _controller = Get.put(
    ReceivedPhotosController(),
  );
  final FriendService _friendService = FriendService();

  String? _selectedSenderUid;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (_controller.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      final senders = _controller.getUniqueSenders();
      final displayPhotos = _controller.getPhotosFrom(_selectedSenderUid);

      return Column(
        children: [
          // 1. Senders List
          if (senders.isNotEmpty)
            Container(
              height: 100,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: senders.length,
                itemBuilder: (context, index) {
                  final uid = senders[index];
                  final isSelected = _selectedSenderUid == uid;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedSenderUid = isSelected ? null : uid;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 16),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: isSelected
                                ? Colors.blue
                                : Colors.grey.shade300,
                            child: CircleAvatar(
                              radius: 27,
                              backgroundColor: Colors.white,
                              child: const Icon(
                                Icons.person,
                                color: Colors.grey,
                              ),
                              // Future Improvement: Fetch Friend specific avatar/thumbnail if available
                            ),
                          ),
                          const SizedBox(height: 3),
                          FutureBuilder<Map<String, dynamic>?>(
                            future: _resolveFriendInfo(uid),
                            builder: (context, snap) {
                              return Text(
                                snap.data?['phone'] ?? "User",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          const Divider(),

          // 2. Photos Grid
          Expanded(
            child: displayPhotos.isEmpty
                ? const Center(child: Text("No received photos"))
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.8,
                        ),
                    itemCount: displayPhotos.length,
                    itemBuilder: (context, index) {
                      final photo = displayPhotos[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(
                              File(photo.localPath),
                              fit: BoxFit.cover,
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                color: Colors.black54,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _formatDate(photo.timestamp),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.download,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        _controller.downloadPhoto(photo);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    });
  }

  Future<Map<String, dynamic>?> _resolveFriendInfo(String uid) async {
    // Ideally FriendService has a method to get Friend Info by UID from local or cache
    // For now we assume we might have it in the friends list.
    // Hack: We fetch friends list and find. Ideally optimize this.
    final friends = await _friendService.getConfirmedFriends();
    try {
      return friends.firstWhere((f) => f['uid'] == uid);
    } catch (e) {
      return {'phone': 'Unknown'};
    }
  }

  String _formatDate(DateTime dt) {
    return "${dt.year}-${dt.month}-${dt.day} ${dt.hour}:${dt.minute}";
  }
}
