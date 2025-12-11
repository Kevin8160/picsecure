// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gallery_service.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ScannedPhotoAdapter extends TypeAdapter<ScannedPhoto> {
  @override
  final int typeId = 0;

  @override
  ScannedPhoto read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ScannedPhoto(
      assetId: fields[0] as String,
      faces: (fields[1] as List).cast<FaceObject>(),
      scannedAt: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, ScannedPhoto obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.assetId)
      ..writeByte(1)
      ..write(obj.faces)
      ..writeByte(2)
      ..write(obj.scannedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScannedPhotoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class FaceObjectAdapter extends TypeAdapter<FaceObject> {
  @override
  final int typeId = 1;

  @override
  FaceObject read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FaceObject(
      embedding: (fields[0] as List).cast<double>(),
      boundingBox: (fields[1] as Map).cast<String, int>(),
      clusterId: fields[2] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, FaceObject obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.embedding)
      ..writeByte(1)
      ..write(obj.boundingBox)
      ..writeByte(2)
      ..write(obj.clusterId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FaceObjectAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
