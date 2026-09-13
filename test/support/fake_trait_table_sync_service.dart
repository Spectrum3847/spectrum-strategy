import 'dart:async';

import 'package:spectrumstrategy/src/models/trait_config.dart';
import 'package:spectrumstrategy/src/models/trait_table.dart';
import 'package:spectrumstrategy/src/services/trait_table_sync_service.dart';

class FakeTraitTableSyncService implements TraitTableSyncService {
  FakeTraitTableSyncService({this.uid = 'uid-1', this.displayName = 'Lead'});

  final String uid;
  final String displayName;

  final _tables = StreamController<TraitTable?>.broadcast();
  final _configs = StreamController<TraitConfig>.broadcast();

  final List<TraitTable> pushes = <TraitTable>[];

  final List<({String eventKey, String matchId})> watched = [];

  Object? failNextPush;

  bool disposed = false;

  @override
  Stream<TraitTable?> get tableStream => _tables.stream;

  @override
  Stream<TraitConfig> get configStream => _configs.stream;

  @override
  String? get currentUserUid => uid;

  @override
  String? get currentUserDisplayName => displayName;

  TraitTable? stored;

  @override
  Future<void> watch({
    required String eventKey,
    required String matchId,
  }) async {
    watched.add((eventKey: eventKey, matchId: matchId));

    _tables.add(stored);
  }

  @override
  Future<void> push(TraitTable table) async {
    final failure = failNextPush;
    if (failure != null) {
      failNextPush = null;
      throw failure;
    }
    pushes.add(table);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _tables.close();
    await _configs.close();
  }

  void emitTable(TraitTable? table) => _tables.add(table);
  void emitConfig(TraitConfig config) => _configs.add(config);
}

class LaggyTraitTableSyncService extends FakeTraitTableSyncService {
  int _pushes = 0;

  @override
  Future<void> push(TraitTable table) async {
    final isFirst = _pushes++ == 0;
    if (isFirst) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return super.push(table);
  }
}
