# Setup guide: contributing with no prior coding experience

This guide is for someone who has never used a terminal or contributed to a
project on GitHub before. It covers Windows, macOS, and Linux, and how to get
the project running by installing Node.js and pnpm.

If you already know Git and Node, you probably want
[CONTRIBUTING.md](../CONTRIBUTING.md) instead.

## Words this guide uses

A few terms come up repeatedly. Here is what each one means, in one line:

- **Terminal**: a text window where you type commands instead of clicking.
  Windows calls it PowerShell or Command Prompt, macOS calls it Terminal,
  Linux distributions usually just call it Terminal.
- **Repository (repo)**: the project's folder of code and its full history,
  stored on GitHub.
- **Clone**: downloading a copy of a repository onto your own computer.
- **Fork**: your own copy of someone else's repository on GitHub, which you
  can change freely before proposing those changes back.
- **Branch**: a named line of work inside a repository, so your changes sit
  separately from the main line (called `master` in this project) until
  they are reviewed.
- **Commit**: a saved snapshot of the changes you made, with a short message
  describing them.
- **Push**: uploading your commits from your computer to GitHub.
- **Pull request (PR)**: a request asking the maintainer to review and merge
  your branch into `master`.

## The easiest way to do all of this: a git GUI client

You do not need to type Git commands. [Desktop Plus](https://desktop-plus.org/)
is a git client with buttons for the steps above: clone or fork a repository,
create a branch, see what you changed, write a commit message, push, and open
a pull request, all without a terminal. It runs on Windows, macOS, and Linux.

Install it from the official releases:

- Windows: `winget install DesktopPlus.DesktopPlus`, or download the `.exe`
  from the [releases page](https://github.com/desktop-plus/desktop-plus/releases/latest).
- macOS: `brew install desktop-plus/tap/desktop-plus`, or download the `.zip`
  from the same releases page.
- Linux: `flatpak install flathub org.desktop_plus.desktop-plus` works on any
  distribution. Debian/Ubuntu (apt), Fedora (dnf), and Arch (AUR) packages
  are also listed on the [Desktop Plus install page](https://desktop-plus.org/install).

Once it is installed, sign in with your GitHub account, then use it to clone
this repository (or your fork of it) to your computer. Everything below still
tells you what to run and check; you can run the terminal commands from
Desktop Plus's own terminal view, or from your OS terminal, whichever you
find easier.

## Running the project's checks

Before you open a pull request, three checks need to pass. Running them means
installing Node.js and pnpm, which also gives you `pnpm dev` too, so you can see
the app itself and not just the checks.

The project needs Node 26 and pnpm 12. Install those versions, not whatever is
newest: the lockfile and the checks assume them.

## Windows, macOS and Linux

1. Install [Git](https://git-scm.com/downloads) if you do not already have it
   (Desktop Plus needs it, or you can use Git Bash directly).
2. Install [Node.js 26](https://nodejs.org/en/download). The Node download page
   lists installers for Windows, macOS and Linux.
3. Install pnpm by following the official [pnpm install
   guide](https://pnpm.io/installation), then check that `pnpm --version`
   starts with 12.
4. Clone the repository (with Desktop Plus, or `git clone` in a terminal), then
   from inside the `app` folder run:

   ```
   pnpm install --frozen-lockfile
   pnpm typecheck
   pnpm test
   pnpm build
   ```

5. To see the app, run `pnpm dev` and open the address it prints.

## What the checks mean

- `pnpm typecheck` runs the TypeScript compiler without writing files. It
  catches type mistakes.
- `pnpm test` runs the automated test suite.
- `pnpm build` makes the production build, the same one that gets deployed.
- `pnpm lint` and `pnpm format` check and fix how the code is formatted. Run
  both before you push.

The checks run again automatically on your pull request through GitHub
Actions, so it is fine if you are not certain everything passes locally
before you push. Running them first just saves a round trip.

## Making your first change

1. A pull request does not need an issue first. Open one if you want to
   discuss an idea before building it, or if you are reporting something you
   are not going to fix yourself; otherwise go straight to the change.
2. If you were invited to the repository directly, create a branch off
   `master` (the default branch) for your change. If you are working from
   your own fork, branch off `master` there instead.
3. Make your change.
4. Commit it with a short message describing what changed, using Desktop
   Plus's commit view or `git commit`.
5. Push the branch (Desktop Plus has a Push button, or `git push`).
6. Open a pull request from your branch (or your fork) back to this
   repository's `master` branch, and say in the description what the change
   is. If it does close an issue, write `Closes #123`.

## Rules this project holds contributors to

- No emojis, anywhere: not in code, comments, commit messages, or pull
  request text.
- `master` is the default branch; branch off it and target it.
- See [CONTRIBUTING.md](../CONTRIBUTING.md) for the rest, including the
  license terms your contribution is made under.
