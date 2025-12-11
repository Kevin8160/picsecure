import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:hive/hive.dart';
import 'package:picsecure/services/encryption_service.dart';

class FriendService {
  static final FriendService _instance = FriendService._internal();

  factory FriendService() {
    return _instance;
  }

  FriendService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final EncryptionService _encryptionService = EncryptionService();

  Box? _friendsBox;

  Future<void> init() async {
    _friendsBox = await Hive.openBox('friends_faces');
  }

  /// 1. Synced Contacts (Deprecated/Secondary)
  Future<List<Map<String, dynamic>>> findFriendsFromContacts() async {
    // ... existing logic ...
    return [];
  }

  /// 1b. Find Friends by Scanning Gallery Faces
  /// Compares local clusters against ALL users in Firestore (MVP).
  /// Returns List of { 'user': userData, 'clusterId': matchedClusterId }
  Future<List<Map<String, dynamic>>> findFriendsByFaces(
    List<dynamic> localClusters,
  ) async {
    // Note: localClusters should be List<FaceCluster> but avoiding circular dependency if possible.
    // We will assume the caller passes objects that have .representativeFace.embedding and .id

    final allUsersSnap = await _firestore.collection('users').get();
    final myUid = _auth.currentUser?.uid;

    // Get already confirmed friends to skip
    final existingFriends = await getConfirmedFriends();
    final existingUids = existingFriends.map((f) => f['uid']).toSet();

    List<Map<String, dynamic>> matches = [];

    // Pre-calculate/cache user embeddings
    List<Map<String, dynamic>> candidates = [];
    for (var doc in allUsersSnap.docs) {
      final data = doc.data();
      if (doc.id == myUid) continue;
      if (existingUids.contains(doc.id)) continue;

      final publicEmb = data['publicEmbedding'];
      if (publicEmb != null && publicEmb is List) {
        candidates.add({'data': data, 'embedding': publicEmb.cast<double>()});
      }
    }

    // Compare
    // Relaxed Threshold for Search (Selfie vs Random Gallery Photo)
    // 0.95 might be too strict for cross-context matching.
    const double THRESHOLD = 1.25;

    print("DEBUG: Starting Face Search...");
    print(
      "DEBUG: Candidates (server users with public face): ${candidates.length}",
    );
    print("DEBUG: Local Clusters: ${localClusters.length}");

    for (var cluster in localClusters) {
      // accessing dynamic properties - be careful or import FaceCluster
      // Assuming passed arg is List<FaceCluster> from face_clustering_service.dart
      final clusterEmbedding =
          cluster.representativeFace.embedding as List<double>;

      for (var candidate in candidates) {
        final candidateEmb = candidate['embedding'] as List<double>;
        final dist = _euclideanDistance(clusterEmbedding, candidateEmb);

        print(
          "DEBUG: Distance between Cluster '${cluster.label}' and User '${candidate['data']['phone']}': $dist",
        );

        if (dist < THRESHOLD) {
          print("DEBUG: MATCH FOUND!");
          matches.add({
            'user': candidate['data'],
            'cluster': cluster, // Pass back the whole cluster object
            'distance': dist,
          });
          // Break candidate loop? No, one candidate might match multiple clusters (unlikely if clustered well)
          // Break cluster loop? One cluster matches one user? Yes, ideally.
          break;
        }
      }
    }

    return matches;
  }

  /// 2. Add Friend (Handshake Step 1)
  Future<void> addFriend(String friendUid, String friendPublicKeyPem) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // A. Get My Encrypted Embedding
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final myEncryptedEmbeddingStr = userDoc.data()?['encryptedFaceEmbedding'];

    if (myEncryptedEmbeddingStr == null)
      throw Exception("My Face Setup not complete");

    // B. Decrypt it
    List<double> myEmbedding;
    try {
      myEmbedding = await _encryptionService.decryptEmbedding(
        myEncryptedEmbeddingStr,
      );
    } catch (e) {
      print("Decryption Failed. Likely key mismatch due to reinstall: $e");
      throw Exception(
        "Security Mismatch: Your Private Key is missing or changed. Please go to Settings (or Re-run Face Setup) to restore your Identity.",
      );
    }

    // C. Encrypt for Friend
    final encryptedForFriend = await _encryptionService.encryptEmbeddingForPeer(
      myEmbedding,
      friendPublicKeyPem,
    );

    // D. Save to Friendships
    await _firestore
        .collection('friendships')
        .doc('${user.uid}_$friendUid')
        .set({
          'userA': user.uid, // Me
          'userB': friendUid, // Friend
          'faceEmbeddingForB': encryptedForFriend,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  /// 3. Get Incoming Requests (Pending)
  Future<List<Map<String, dynamic>>> getIncomingRequests() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final snapshot = await _firestore
        .collection('friendships')
        .where('userB', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .get();

    return snapshot.docs.map((d) => {...d.data(), 'id': d.id}).toList();
  }

  /// 3.5. Get Confirmed Friends (Local Hive + Firestore fetch for info)
  Future<List<Map<String, dynamic>>> getConfirmedFriends() async {
    if (_friendsBox == null) return [];

    final friendUids = _friendsBox!.keys.cast<String>().toList();
    if (friendUids.isEmpty) return [];

    // Fetch details for display (e.g. Phone)
    // Firestore 'in' limit is 10. For MVP assuming < 10 friends, else loop.
    // Ideally we store name/phone in Hive too, but we only stored embedding.
    // Let's fetch freshly.

    List<Map<String, dynamic>> friends = [];
    for (var i = 0; i < friendUids.length; i += 10) {
      final chunk = friendUids.sublist(
        i,
        (i + 10) > friendUids.length ? friendUids.length : i + 10,
      );
      final snapshot = await _firestore
          .collection('users')
          .where('uid', whereIn: chunk)
          .get();
      friends.addAll(snapshot.docs.map((d) => d.data()));
    }
    return friends;
  }

  /// 4. Accept Request (Handshake Step 2)
  Future<void> acceptRequest(
    String requestId,
    String userAUid,
    String encryptedFaceForMe,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // A. Save Friend's Face Locally
    await _saveFriendFace(userAUid, encryptedFaceForMe);

    // B. Send My Face back to them
    // 1. Get/Decrypt My Face
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final myEncSrc = userDoc.data()?['encryptedFaceEmbedding'];
    final myEmbedding = await _encryptionService.decryptEmbedding(myEncSrc);

    // 2. Encrypt for userA
    final userADoc = await _firestore.collection('users').doc(userAUid).get();
    final userAPubKey = userADoc.data()?['publicKey'];
    final encryptedForA = await _encryptionService.encryptEmbeddingForPeer(
      myEmbedding,
      userAPubKey,
    );

    // 3. Update Firestore
    await _firestore.collection('friendships').doc(requestId).update({
      'faceEmbeddingForA': encryptedForA,
      'status': 'accepted',
    });
  }

  /// 5. Check Outgoing Requests (Did they accept?)
  Future<void> checkOutgoingStatus() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final myAdds = await _firestore
        .collection('friendships')
        .where('userA', isEqualTo: user.uid)
        .get();

    for (var doc in myAdds.docs) {
      final data = doc.data();
      // If they replied (faceEmbeddingForA is set), save it.
      if (data['faceEmbeddingForA'] != null) {
        await _saveFriendFace(data['userB'], data['faceEmbeddingForA']);
      }
    }
  }

  // Deprecated massive auto-process function
  Future<void> processFriendships() async {
    // For backward compatibility or auto-background checks
    await checkOutgoingStatus();
  }

  Future<void> _saveFriendFace(String friendUid, String encryptedJson) async {
    if (_friendsBox != null && _friendsBox!.containsKey(friendUid)) return;

    try {
      final embedding = await _encryptionService.decryptEmbedding(
        encryptedJson,
      );
      await _friendsBox?.put(friendUid, embedding);
      print("✅ Friend $friendUid face secured locally!");
    } catch (e) {
      print("Error saving friend face: $e");
    }
  }

  /// Clears local hive box for debugging
  Future<void> debugClearFriends() async {
    await _friendsBox?.clear();
  }

  String _normalizePhone(String phone) {
    // 1. Remove all characters except digits and '+'
    String cleaned = phone.replaceAll(RegExp(r'[^+\d]'), '');

    // 2. If it starts with +, return it (e.g., +919876543210)
    if (cleaned.startsWith('+')) {
      return cleaned;
    }

    // 3. If it doesn't start with +, assume valid local number and prepend +91 (Default to IN for this demo)
    // This matches LoginView logic.
    return "+91$cleaned";
  }

  /// Match a given embedding against all trusted friends
  Future<Map<String, dynamic>?> identifyFace(List<double> embedding) async {
    if (_friendsBox == null) return null;

    String? bestUid;
    double minDistance = 1.25; // Relaxed Threshold (Matches Discovery Logic)

    for (var key in _friendsBox!.keys) {
      // Hive stores as List<dynamic> (usually), checking cast
      final storedList = _friendsBox!.get(key);
      if (storedList != null && storedList is List) {
        final friendEmbedding = storedList.cast<double>();
        final dist = _euclideanDistance(embedding, friendEmbedding);
        if (dist < minDistance) {
          minDistance = dist;
          bestUid = key;
        }
      }
    }

    if (bestUid != null) {
      return {'uid': bestUid, 'distance': minDistance};
    }
    return null; // Unknown face
  }

  double _euclideanDistance(List<double> e1, List<double> e2) {
    if (e1.length != e2.length) return 100.0;
    double sum = 0;
    for (int i = 0; i < e1.length; i++) {
      sum += (e1[i] - e2[i]) * (e1[i] - e2[i]);
    }
    return math.sqrt(sum);
  }
}
