import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/in_flight_local_writes.dart';

void main() {
  test('records nothing outside a window', () {
    final writes = InFlightLocalWrites<String>();
    expect(writes.isRecording, isFalse);
    writes.recordPush('a', 'local');
    writes.recordDelete('b');
    final resolved = writes.resolve(<String, String>{'b': 'remote'});
    expect(resolved, <String, String>{'b': 'remote'});
  });

  test('a push during the window survives a snapshot that omits it', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordPush('a', 'local');
    expect(writes.resolve(<String, String>{'b': 'remote'}), <String, String>{
      'b': 'remote',
      'a': 'local',
    });
  });

  test('a delete during the window is not resurrected by the snapshot', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordDelete('a');
    expect(
      writes.resolve(<String, String>{'a': 'remote', 'b': 'remote'}),
      <String, String>{'b': 'remote'},
    );
  });

  test('a push wins over the snapshot value for the same id', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordPush('a', 'local');
    expect(writes.resolve(<String, String>{'a': 'stale'}), <String, String>{
      'a': 'local',
    });
  });

  test('delete then push on one id in one window resolves to the push', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordDelete('a');
    writes.recordPush('a', 'local');
    expect(writes.resolve(<String, String>{'a': 'stale'}), <String, String>{
      'a': 'local',
    });
  });

  test('push then delete on one id in one window resolves to the delete', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordPush('a', 'local');
    writes.recordDelete('a');
    expect(writes.resolve(<String, String>{'a': 'stale'}), isEmpty);
  });

  test('resolve closes the window so the next fetch starts clean', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordDelete('a');
    writes.resolve(<String, String>{});
    expect(writes.isRecording, isFalse);

    writes.beginFetch();
    expect(writes.resolve(<String, String>{'a': 'remote'}), <String, String>{
      'a': 'remote',
    });
  });

  test('abandonFetch drops the window without applying it', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordPush('a', 'local');
    writes.abandonFetch();
    expect(writes.isRecording, isFalse);
    expect(writes.resolve(<String, String>{'b': 'remote'}), <String, String>{
      'b': 'remote',
    });
  });

  test('beginFetch discards a window left open by a previous fetch', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordDelete('a');
    writes.beginFetch();
    expect(writes.resolve(<String, String>{'a': 'remote'}), <String, String>{
      'a': 'remote',
    });
  });
}
