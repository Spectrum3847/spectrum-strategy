# Contributing to Spectrum Strategy

Thanks for your interest. This repository is a release mirror, which changes the mechanics a little.

New to Git, GitHub, or Flutter? [docs/setup-guide.md](docs/setup-guide.md) walks
through installing everything from scratch on Windows, macOS, and Linux,
including a Docker/Podman path that does not require installing the Flutter
SDK at all, and a recommended git GUI client.

## How changes flow

- The team develops in a private repository. Every published release is synced here as one squashed commit with no internal history, so this repo and the private one do not share git history.
- Open an issue describing the change before you start working on it. One issue per piece of work; reference it from your PR (for example `Closes #123`).
- `master` is the default branch. Branch off it and target it.
- Your PR is reviewed and merged here like any other PR: CI runs the same gates listed below, and CodeRabbit leaves an automated review.
- Because this repo and the private one share no history, merging here is not the end of the road: the maintainer turns your merged PR into a patch and applies it to the private repo, preserving your commit authorship. Your change then ships in the next release and, from that point on, keeps surviving the sync (a change that only exists as a merge commit on this mirror would otherwise be overwritten the next time a release syncs). This step is on the maintainer, not something you need to do, but it is also why a merged PR here does not appear live until the next release goes out.

## Before you open a PR

- Toolchain: Flutter 3.47.2 / Dart 3.13.2.
- Run the same gates CI runs:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

- No local Flutter install? Run the same checks with
  [`scripts/docker-test.sh`](scripts/docker-test.sh) instead, using Docker or
  Podman.
- Keep changes small and focused, one concern per PR.
- No emojis anywhere: code, comments, docs, commit messages, or UI strings. Use plain text, or Material icons in UI.
- UI changes should keep the existing visual system: the palette tokens in `lib/src/theme/strategy_palette.dart`, Overpass type, flat surfaces, and 4px corners.

## License and attribution

By contributing you agree that your contribution is licensed under AGPL-3.0, the same license as this mirror. The private repository it gets ported into is not published under any license; by contributing here you also grant Spectrum 3847 permission to incorporate your change there under the same terms as the rest of that codebase. Your authorship is preserved on the commit that lands in the private repo and you keep your copyright either way.
