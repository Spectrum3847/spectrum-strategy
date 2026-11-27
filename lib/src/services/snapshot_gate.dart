abstract interface class PendingAwareSync {
  Set<String> get unconfirmedIds;
}

class SnapshotGate {
  const SnapshotGate({required this.unconfirmedIds, required this.markSynced});

  factory SnapshotGate.of({
    required bool isFromCache,
    required Iterable<({String id, bool hasPendingWrites})> docs,
  }) {
    return SnapshotGate(
      unconfirmedIds: {
        for (final doc in docs)
          if (isFromCache || doc.hasPendingWrites) doc.id,
      },
      markSynced: !isFromCache,
    );
  }

  final Set<String> unconfirmedIds;
  final bool markSynced;
}
