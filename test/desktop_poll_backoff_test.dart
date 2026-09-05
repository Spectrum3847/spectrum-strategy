import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/services/desktop_poll_backoff.dart';

void main() {
  group('pollDelayFor', () {
    const base = Duration(seconds: 30);

    test('no failures yet: the base interval', () {
      expect(pollDelayFor(base, 0), base);
    });

    test('doubles per consecutive failure, capped at 16x', () {
      expect(pollDelayFor(base, 1), base);
      expect(pollDelayFor(base, 2), base * 2);
      expect(pollDelayFor(base, 3), base * 4);
      expect(pollDelayFor(base, 4), base * 8);
      expect(pollDelayFor(base, 5), base * 16);
      expect(pollDelayFor(base, 6), base * 16);
      expect(pollDelayFor(base, 50), base * 16);
    });
  });

  group('DesktopPollScheduler', () {
    test('ticks at the base interval while every poll succeeds', () {
      fakeAsync((async) {
        var ticks = 0;
        final scheduler = DesktopPollScheduler(const Duration(seconds: 30));
        scheduler.start(() {
          ticks++;
          scheduler.onSuccess();
        });

        async.elapse(const Duration(seconds: 30));
        expect(ticks, 1);
        async.elapse(const Duration(seconds: 30));
        expect(ticks, 2);

        scheduler.cancel();
      });
    });

    test('backs off on consecutive failures and resets on success', () {
      fakeAsync((async) {
        var ticks = 0;
        var shouldFail = true;
        final scheduler = DesktopPollScheduler(const Duration(seconds: 30));
        scheduler.start(() {
          ticks++;
          if (shouldFail) {
            scheduler.onFailure();
          } else {
            scheduler.onSuccess();
          }
        });

        async.elapse(const Duration(seconds: 30));
        expect(ticks, 1);
        expect(scheduler.currentDelay, const Duration(seconds: 30));

        async.elapse(const Duration(seconds: 30));
        expect(ticks, 2);
        expect(scheduler.currentDelay, const Duration(seconds: 60));

        shouldFail = false;
        async.elapse(const Duration(seconds: 60));
        expect(ticks, 3);
        expect(scheduler.currentDelay, const Duration(seconds: 30));

        scheduler.cancel();
      });
    });

    test('cancel stops further ticks', () {
      fakeAsync((async) {
        var ticks = 0;
        final scheduler = DesktopPollScheduler(const Duration(seconds: 30));
        scheduler.start(() => ticks++);
        scheduler.cancel();

        async.elapse(const Duration(minutes: 10));
        expect(ticks, 0);
      });
    });

    test('start cancels a timer already running', () {
      fakeAsync((async) {
        var firstTicks = 0;
        var secondTicks = 0;
        final scheduler = DesktopPollScheduler(const Duration(seconds: 30));
        scheduler.start(() => firstTicks++);
        scheduler.start(() => secondTicks++);

        async.elapse(const Duration(seconds: 30));
        expect(firstTicks, 0);
        expect(secondTicks, 1);

        scheduler.cancel();
      });
    });

    test('cancel during an in-flight tick does not resurrect the loop', () {
      fakeAsync((async) {
        var ticks = 0;
        final scheduler = DesktopPollScheduler(const Duration(seconds: 30));
        scheduler.start(() async {
          ticks++;

          await Future<void>.delayed(const Duration(seconds: 5));
        });

        async.elapse(const Duration(seconds: 32));
        expect(ticks, 1);
        scheduler.cancel();
        async.elapse(const Duration(minutes: 30));

        expect(ticks, 1);
      });
    });

    test('start during an in-flight tick leaves exactly one live chain', () {
      fakeAsync((async) {
        var firstTicks = 0;
        var secondTicks = 0;
        final scheduler = DesktopPollScheduler(const Duration(seconds: 30));
        scheduler.start(() async {
          firstTicks++;
          await Future<void>.delayed(const Duration(seconds: 5));
        });

        async.elapse(const Duration(seconds: 32));
        scheduler.start(() => secondTicks++);
        async.elapse(const Duration(minutes: 2));

        expect(firstTicks, 1);
        expect(secondTicks, 4);

        scheduler.cancel();
      });
    });
  });
}
