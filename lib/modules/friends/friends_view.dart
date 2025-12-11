import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:picsecure/services/friend_service.dart';
import 'package:picsecure/services/face_clustering_service.dart'; // Import for type if needed, or dynamic

class FriendsView extends StatefulWidget {
  final List<dynamic>
  clusters; // Using dynamic to avoid hard type coupling if preferred, else FaceCluster
  const FriendsView({super.key, this.clusters = const []});

  @override
  State<FriendsView> createState() => _FriendsViewState();
}

class _FriendsViewState extends State<FriendsView>
    with SingleTickerProviderStateMixin {
  final FriendService _friendService = FriendService();
  late TabController _tabController;

  List<Map<String, dynamic>> _foundFriends = []; // Result of face scan
  List<Map<String, dynamic>> _incomingRequests = [];

  bool _isLoading = false;
  String _statusMessage = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkOutgoing();
    _fetchRequests();

    // Auto-scan if clusters provided
    if (widget.clusters.isNotEmpty) {
      // _scanGalleryForFriends(); // Optional: Auto-run? better user triggers
    }
  }

  void _checkOutgoing() {
    // Check if my friends accepted me
    _friendService.checkOutgoingStatus();
  }

  Future<void> _fetchRequests() async {
    final requests = await _friendService.getIncomingRequests();
    setState(() {
      _incomingRequests = requests;
    });
  }

  // REPLACES _syncContacts
  Future<void> _scanGalleryForFriends() async {
    if (widget.clusters.isEmpty) {
      setState(() {
        _statusMessage = "No people found in your gallery to search with.";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage =
          "Scanning ${widget.clusters.length} people against PicSecure users...";
    });

    try {
      // Uses the NEW face-based search
      final found = await _friendService.findFriendsByFaces(widget.clusters);

      setState(() {
        _foundFriends = found;
        _isLoading = false;
        _statusMessage = found.isEmpty
            ? "No matches found. Ask friends to run 'Face Setup'!"
            : "Found ${found.length} potential friends!";
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = "Error: $e";
      });
      print(e);
    }
  }

  Future<void> _addFriend(Map<String, dynamic> matchResult) async {
    final user = matchResult['user'];
    final uid = user['uid'];
    final pubKey = user['publicKey'];

    if (pubKey == null) {
      Get.snackbar("Error", "User has no public key");
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _friendService.addFriend(uid, pubKey);
      Get.snackbar(
        "Success",
        "Friend request sent to ${user['phone'] ?? 'User'}!",
      );
    } catch (e) {
      Get.snackbar("Error", "$e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _acceptRequest(Map<String, dynamic> request) async {
    setState(() => _isLoading = true);
    try {
      await _friendService.acceptRequest(
        request['id'],
        request['userA'],
        request['faceEmbeddingForB'],
      );
      Get.snackbar(
        "Connected!",
        "Friend accepted. You can now detect their photos!",
      );
      _fetchRequests(); // Refresh
    } catch (e) {
      Get.snackbar("Error", "Accept failed: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Friends"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Connections"),
            Tab(text: "Find"),
            Tab(text: "Requests"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 0: Connections (Confirmed)
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _friendService.getConfirmedFriends(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final friends = snapshot.data ?? [];
              if (friends.isEmpty) {
                return const Center(child: Text("No confirmed friends yet."));
              }
              return ListView.builder(
                itemCount: friends.length,
                itemBuilder: (context, index) {
                  final friend = friends[index];
                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.green,
                      child: Icon(Icons.check, color: Colors.white),
                    ),
                    title: Text(friend['phone'] ?? "Friend"),
                    subtitle: const Text("Trusted & Secure"),
                    onTap: () {
                      // Navigate to Friend Detail
                      Get.toNamed('/friend-detail', arguments: friend);
                    },
                  );
                },
              );
            },
          ),

          // Tab 1: Find Friends (Face Search)
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      "Find friends by scanning faces in your gallery.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _scanGalleryForFriends,
                      icon: const Icon(Icons.face_retouching_natural),
                      label: const Text("Scan Gallery for Friends"),
                    ),
                    if (_statusMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: _isLoading && _foundFriends.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: _foundFriends.length,
                        itemBuilder: (context, index) {
                          final match = _foundFriends[index];
                          final user = match['user'];
                          final cluster =
                              match['cluster']; // The local cluster that matched

                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person),
                              // Future: Show side-by-side (Cluster Face vs User Face?)
                            ),
                            title: Text(user['phone'] ?? "Unknown"),
                            subtitle: Text(
                              "Matched with ${cluster.label ?? 'Unknown Person'}",
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.person_add,
                                color: Colors.blue,
                              ),
                              onPressed: () => _addFriend(match),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),

          // Tab 2: Requests
          _incomingRequests.isEmpty
              ? const Center(child: Text("No Pending Requests"))
              : ListView.builder(
                  itemCount: _incomingRequests.length,
                  itemBuilder: (context, index) {
                    final req = _incomingRequests[index];
                    return ListTile(
                      title: const Text("New Friend Request"),
                      subtitle: Text("From: ${req['userA']}"),
                      trailing: ElevatedButton(
                        child: const Text("Accept"),
                        onPressed: () => _acceptRequest(req),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}
