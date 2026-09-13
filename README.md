# Spectrum Strategy

An all in one strategy and scouting app for FRC teams, built by Spectrum 3847. One app, three surfaces that feed each other:

- **Strategy board**: draw match plans per phase (auton, teleop, endgame) over the season's field, with robot markers, notes, and PNG export.
- **Scouting**: a configurable per-match capture form (QRScout-compatible config), offline-first storage, QR transfer, and cloud sync.
- **Prematch**: event teams ranked by EPA and joined with your own scouting data, plus playoff ranking, film review, and pick lists.

Built with Flutter for iOS and Android.

## About this repository

This is the public mirror of Spectrum Strategy. The team develops in a private repository; each published release is synced here as a single squashed commit, so this repo always holds the source of the latest release without internal history.

## Running it for your own team

The builds we publish talk to Spectrum 3847's Firebase project, and you cannot
repoint them from Settings, because the project is compiled in. To run the app
on your own data you fork this repository, put your own Firebase project into
it, and build it yourself. [docs/self-hosting.md](docs/self-hosting.md) is the
full walkthrough, including the sign-in function you have to deploy and the
Blaze billing plan it needs.

The app is gated on sign-in, and our builds only admit people on Spectrum's
roster, so there is no lighter way to run this for another team.

## Contributing

Pull requests are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md). New to Git
or Flutter? [docs/setup-guide.md](docs/setup-guide.md) starts from scratch on
Windows, macOS, and Linux.

## License

[AGPL-3.0](LICENSE). If you distribute a modified version of this app, or run one as a service for others, you must make its source available under the same license.
