library;

import 'scout_shift_schedule.dart';

enum ShiftTradeStatus {
  pending,
  accepted,
  declined,
  cancelled;

  String get wireValue => name;

  static ShiftTradeStatus fromWire(String? value) {
    for (final status in ShiftTradeStatus.values) {
      if (status.wireValue == value) return status;
    }
    return ShiftTradeStatus.pending;
  }
}

class ShiftTrade {
  ShiftTrade({
    required this.id,
    required this.eventKey,
    required this.requesterUid,
    required this.requesterDisplayName,
    required this.targetUid,
    required this.targetDisplayName,
    required this.requesterBlock,
    this.targetBlock,
    this.status = ShiftTradeStatus.pending,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now().toUtc();

  final String id;
  final String eventKey;

  final String requesterUid;
  final String requesterDisplayName;

  final String targetUid;
  final String targetDisplayName;

  final ScoutShiftBlock requesterBlock;

  final ScoutShiftBlock? targetBlock;

  final ShiftTradeStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPending => status == ShiftTradeStatus.pending;

  bool involves(String uid) =>
      uid.isNotEmpty && (requesterUid == uid || targetUid == uid);

  ShiftTrade copyWith({ShiftTradeStatus? status, DateTime? updatedAt}) {
    return ShiftTrade(
      id: id,
      eventKey: eventKey,
      requesterUid: requesterUid,
      requesterDisplayName: requesterDisplayName,
      targetUid: targetUid,
      targetDisplayName: targetDisplayName,
      requesterBlock: requesterBlock,
      targetBlock: targetBlock,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'eventKey': eventKey,
    'requesterUid': requesterUid,
    'requesterDisplayName': requesterDisplayName,
    'targetUid': targetUid,
    'targetDisplayName': targetDisplayName,
    'requesterBlock': requesterBlock.toJson(),
    if (targetBlock != null) 'targetBlock': targetBlock!.toJson(),
    'status': status.wireValue,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static ShiftTrade fromJson(Map<String, dynamic> json) {
    final rawTargetBlock = json['targetBlock'];
    return ShiftTrade(
      id: json['id'] as String? ?? '',
      eventKey: json['eventKey'] as String? ?? '',
      requesterUid: json['requesterUid'] as String? ?? '',
      requesterDisplayName: json['requesterDisplayName'] as String? ?? '',
      targetUid: json['targetUid'] as String? ?? '',
      targetDisplayName: json['targetDisplayName'] as String? ?? '',
      requesterBlock: ScoutShiftBlock.fromJson(
        (json['requesterBlock'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      targetBlock: rawTargetBlock is Map
          ? ScoutShiftBlock.fromJson(rawTargetBlock.cast<String, dynamic>())
          : null,
      status: ShiftTradeStatus.fromWire(json['status'] as String?),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }
}
