import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/in_flight_local_writes.dart';

void main() {
  test('records nothing outside a window', () {
    final writes = InFlightLocalWrites<String>();
    expect(writes.isRecording, isFalse);
    writes.recordPush('a', 'local', 1);
    writes.recordDelete('b', 1);
    final resolved = writes.resolve(<String, String>{'b': 'remote'});
    expect(resolved, <String, String>{'b': 'remote'});
  });

  test('a push during the window survives a snapshot that omits it', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordPush('a', 'local', 1);
    expect(writes.resolve(<String, String>{'b': 'remote'}), <String, String>{
      'b': 'remote',
      'a': 'local',
    });
  });

  test('a delete during the window is not resurrected by the snapshot', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordDelete('a', 1);
    expect(
      writes.resolve(<String, String>{'a': 'remote', 'b': 'remote'}),
      <String, String>{'b': 'remote'},
    );
  });

  test('a push wins over the snapshot value for the same id', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordPush('a', 'local', 1);
    expect(writes.resolve(<String, String>{'a': 'stale'}), <String, String>{
      'a': 'local',
    });
  });

  test('delete then push on one id in one window resolves to the push', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordDelete('a', 1);
    writes.recordPush('a', 'local', 2);
    expect(writes.resolve(<String, String>{'a': 'stale'}), <String, String>{
      'a': 'local',
    });
  });

  test('push then delete on one id in one window resolves to the delete', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordPush('a', 'local', 1);
    writes.recordDelete('a', 2);
    expect(writes.resolve(<String, String>{'a': 'stale'}), isEmpty);
  });

  test('resolve closes the window so the next fetch starts clean', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordDelete('a', 1);
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
    writes.recordPush('a', 'local', 1);
    writes.abandonFetch();
    expect(writes.isRecording, isFalse);
    expect(writes.resolve(<String, String>{'b': 'remote'}), <String, String>{
      'b': 'remote',
    });
  });

  test('beginFetch discards a window left open by a previous fetch', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordDelete('a', 1);
    writes.beginFetch();
    expect(writes.resolve(<String, String>{'a': 'remote'}), <String, String>{
      'a': 'remote',
    });
  });

  test('a write outstanding across a fetch survives its snapshot', () {
    final writes = InFlightLocalWrites<String>();

    final token = writes.beginPush('a', 'local');
    writes.beginFetch();
    expect(writes.resolve(<String, String>{}), <String, String>{'a': 'local'});
    writes.endWrite('a', token);
    writes.beginFetch();
    expect(writes.resolve(<String, String>{}), isEmpty);
  });

  test('a delete outstanding across a fetch is not resurrected', () {
    final writes = InFlightLocalWrites<String>();
    final token = writes.beginDelete('a');
    writes.beginFetch();
    expect(writes.resolve(<String, String>{'a': 'stale'}), isEmpty);
    writes.endWrite('a', token);
    writes.beginFetch();
    expect(writes.resolve(<String, String>{'a': 'stale'}), <String, String>{
      'a': 'stale',
    });
  });

  test('an outstanding write applies to every snapshot until it ends', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginPush('a', 'local');
    for (var i = 0; i < 3; i++) {
      writes.beginFetch();
      expect(writes.resolve(<String, String>{}), <String, String>{
        'a': 'local',
      });
    }
  });

  test('a completed write wins over one still outstanding for the same id', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginPush('a', 'outstanding');
    writes.beginFetch();
    writes.recordPush('a', 'completed', 1);
    expect(writes.resolve(<String, String>{}), <String, String>{
      'a': 'completed',
    });
  });

  test('an older write ending does not clear a newer one for the same id', () {
    final writes = InFlightLocalWrites<String>();
    final older = writes.beginPush('a', 'older');
    writes.beginPush('a', 'newer');
    writes.endWrite('a', older);
    writes.beginFetch();
    expect(writes.resolve(<String, String>{}), <String, String>{'a': 'newer'});
  });

  test('abandonFetch leaves an outstanding write in place', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginDelete('a');
    writes.beginFetch();
    writes.abandonFetch();
    writes.beginFetch();
    expect(writes.resolve(<String, String>{'a': 'stale'}), isEmpty);
  });
  test('a fetch opened before the session ended resolves to null', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.endSession();
    expect(writes.resolve(<String, String>{'a': 'theirs'}), isNull);
  });

  test('the next fetch after a session ends resolves normally', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.endSession();
    expect(writes.resolve(<String, String>{'a': 'theirs'}), isNull);
    writes.beginFetch();
    expect(writes.resolve(<String, String>{'a': 'mine'}), <String, String>{
      'a': 'mine',
    });
  });

  test('ending a session drops recorded and outstanding writes alike', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginPush('a', 'outstanding');
    writes.beginFetch();
    writes.recordDelete('b', 1);
    writes.endSession();

    writes.beginFetch();
    expect(writes.resolve(<String, String>{'b': 'theirs'}), <String, String>{
      'b': 'theirs',
    });
  });

  test('syncSession ends the session only when the uid changes', () {
    final writes = InFlightLocalWrites<String>();
    writes.syncSession('u1');
    final token = writes.beginPush('a', 'local');

    writes.syncSession('u1');
    expect(writes.isOpen('a', token), isTrue);
    writes.beginFetch();
    expect(writes.resolve(<String, String>{}), <String, String>{'a': 'local'});

    writes.syncSession('u2');
    expect(writes.isOpen('a', token), isFalse);
    writes.beginFetch();
    expect(writes.resolve(<String, String>{}), isEmpty);
  });

  test('syncSession treats the first uid it sees as a change', () {
    final writes = InFlightLocalWrites<String>();
    final token = writes.beginPush('a', 'local');
    writes.syncSession('u1');
    expect(writes.isOpen('a', token), isFalse);
  });

  test('signing out and back in as the same user still ends the session', () {
    final writes = InFlightLocalWrites<String>();
    writes.syncSession('u1');
    final token = writes.beginPush('a', 'local');
    writes.syncSession(null);
    writes.syncSession('u1');
    expect(writes.isOpen('a', token), isFalse);
  });

  test('isOpen is false once a newer write for the same id starts', () {
    final writes = InFlightLocalWrites<String>();
    final older = writes.beginPush('a', 'older');
    final newer = writes.beginPush('a', 'newer');
    expect(writes.isOpen('a', older), isFalse);
    expect(writes.isOpen('a', newer), isTrue);
  });

  test('two completed writes for one id keep the newer value when they land in reverse order', () {
    final writes = InFlightLocalWrites<String>();
    writes.beginFetch();
    writes.recordPush('a', 'newer', 2);
    writes.recordPush('a', 'older', 1);
    expect(writes.resolve(<String, String>{}), <String, String>{'a': 'newer'});
  });

  test(
    'a delete landing after a newer push does not resurrect as a delete',
    () {
      final writes = InFlightLocalWrites<String>();
      writes.beginFetch();
      writes.recordPush('a', 'newer', 2);
      writes.recordDelete('a', 1);
      expect(writes.resolve(<String, String>{}), <String, String>{
        'a': 'newer',
      });
    },
  );
}
