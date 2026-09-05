import 'package:spectrumstrategy/src/models/pick_list.dart';
import 'package:spectrumstrategy/src/services/pick_list_storage.dart';

class FakePickListStorage implements PickListStorage {
  final Map<String, PickList> _data = <String, PickList>{};

  @override
  Future<List<PickList>> loadAll() async => _data.values.toList();

  @override
  Future<void> save(PickList list) async => _data[list.id] = list;

  @override
  Future<void> delete(String id) async => _data.remove(id);

  @override
  Future<Set<String>> loadSyncedIds() async => <String>{};

  @override
  Future<void> saveSyncedIds(Set<String> ids) async {}
}
