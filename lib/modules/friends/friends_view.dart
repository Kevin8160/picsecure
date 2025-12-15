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

  bool _isLoading = false;
  String _statusMessage = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkOutgoing();
    // Requests are now handled by StreamBuilder

    // Auto-scan if clusters provided
    if (widget.clusters.isNotEmpty) {
      // _scanGalleryForFriends(); // Optional: Auto-run? better user triggers
    }
  }

  void _checkOutgoing() {
    // Check if my friends accepted me
    _friendService.checkOutgoingStatus();
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
      // _fetchRequests(); // Refresh not needed with Stream
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
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _friendService.getFriendsStream(),
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

          // Tab 1: Find Friends (Face Search) - Mixed Manual & Continuous
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
                    // Manual Trigger still useful for force-refresh or UX
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
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: widget.clusters.isNotEmpty
                      ? _friendService.findFriendsStream(widget.clusters)
                      : Stream.value([]),
                  builder: (context, snapshot) {
                    final manualMatches = _foundFriends;
                    final streamMatches = snapshot.data ?? [];

                    // Merege deduplicated if needed, or just prefer stream if available.
                    // For logic simplicity: Show Stream matches if present, else manual.
                    // Actually, stream will fire immediately with current state.
                    // Combining them for best UX:

                    final allMatches = [...manualMatches];
                    // Add stream matches if not already present
                    for (var m in streamMatches) {
                      // Checking by user uid to avoid dupes
                      bool exists = allMatches.any(
                        (existing) =>
                            existing['user']['uid'] == m['user']['uid'],
                      );
                      if (!exists) allMatches.add(m);
                    }

                    if (_isLoading && allMatches.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (allMatches.isEmpty) {
                      // Only show empty state if stream has emitted at least once or we are not loading manual
                      if (snapshot.hasData || !_isLoading) {
                        return const Center(
                          child: Text(
                            "No matches found yet. Waiting for friends...",
                          ),
                        );
                      }
                      return const Center(child: CircularProgressIndicator());
                    }

                    return ListView.builder(
                      itemCount: allMatches.length,
                      itemBuilder: (context, index) {
                        final match = allMatches[index];
                        final user = match['user'];
                        final cluster = match['cluster'];

                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
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
                    );
                  },
                ),
              ),
            ],
          ),

          // Tab 2: Requests
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _friendService.getIncomingRequestsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final requests = snapshot.data ?? [];

              if (requests.isEmpty) {
                return const Center(child: Text("No Pending Requests"));
              }

              return ListView.builder(
                itemCount: requests.length,
                itemBuilder: (context, index) {
                  final req = requests[index];
                  return ListTile(
                    title: const Text("New Friend Request"),
                    subtitle: Text("From: ${req['userA']}"),
                    trailing: ElevatedButton(
                      child: const Text("Accept"),
                      onPressed: () => _acceptRequest(req),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
