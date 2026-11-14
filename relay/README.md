# Spectrum AI relay

A small background service that answers the app's AI features with a local
model. It does two jobs.

- Summaries. The PWA posts a request to `assistantRequests`. The relay claims
  it, asks a local llama.cpp model, writes the answer to `assistantSummaries`
  and deletes the request.
- Private chat. A lead's browser opens a direct WebRTC data channel to the
  relay and the answer streams back over it. The question and the answer never
  touch Firestore or the chat hub. The relay keeps one WebSocket open to the
  hub, a Durable Object on the team's Cloudflare Worker, which lists the relay
  to leads and forwards their connection offers. The protocol is in
  `agent-docs/decisions/ai-chat-p2p.md`.

Nothing leaves the team's machine except Firestore traffic, the hub socket
and, for a chat, the peer-to-peer channel.

Who answers AI requests: the relay is the only answerer. The Flutter desktop
app used to answer them and is being removed.

It is one binary (`relay`). It downloads the official llama.cpp
`llama-server` build and a small GGUF model on first run, runs `llama-server`
as a child process on a random 127.0.0.1 port, and talks to its
OpenAI-compatible API. Targets: Linux (x86_64, Arm), macOS and
Windows.

## Install

Download the file for your computer from the
[relay-latest release](https://github.com/Spectrum3847/spectrum-strategy/releases/tag/relay-latest)
on the public mirror:

| System | File |
| --- | --- |
| Windows, Intel or AMD | `relay-windows-x86_64.exe` |
| Windows on Arm | `relay-windows-aarch64.exe` |
| macOS, Apple silicon | `relay-macos-aarch64.zip` |
| macOS, Intel | `relay-macos-x86_64.zip` |
| Linux, Intel or AMD | `relay-linux-x86_64.tar.gz` |
| Linux, Arm | `relay-linux-aarch64.tar.gz` |

Then double-click it. On macOS and Linux, unpack the archive first and
double-click the `relay` file inside. The relay copies itself to its own
folder, sets itself to start at login, starts, and opens the settings page in
your browser. You can delete the downloaded file afterwards.

The builds are not signed with an Apple or Microsoft certificate, so the
system asks once:

- Windows: SmartScreen says it protected your PC. Press More info, then Run
  anyway.
- macOS: right-click the file, choose Open, then press Open. Or open System
  Settings, Privacy & Security, and press Open Anyway.
- Linux: if the file manager asks, choose Run.

The relay copies itself to `bin/` under the data folder (see Files). Double-click
a newer download later and it replaces the installed copy and restarts.

To build it yourself with a current stable Rust:

    cd relay
    cargo build --release

Run the result with no arguments for the same setup, or use `relay install` to
register the file where it is without copying it. Either way, on Linux it is a
systemd user unit and the command also tries `loginctl enable-linger` so it
starts at boot without a login. On macOS it is a LaunchAgent. On Windows it is a
Task Scheduler logon task.

`tar` must be on the PATH to unpack llama.cpp. Linux and macOS have it, and so
does Windows 10 and later.

## Updates

The relay updates itself. About every six hours it reads the signed
`relay-checksums.txt` from the `relay-latest` release, which the public mirror
rebuilds whenever `relay/` changes on master. There is one channel and no
version choice.

It installs a new file only when all of these hold:

- The Ed25519 signature on `relay-checksums.txt` matches the public key
  compiled into the relay.
- The build number in the file is higher than the running build. Build numbers
  are UTC timestamps, so the relay never moves to an older build.
- The SHA-256 of the downloaded file matches the signed list.
- The new file reports the signed build number when it runs.

It then restarts through its start-at-login entry. The settings page shows the
build, the last check, a switch for automatic updates and a "Check now" button.
`relay update` does the same check from a terminal. Updates need start at login,
and a build made with `cargo build` has no build number and never updates.

The mirror workflow signs with the `RELAY_SIGNING_KEY` secret, an Ed25519
private key in PEM (PKCS#8). The matching public key is `PUBLIC_KEY` in
`src/update.rs`. Changing the key means shipping a relay with the new public key
before the secret changes, or every relay in the field refuses the next update.

## Sign in

Open the settings page, `http://localhost:47821/` (or run `relay gui`). Press
"Sign in with Google" and use the team account. This is the normal central
sign-in. The relay then keeps a refresh token on this device and writes as
that member, so the Firestore rules apply to it.

The sign-in page loads the Firebase web SDK from `www.gstatic.com`. Google
sign-in allows `localhost` by default. If the central project's authorized
domains no longer list `localhost`, sign-in fails with
`auth/unauthorized-domain` and the page says so. Add `localhost` to the
central project's Auth authorized domains. The address must be `localhost`;
`127.0.0.1` is not on the default list.

The account must be a member (scouter, strategy, admin or developer) in
`userProfiles`, the same as for the app. A request the same account posted is
never answered by the relay.

Private chat needs one more step. An admin adds the account's uid to
`appConfig/relay`, field `uids` (a list of strings), in the Firestore console.
The settings page shows the uid under "Account id". Until it is listed the
hub refuses the relay's connection (HTTP 401), the page shows a chat error, and
summaries keep working.

## The settings page

It shows who is signed in, whether the relay is on, what it is doing,
whether `llama-server` is running, the model, the last answer and the last
error. It also shows the private chat: whether the relay is available to leads,
how many chats are open and the last chat error. From it you can:

- Sign in or out.
- Pick another model: any https URL to a GGUF chat model, and optionally its
  SHA-256. The old model file is deleted.
- Turn automatic updates off, or check for an update now.
- Turn the relay off. This stops answering, stops `llama-server` and disables
  start at login. The process stays up, with only the page running, so you can
  turn it back on. It is gone at the next reboot or logout.

The page listens on 127.0.0.1 only and refuses requests whose Host or Origin is
not local.

## Commands

    relay            set up: copy itself, start at login, open the page
    relay run        run the service and the page (what auto start runs)
    relay gui        open the page in a browser
    relay status     running, signed in, last answer and error
    relay install    turn on, start now, start at login
    relay uninstall  turn off, stop, remove start at login
    relay update     check for a newer build now and install it
    relay version    print the build number

## Files

Config and the refresh token are under the OS config directory, models and
`llama-server` under the OS data directory (for example `~/.config/spectrum-relay`
and `~/.local/share/spectrum-relay` on Linux). `token.json` is readable by the
owner only. Set `SPECTRUM_RELAY_HOME` to keep everything under one folder
instead. `llama-server.log` in the data directory holds the model server's
output.

## Defaults and limits

- Model: Liquid AI LFM3-1.7B Q4_K_M, 1.1 GB, pinned to a repo commit and by
  SHA-256. It runs with temperature 0.1, top-k 50 and repeat penalty 1.1. It is
  under the LFM Open License v1.0, which is free to use for organizations under
  a $10M annual revenue threshold. Read the license before moving past it.
- llama.cpp: the newest release build with a CPU download for the platform,
  checked at most once a day and verified against the SHA-256 GitHub lists
  for it. When the check fails, the installed build keeps running. LFM3 needs
  b11960 or newer.
- The queue is polled every 10 seconds. Errors back off up to two minutes.
- `llama-server` starts when the first request arrives and stops after five
  idle minutes.
- A request older than 10 minutes, or claimed in the last 3, is left alone.
- The hub socket reconnects after a failure, waiting 1 second and doubling up
  to 60. The relay sends `ping` every 30 seconds and a fresh sign-in token every
  45 minutes. An offer arrives over the socket at once, so nothing polls for
  chats. It serves up to 4 chats at once, and runs one ask at a time across
  chats and summaries. A second ask gets "busy". Connections use the STUN and,
  when the team has set up Cloudflare Realtime TURN, UDP TURN servers the hub
  sends with each offer. TURN over TCP or TLS is skipped, because the WebRTC
  library gathers from UDP only.
- A chat ask may carry up to 8000 characters of system text, 200000 of prompt
  and 2048 tokens of answer. llama-server's 8192 token context is the real limit.

## Develop

    cargo fmt --check
    cargo clippy --all-targets -- -D warnings
    cargo test

`tests/p2p_loopback.rs` runs the chat over real WebRTC on the loopback
interface against a scripted model, with offers arriving as the hub's
messages. `tests/hub_socket.rs` runs the hub client against a WebSocket server
on loopback. Neither needs the network.

An end to end test runs against the Firestore emulator with the repo's rules
and a real model. See the comment at the top of `tests/e2e.rs`. It never
touches production.

`tests/smoke.rs` downloads llama.cpp and a model, starts `llama-server` and
answers a fake request with no database. It is ignored by default.
