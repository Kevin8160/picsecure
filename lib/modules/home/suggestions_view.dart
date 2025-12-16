import 'dart:typed_data';
import 'package:image/image.dart' as img;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:picsecure/services/gallery_service.dart';
import 'package:picsecure/services/face_clustering_service.dart';
import 'package:picsecure/modules/home/home_controller.dart';
import 'package:picsecure/modules/home/person_detail_view.dart';
import 'package:picsecure/modules/friends/received_photos_view.dart';
import 'package:picsecure/modules/friends/friends_view.dart';

class SuggestionsView extends StatefulWidget {
  const SuggestionsView({super.key});

  @override
  State<SuggestionsView> createState() => _SuggestionsViewState();
}

class _SuggestionsViewState extends State<SuggestionsView> {
  final HomeController _controller = Get.put(HomeController());
  final GalleryService _galleryService = GalleryService();
  Box<ScannedPhoto>? _box;

  @override
  void initState() {
    super.initState();
    _initBox();
  }

  Future<void> _initBox() async {
    // Keep this just for "All Photos" grid direct binding if we want,
    // OR migrate "All Photos" to controller too.
    // For now, "All Photos" can stay efficient with ValueListenable specific to the box,
    // but mixing Obx (Clusters) and ValueListenable (Grid) is fine.
    await _galleryService.init();
    if (Hive.isBoxOpen('scanned_photos')) {
      setState(() {
        _box = Hive.box<ScannedPhoto>('scanned_photos');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Found Memories"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "My Photos"),
              Tab(text: "Received"),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () {
                // Navigate to Friends
                // We can pass clusters from controller
                Get.to(() => FriendsView(clusters: _controller.clusters));
              },
              icon: const Icon(Icons.people),
            ),
            IconButton(
              onPressed: () {
                _galleryService.startScanning();
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(color: Colors.blueAccent),
                child: Text(
                  "PicSecure",
                  style: TextStyle(color: Colors.white, fontSize: 24),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home),
                title: const Text('Home'),
                onTap: () => Get.back(),
              ),
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Friends'),
                onTap: () {
                  Get.back();
                  Get.toNamed('/friends');
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {
                  Get.back();
                  Get.toNamed('/settings');
                },
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: My Photos
            Column(
              children: [
                _buildStatusHeader(),
                Expanded(
                  child: _box == null
                      ? const Center(child: CircularProgressIndicator())
                      : CustomScrollView(
                          slivers: [
                            // 1. People Section (Reactive from Controller)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text(
                                  "People & Friends",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Obx(() {
                                if (_controller.isLoadingClusters.value) {
                                  return const SizedBox(
                                    height: 120,
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                final clusters = _controller.clusters;
                                if (clusters.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 16.0,
                                    ),
                                    child: Text(
                                      "No people found yet. Keep scanning!",
                                    ),
                                  );
                                }
                                return SizedBox(
                                  height: 120,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: clusters.length,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    itemBuilder: (context, index) {
                                      final cluster = clusters[index];
                                      return GestureDetector(
                                        onTap: () => Get.to(
                                          () => PersonDetailView(
                                            cluster: cluster,
                                          ),
                                        ),
                                        child: Container(
                                          margin: const EdgeInsets.only(
                                            right: 16,
                                          ),
                                          child: Column(
                                            children: [
                                              FutureBuilder<Uint8List?>(
                                                future: _getFaceCrop(cluster),
                                                builder: (context, snapshot) {
                                                  if (!snapshot.hasData ||
                                                      snapshot.data == null) {
                                                    return const CircleAvatar(
                                                      radius: 40,
                                                      backgroundColor:
                                                          Colors.grey,
                                                    );
                                                  }
                                                  return CircleAvatar(
                                                    radius: 40,
                                                    backgroundImage:
                                                        MemoryImage(
                                                          snapshot.data!,
                                                        ),
                                                  );
                                                },
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                cluster.label ??
                                                    "Person ${index + 1}",
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              }),
                            ),

                            // 2. All Photos Section (Still using Box Listener for efficient grid updates)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text(
                                  "All Photos",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            ValueListenableBuilder(
                              valueListenable: _box!.listenable(),
                              builder: (context, Box<ScannedPhoto> box, _) {
                                final photos = box.values.toList();
                                if (photos.isEmpty) {
                                  return const SliverToBoxAdapter(
                                    child: Center(
                                      child: Text("No photos found yet."),
                                    ),
                                  );
                                }
                                return SliverGrid(
                                  delegate: SliverChildBuilderDelegate((
                                    context,
                                    index,
                                  ) {
                                    final photo = photos[index];
                                    return _buildPhotoTile(photo);
                                  }, childCount: photos.length),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        crossAxisSpacing: 4,
                                        mainAxisSpacing: 4,
                                      ),
                                );
                              },
                            ),
                          ],
                        ),
                ),
              ],
            ),

            // Tab 2: Received Photos
            const ReceivedPhotosView(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader() {
    return StreamBuilder<String>(
      stream: _galleryService.scanStatus,
      initialData: "Idle",
      builder: (context, snapshot) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: Colors.blueGrey.shade50,
          child: Text(
            "Status: ${snapshot.data}",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }

  Widget _buildPhotoTile(ScannedPhoto photo) {
    return FutureBuilder<AssetEntity?>(
      future: AssetEntity.fromId(photo.assetId),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return FutureBuilder<Uint8List?>(
            future: snapshot.data!.thumbnailDataWithSize(
              const ThumbnailSize.square(200),
            ),
            builder: (context, thumbSnapshot) {
              if (thumbSnapshot.hasData && thumbSnapshot.data != null) {
                return Image.memory(thumbSnapshot.data!, fit: BoxFit.cover);
              }
              return Container(color: Colors.grey.shade300);
            },
          );
        }
        return Container(color: Colors.grey.shade300);
      },
    );
  }
}

Future<Uint8List?> _getFaceCrop(FaceCluster cluster) async {
  try {
    final assetId = cluster.photoIds.first;
    final asset = await AssetEntity.fromId(assetId);
    if (asset == null) return null;

    // Get larger thumbnail for better crop quality
    // Increased from 500 to 1500 to ensure face crop is not pixelated
    final thumbBytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize(1500, 1500),
    );
    if (thumbBytes == null) return null;

    // Decode
    final image = img.decodeImage(thumbBytes);
    if (image == null) return null;

    // Calculate Scale (Thumbnail vs Original)
    final scaleX = image.width / asset.width;
    final scaleY = image.height / asset.height;

    final bbox = cluster.representativeFace.boundingBox;
    int x = (bbox['x']! * scaleX).toInt();
    int y = (bbox['y']! * scaleY).toInt();
    int w = (bbox['w']! * scaleX).toInt();
    int h = (bbox['h']! * scaleY).toInt();

    // Clamp
    x = x.clamp(0, image.width - 1);
    y = y.clamp(0, image.height - 1);
    if (x + w > image.width) w = image.width - x;
    if (y + h > image.height) h = image.height - y;

    // Crop
    final crop = img.copyCrop(image, x: x, y: y, width: w, height: h);

    // Encode back to PNG for display
    return Uint8List.fromList(img.encodePng(crop));
  } catch (e) {
    print("Crop error: $e");
    return null;
  }
}
