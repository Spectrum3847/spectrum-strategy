# Contributing to Spectrum Strategy

Thanks for your interest. This repository is a release mirror, which changes the mechanics a little.

## How changes flow

- The team develops in a private repository. Every published release is synced here as one squashed commit.
- Pull requests here are reviewed by the maintainer. When accepted, the change is applied to the internal repository and ships in the next release, with credit in the release notes. The release then syncs back here.
- Because each release replaces this tree with a snapshot, your merged commit may be rewritten by the next sync. The change itself survives through the internal port.

## Before you open a PR

- Toolchain: Flutter 3.44.4 / Dart 3.11.5.
- Run the same gates CI runs:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

- Keep changes small and focused, one concern per PR.
- No emojis anywhere: code, comments, docs, commit messages, or UI strings. Use plain text, or Material icons in UI.
- UI changes should follow `DESIGN.md`: the existing palette tokens, Overpass type, flat surfaces, and 4px corners.

## License

By contributing you agree that your contribution is licensed under AGPL-3.0, the same license as the project.
