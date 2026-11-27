# Spectrum Strategy

An all in one strategy and scouting app for FRC teams, built by Spectrum 3847. One app, three surfaces that feed each other:

- **Strategy board**: draw match plans per phase (auton, teleop, endgame) over the season's field, with robot markers, notes, and PNG export.
- **Scouting**: a configurable per-match capture form (QRScout-compatible config), offline-first storage, QR transfer, and cloud sync.
- **Prematch**: event teams ranked by rating and joined with your own scouting data, plus playoff ranking and film review.

Built with Flutter for iOS, Android, web, and desktop (Windows, macOS, Linux).

## About this repository

This is the public mirror of Spectrum Strategy. The team develops in a private repository; each published release is synced here as a single squashed commit, so this repo always holds the source of the latest release without internal history.

The `relay/` folder is the headless service that answers AI summary requests with a local model. Its prebuilt binaries are on the [relay-latest release](https://github.com/Spectrum3847/spectrum-strategy/releases/tag/relay-latest).

## Running it for your own team

The builds we publish are for Spectrum 3847, and cannot be used for other teams.
To run the app for your team, fork this repository, and follow [docs/self-hosting.md](docs/self-hosting.md).

## Contributing

Pull requests are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md). New to Git
or Flutter? [docs/setup-guide.md](docs/setup-guide.md) starts from scratch on
Windows, macOS, and Linux. See [CONTRIBUTORS.md](CONTRIBUTORS.md) for who has
worked on this project.

## License

[AGPL-3.0](LICENSE). If you distribute a modified version of this app, or run one as a service for others, you must make its source available under the same license.

[![REUSE status](https://api.reuse.software/badge/github.com/Spectrum3847/spectrum-strategy)](https://api.reuse.software/info/github.com/Spectrum3847/spectrum-strategy)
