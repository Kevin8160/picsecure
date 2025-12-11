import 'dart:math';
import 'package:picsecure/services/gallery_service.dart';

class FaceCluster {
  final String id;
  final String? label; // Name of person (if known)
  final FaceObject representativeFace;
  final List<String> photoIds; // Asset IDs containing this person

  FaceCluster({
    required this.id,
    this.label,
    required this.representativeFace,
    required this.photoIds,
  });
}

class FaceClusteringService {
  static final FaceClusteringService _instance =
      FaceClusteringService._internal();

  factory FaceClusteringService() {
    return _instance;
  }

  FaceClusteringService._internal();

  // Threshold for matching faces (Increased to 0.95 to be more inclusive)
  static const double MATCH_THRESHOLD = 0.95;

  /// Main method: Takes all scanned photos and organizes them into clusters
  List<FaceCluster> clusterFaces(List<ScannedPhoto> photos) {
    List<FaceCluster> clusters = [];

    for (var photo in photos) {
      for (var face in photo.faces) {
        // Try to match with existing clusters
        FaceCluster? bestMatch;
        double minDistance = double.infinity;

        for (var cluster in clusters) {
          double dist = calculateEuclideanDistance(
            face.embedding,
            cluster.representativeFace.embedding,
          );
          if (dist < MATCH_THRESHOLD && dist < minDistance) {
            minDistance = dist;
            bestMatch = cluster;
          }
        }

        if (bestMatch != null) {
          // Add to existing cluster
          // Avoid duplicates if multiple faces in same photo match same person (edge case)
          if (!bestMatch.photoIds.contains(photo.assetId)) {
            bestMatch.photoIds.add(photo.assetId);
          }
          face.clusterId = bestMatch.id;
        } else {
          // Create new cluster
          final newClusterId = "person_${clusters.length + 1}";
          final newCluster = FaceCluster(
            id: newClusterId,
            representativeFace: face,
            photoIds: [photo.assetId],
          );
          clusters.add(newCluster);
          face.clusterId = newClusterId;
        }
      }
    }

    // Optional: Merge similar clusters? (Not implemented for MVP)

    // Sort clusters by size (most frequent people first)
    clusters.sort((a, b) => b.photoIds.length.compareTo(a.photoIds.length));

    return clusters;
  }

  double calculateEuclideanDistance(List<double> v1, List<double> v2) {
    if (v1.length != v2.length) return double.infinity;
    double sum = 0;
    for (int i = 0; i < v1.length; i++) {
      sum += pow(v1[i] - v2[i], 2);
    }
    return sqrt(sum);
  }
}
