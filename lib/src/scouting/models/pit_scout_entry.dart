import 'package:uuid/uuid.dart';

class PitScoutEntry {
  static const int maxPhotos = 3;

  PitScoutEntry({
    String? id,
    required this.teamNumber,
    this.eventKey = '',
    Map<String, dynamic>? fieldValues,
    this.authorUid = '',
    this.authorDisplayName = '',
    DateTime? updatedAt,
    List<String>? photoIds,
    Map<String, String>? photoKeys,
  }) : id = id ?? const Uuid().v4(),
       fieldValues = fieldValues ?? const <String, dynamic>{},
       photoKeys = Map<String, String>.unmodifiable(
         photoKeys ?? const <String, String>{},
       ),
       photoIds = List<String>.unmodifiable(
         photoIds == null
             ? <String>[]
             : photoIds.length > maxPhotos
             ? photoIds.sublist(0, maxPhotos)
             : photoIds,
       ),
       updatedAt = (updatedAt ?? DateTime.now()).toUtc();

  final String id;
  final int teamNumber;

  final String eventKey;

  final Map<String, dynamic> fieldValues;

  final String authorUid;

  final String authorDisplayName;

  final List<String> photoIds;

  final Map<String, String> photoKeys;

  Iterable<String> get pendingPhotoIds =>
      photoIds.where((id) => !photoKeys.containsKey(id));

  final DateTime updatedAt;

  PitScoutEntry copyWith({
    int? teamNumber,
    String? eventKey,
    Map<String, dynamic>? fieldValues,
    String? authorUid,
    String? authorDisplayName,
    DateTime? updatedAt,
    List<String>? photoIds,
    Map<String, String>? photoKeys,
  }) {
    return PitScoutEntry(
      id: id,
      teamNumber: teamNumber ?? this.teamNumber,
      eventKey: eventKey ?? this.eventKey,
      fieldValues: fieldValues ?? this.fieldValues,
      authorUid: authorUid ?? this.authorUid,
      authorDisplayName: authorDisplayName ?? this.authorDisplayName,
      updatedAt: updatedAt ?? this.updatedAt,
      photoIds: photoIds ?? this.photoIds,
      photoKeys: photoKeys ?? this.photoKeys,
    );
  }

  PitScoutEntry withUploadedPhoto(String photoId, String key) {
    if (!photoIds.contains(photoId)) return this;
    return copyWith(photoKeys: <String, String>{...photoKeys, photoId: key});
  }

  PitScoutEntry withAddedPhoto(String photoId) {
    if (photoIds.length >= maxPhotos) return this;
    return copyWith(photoIds: [...photoIds, photoId]);
  }

  PitScoutEntry withRemovedPhoto(String photoId) {
    return copyWith(
      photoIds: [...photoIds.where((id) => id != photoId)],
      photoKeys: <String, String>{
        for (final entry in photoKeys.entries)
          if (entry.key != photoId) entry.key: entry.value,
      },
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'teamNumber': teamNumber,
      'eventKey': eventKey,
      'fieldValues': fieldValues,
      'authorUid': authorUid,
      'authorDisplayName': authorDisplayName,
      'photoIds': photoIds,
      'photoKeys': photoKeys,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toRemoteJson() {
    final json = toJson();
    json.remove('photoIds');
    json['photoKeys'] = photoKeys.values.toList(growable: false);
    return json;
  }

  factory PitScoutEntry.fromJson(Map<String, dynamic> json) {
    final rawFieldValues =
        (json['fieldValues'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final rawUpdatedAt = json['updatedAt'] as String? ?? '';
    return PitScoutEntry(
      id: json['id'] as String?,
      teamNumber: (json['teamNumber'] as num?)?.toInt() ?? 0,
      eventKey: (json['eventKey'] as String?) ?? '',
      fieldValues: rawFieldValues,
      authorUid: (json['authorUid'] as String?) ?? '',
      authorDisplayName: (json['authorDisplayName'] as String?) ?? '',
      photoIds: (json['photoIds'] as List?)?.cast<String>() ?? <String>[],
      photoKeys: _photoKeysFrom(json['photoKeys']),
      updatedAt: DateTime.tryParse(rawUpdatedAt) ?? DateTime.now().toUtc(),
    );
  }

  static Map<String, String> _photoKeysFrom(Object? raw) {
    if (raw is Map) {
      return <String, String>{
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    }
    if (raw is List) {
      return <String, String>{
        for (final key in raw)
          if (key is String && key.isNotEmpty) key: key,
      };
    }
    return const <String, String>{};
  }
}
