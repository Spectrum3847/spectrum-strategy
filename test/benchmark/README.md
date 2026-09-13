# Benchmarks

Measurement harnesses for the performance pass in #1450. They are not tests:
nothing here asserts, and `flutter test` only runs `*_test.dart`, so these
never run in CI and cost no minutes. Run one when a change claims to make
something faster, and quote the before and after in the PR.

```bash
flutter test test/benchmark/storage_bench.dart
flutter test test/benchmark/sync_bench.dart
flutter test test/benchmark/database_tab_bench.dart
```

Every number comes out of the debug test VM, which is slower than a release
build and does not touch a real disk or a real platform channel. Treat them as
a shape (linear, quadratic, flat) and a ratio between two options, not as a
prediction of milliseconds on a Kindle.

Baseline figures, and what they say about the app, are in
`agent-docs/decisions/performance-baseline.md`.
