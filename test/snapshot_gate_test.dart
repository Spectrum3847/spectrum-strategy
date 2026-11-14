import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/snapshot_gate.dart';

({String id, bool hasPendingWrites}) _doc(String id, {bool pending = false}) =>
    (id: id, hasPendingWrites: pending);

void main() {
  test('only the doc with an unsent write is unconfirmed', () {
    final gate = SnapshotGate.of(
      isFromCache: false,
      docs: [_doc('a'), _doc('b', pending: true)],
    );
    expect(gate.unconfirmedIds, {'b'});
    expect(gate.markSynced, isTrue);
  });

  test('a cache snapshot confirms nothing and does not report synced', () {
    final gate = SnapshotGate.of(
      isFromCache: true,
      docs: [_doc('a'), _doc('b')],
    );
    expect(gate.unconfirmedIds, {'a', 'b'});
    expect(gate.markSynced, isFalse);
  });

  test('the ack event after a pending write confirms the doc', () {
    final pending = SnapshotGate.of(
      isFromCache: false,
      docs: [_doc('a', pending: true)],
    );
    final acked = SnapshotGate.of(isFromCache: false, docs: [_doc('a')]);
    expect(pending.unconfirmedIds, {'a'});
    expect(acked.unconfirmedIds, isEmpty);
    expect(acked.markSynced, isTrue);
  });

  test('an empty server snapshot reports synced', () {
    final gate = SnapshotGate.of(isFromCache: false, docs: const []);
    expect(gate.unconfirmedIds, isEmpty);
    expect(gate.markSynced, isTrue);
  });
}
