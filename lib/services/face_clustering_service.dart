import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:picsecure/services/gallery_service.dart';

class FaceCluster {
  final String id;
  final String? label; // Name of person (if known)
  final FaceObjectDto representativeFace; // Changed to DTO
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
  // Made async to support compute
  Future<List<FaceCluster>> clusterFaces(List<ScannedPhoto> photos) async {
    // Serialization Fix: Convert HiveObjects to plain DTOs
    // HiveObjects cannot be passed to isolates because they contain generic Futures/Box references.
    final photoDtos = photos.map((p) => ScannedPhotoDto.fromHive(p)).toList();

    // Offload to isolate
    return await compute(computeClustering, photoDtos);
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

/// DTOs for Isolate Transfer
class FaceObjectDto {
  final List<double> embedding;
  final Map<String, int> boundingBox;
  String? clusterId;

  FaceObjectDto({
    required this.embedding,
    required this.boundingBox,
    this.clusterId,
  });

  factory FaceObjectDto.fromHive(FaceObject face) {
    return FaceObjectDto(
      embedding: List<double>.from(face.embedding),
      boundingBox: Map<String, int>.from(face.boundingBox),
      clusterId: face.clusterId,
    );
  }

  // Convert back if needed (or just use DTO values for clustering logic validation)
  // For clustering, we just need to return FaceClusters which contain data.
  // The 'representativeFace' in FaceCluster is currently typed as FaceObject.
  // We might need to change FaceCluster to use FaceObjectDto or map back.
  // Let's update `FaceCluster` to allow holding DTO data or update the type.
  // Actually, checking FaceCluster definition above... it uses FaceObject.
  // We should prob change FaceCluster to use FaceObjectDto (or a generic interface) or just duplicate the minimal data needed.
}

class ScannedPhotoDto {
  final String assetId;
  final List<FaceObjectDto> faces;

  ScannedPhotoDto({required this.assetId, required this.faces});

  factory ScannedPhotoDto.fromHive(ScannedPhoto photo) {
    return ScannedPhotoDto(
      assetId: photo.assetId,
      faces: photo.faces.map((f) => FaceObjectDto.fromHive(f)).toList(),
    );
  }
}

/// Top-level function for Compute
List<FaceCluster> computeClustering(List<ScannedPhotoDto> photos) {
  const double MATCH_THRESHOLD = 0.95;
  List<FaceCluster> clusters = [];

  for (var photo in photos) {
    for (var face in photo.faces) {
      // Try to match with existing clusters
      FaceCluster? bestMatch;
      double minDistance = double.infinity;

      for (var cluster in clusters) {
        double dist = _calculateEuclideanDistanceStatic(
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

  // Sort clusters by size (most frequent people first)
  clusters.sort((a, b) => b.photoIds.length.compareTo(a.photoIds.length));

  return clusters;
}

double _calculateEuclideanDistanceStatic(List<double> v1, List<double> v2) {
  if (v1.length != v2.length) return double.infinity;
  double sum = 0;
  for (int i = 0; i < v1.length; i++) {
    sum += pow(v1[i] - v2[i], 2);
  }
  return sqrt(sum);
}
