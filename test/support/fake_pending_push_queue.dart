import 'package:spectrumstrategy/src/services/pending_push_queue.dart';

class FakePendingPushQueue extends PendingPushQueue {
  FakePendingPushQueue() : super();

  final Map<String, Set<String>> _store = <String, Set<String>>{};

  @override
  Future<Set<String>> pending(String collection) async =>
      _store[collection]?.toSet() ?? <String>{};

  @override
  Future<void> mark(String collection, String id) async {
    _store.putIfAbsent(collection, () => <String>{});
    _store[collection]!.add(id);
  }

  @override
  Future<void> clear(String collection, String id) async {
    _store[collection]?.remove(id);
  }

  @override
  Future<int> count(String collection) async => _store[collection]?.length ?? 0;
}
