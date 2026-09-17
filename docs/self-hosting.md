# Running Spectrum Strategy for your own team

The builds we publish are wired to Spectrum 3847's Firebase project. You
cannot point them somewhere else from Settings, because there is no URL to
change: the backend is Firebase, and its identifiers are compiled into the
binary. To run this app on your own data you fork the repository, put your own
Firebase project into it, and build it yourself.

There is no lighter option. The app is gated on sign-in: an account with no
roles gets a "no access" screen and no tabs at all, so a build you cannot sign
in to does nothing. Our published builds only admit people on Spectrum's
roster. If you are not on it, self-hosting is the only way to run this app.

## What the backend is

Two Firebase projects, no server we wrote.

**Your app project** holds Firestore (scout entries, pick lists, boards,
config, roles) and the Firebase Auth session the app runs under.
`firestore.rules` in this repository is the only authorization there is;
everything else is a client talking straight to Firestore.

**A central project** owns the roster. Sign-in goes Google, then a session on
the central project, then a Cloud Function called `getCustomToken` that checks
the person is an approved member and that your app is registered, and mints a
custom token the app swaps for a session on the app project. Spectrum uses its
SpectrumTasks project for this so one roster covers several apps.

You have to stand up both. The second one is the part people underestimate:
`getCustomToken` is a Cloud Function, and Firebase only runs functions on the
Blaze pay-as-you-go plan, which wants a billing card even though a
team-sized load stays inside the free monthly allowance. Short of rewriting
sign-in there is no way around it. Your app project can stay on the free Spark
plan; ours does.

## Before you start

- A Google account, and a card for the Blaze plan.
- The Flutter SDK. This release pins Flutter 3.47.3 and Dart 3.13.3. If you
  have never installed it, [docs/setup-guide.md](setup-guide.md) walks through
  Windows, macOS, and Linux.
- The Firebase CLI (`npm install -g firebase-tools`) and the FlutterFire CLI
  (`dart pub global activate flutterfire_cli`).
- A team key from [The Blue Alliance](https://www.thebluealliance.com/account),
  free. Statbotics needs no key.

Budget an afternoon.

## 1. Fork this repository

Fork it, clone your fork, and run `flutter pub get`. That is the only
repository you need; everything Spectrum-specific is either a build flag or a
config file you regenerate.

## 2. Create your Firebase projects

In the [Firebase console](https://console.firebase.google.com/), create two
projects. Name them whatever you like; this guide calls them `yourteam-app`
and `yourteam-central`.

On **yourteam-app**:

- Build > Firestore Database > create a database, production mode, pick the
  region closest to your events.
- Build > Authentication > Sign-in method > enable Google.

On **yourteam-central**:

- The same two, plus upgrade the project to the Blaze plan so you can deploy
  a function.

## 3. Generate the app's Firebase config

From your clone:

```
flutterfire configure --project=yourteam-app
```

Pick the platforms you build for. That rewrites `lib/firebase_options.dart`
and drops `android/app/google-services.json` and
`ios/Runner/GoogleService-Info.plist` into place. On Android, register your
signing key's SHA-1 with the Firebase Android app afterwards, or Google
sign-in returns a token the project refuses.

## 4. Deploy the rules

```
firebase use yourteam-app
firebase deploy --only firestore:rules,firestore:indexes
```

Do this before anyone signs in. The default Firestore rules either lock
everything out or leave your scouting data world-writable, and neither is what
you want at an event.

## 5. Point the central handshake at your project

The central project id is a build define, so most of this is one flag you will
pass in step 7:

```
--dart-define=SPECTRUM_CENTRAL_PROJECT_ID=yourteam-central
```

The callable endpoint follows it automatically, resolving to
`https://us-central1-yourteam-central.cloudfunctions.net`. If you deploy the
function outside `us-central1` or behind a custom domain, override that too
with `--dart-define=SPECTRUM_CENTRAL_FUNCTIONS_BASE_URL=...`. It has to be
https either way, since that URL carries a bearer token.

Two files still need editing by hand:

In `lib/firebase_options_central.dart`, replace the values with your central
project's **web app** config, from the Firebase console under Project settings
> Your apps. These are public client identifiers, not secrets.

In `firebase.json`, the web builds' `Content-Security-Policy-Report-Only`
header lists `https://us-central1-spectrumtasks-81c63.cloudfunctions.net` in
`connect-src`. Swap in your own. Skip this if you do not deploy the web build.

## 6. Write the `getCustomToken` function

This is the one piece of backend code you have to supply. Ours lives in
another team app and is not published, so here is the contract the client
expects, and an implementation that satisfies it.

The client calls a v1 callable named `getCustomToken` in `us-central1` on your
central project, with the caller's central ID token as the bearer, and a body
of `{"data": {"targetApp": "<your app key>"}}`. It expects back:

```json
{"result": {
  "customToken": "...",
  "profile": {"displayName": "...", "email": "...", "role": "...",
              "photoURL": "...", "slackId": "..."}
}}
```

`profile` is optional and every field in it is optional. Two error codes carry
meaning: `permission-denied` means this person is not approved, and
`not-found` means the app is not registered. The sign-in screen turns both
into a readable message; anything else reads as a network or configuration
failure.

In `functions/index.js` on your central project:

```js
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();

exports.getCustomToken = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in first.");
  }
  const targetApp = data && data.targetApp;
  if (
    typeof targetApp !== "string" ||
    targetApp.length === 0 ||
    targetApp.includes("/")
  ) {
    throw new functions.https.HttpsError("invalid-argument", "targetApp required.");
  }

  const db = admin.firestore();

  const app = await db.doc(`apps/${targetApp}`).get();
  if (!app.exists || app.get("approved") !== true) {
    throw new functions.https.HttpsError("not-found", "App not registered.");
  }

  const uid = context.auth.uid;
  const user = await db.doc(`users/${uid}`).get();
  if (!user.exists || user.get("approved") !== true) {
    throw new functions.https.HttpsError("permission-denied", "Not approved.");
  }

  return {
    customToken: await admin.auth().createCustomToken(uid),
    profile: {
      displayName: user.get("displayName") || context.auth.token.name || null,
      email: user.get("email") || context.auth.token.email || null,
      photoURL: user.get("photoURL") || context.auth.token.picture || null,
    },
  };
});
```

Deploy it, then create the two documents it reads, by hand in the console:

- `apps/yourapp` with `approved: true`
- `users/<your central uid>` with `approved: true` and your `displayName`

Your central uid appears under Authentication > Users after you sign in to the
central project once, which happens the first time you try to sign in to the
app. Expect the first attempt to fail with "Account not approved", then add
the document, then try again. Every teammate needs a `users/<uid>` document
before they can get in, and that is the whole membership gate: no document, no
access.

The custom token is minted for the same uid the central project knows, so
`userProfiles/{uid}` in your app project and `users/{uid}` on the central
project line up.

## 7. Build

The app key is a build-time value with no default. A build without it refuses
to sign in and says so, which is deliberate.

```
flutter run \
  --dart-define=SPECTRUM_APP_KEY=yourapp \
  --dart-define=SPECTRUM_CENTRAL_PROJECT_ID=yourteam-central
```

Use the same app-key string you wrote into `apps/{key}`. Pass both defines on
every build, for every platform, or the binary talks to Spectrum's platform
and refuses your team.

Linux desktop has no FlutterFire, so it signs in through a loopback OAuth
flow instead and needs a Google OAuth client of type "Desktop app" from your
Google Cloud console:

```
flutter build linux \
  --dart-define=SPECTRUM_APP_KEY=yourapp \
  --dart-define=SPECTRUM_CENTRAL_PROJECT_ID=yourteam-central \
  --dart-define=GOOGLE_OAUTH_CLIENT_ID=...apps.googleusercontent.com \
  --dart-define=GOOGLE_OAUTH_CLIENT_SECRET=...
```

Desktop OAuth client secrets are not secret in the usual sense; Google's own
docs say a native app cannot keep one. Without these two the Linux build still
runs, local-only.

## 8. Make yourself an admin

A first sign-in creates `userProfiles/{uid}` with the `scouter` role. Scouters
do not see the Users tab, so nobody can promote anybody and you are stuck.

Break the loop in the Firebase console: open `userProfiles/{your uid}` on the
app project and change `roles` to `["admin"]`. From then on the Users tab
handles everyone else.

## 9. Add your API keys

Sign in as admin, then create `appConfig/apiKeys` on the app project with
whichever of these you have. All are string fields, all optional except `tba`:

| Field | What it is |
| --- | --- |
| `tba` | The Blue Alliance read key. Without it, team lists, avatars, and film review are empty. |
| `openrouter` | An [OpenRouter](https://openrouter.ai/) key for the AI summaries. Free-tier models work. |
| `huggingface` | Only speeds up local-model discovery in the desktop assistant. |
| `photoWorker` | The base URL of your photo service, if you deploy `scripts/photo-worker/` (see below). Leave it out and pit-scouting photos are the one thing that will not work. |

The rules let any member read this document and only admins write it, so you
set the team's TBA key once instead of on every phone.

## Optional: the photo service

Pit-scouting photos are bytes, and Firebase Cloud Storage needs the Blaze plan
your app project is not on, so they go through a small Cloudflare Worker over
an R2 bucket. Both are free at a team's volume. It ships here at
`scripts/photo-worker/`.

Create the R2 bucket, then edit `scripts/photo-worker/wrangler.jsonc`: your own
`account_id` in place of the placeholder, your `bucket_name`, `FIREBASE_PROJECT`
set to your app project, and `ALLOWED_ORIGINS` set to the origins you serve the
web build from (mobile and desktop send no `Origin`, so they need no entry).

```
cd scripts/photo-worker
pnpm dlx wrangler@latest deploy
```

Give the bucket a lifecycle rule expiring objects after 90 days. That plus the
Worker's 2 MB per-image ceiling keeps the bucket inside R2's free 10 GB, which
matters because R2 bills past it rather than stopping.

Then put the deployed URL in `appConfig/apiKeys.photoWorker`. There is no API
key anywhere in this: a request carries the caller's own Firebase ID token, and
the Worker re-presents that token to your Firestore to check the profile, so a
forged token fails at Firestore and the Worker never verifies one itself.

## Optional: the scheduled jobs

Four Node services in `scripts/` do the work that happens while nobody has the
app open. The app works without all of them, so treat this as a later
afternoon, not part of the first one:

| Service | What it does | Needs |
| --- | --- | --- |
| `accuracy-cron` | Compares a scouter's entry against the match result and Slacks them when it is off | `SLACK_BOT_TOKEN` |
| `shift-cron` | Reminds scouters on Slack when their shift is coming up | `SLACK_BOT_TOKEN` |
| `report-cron` | Posts post-match reports | `GH_TOKEN` |
| `usage-cron` | Rolls up telemetry so the Users tab has numbers | Nothing extra |

They run on Node 24 with pnpm, and every one of them takes its credentials
from the environment rather than from a file in the repository, so there is
nothing to fill in before you read the source. Each expects
`FIREBASE_SERVICE_ACCOUNT` (a service account JSON for your app project) and
reads the rest of its configuration from Firestore under `appConfig`: the
accuracy mapping from `appConfig/accuracyMapping`, the shift reminders from
`appConfig/activeEvent`.
Run one with `DRY_RUN=1` first; they all honour it.

The Slack ones need a bot token from your own Slack workspace, and they
message a person by the `slackId` on their profile, so those have to be filled
in before a reminder reaches anyone.

## What you do not get

- The `getCustomToken` function itself. It lives in another Spectrum app, not
  in this repository, which is why section 6 has you write your own.
- Our nightly builds and AltStore sources. The desktop app's update check is
  worse than missing: it is hard-coded to `Spectrum3847/spectrum-strategy`, so
  your fork will offer your team our builds and overwrite itself with them.
  Change `_defaultRepositories` in
  `lib/src/services/desktop_update_service.dart`, or turn the check off in
  Settings, before you hand a desktop build to anyone.

## What you can also run

- **The MCP server**, which lets an AI agent read the database, is open source
  at [Project516/spectrum-mcp](https://github.com/Project516/spectrum-mcp). It
  holds no service account and acts as the signed-in user, so your
  `firestore.rules` governs it the same way it governs the app.
- **GitHub Actions** can build your fork for you, which is the only practical
  way to get an iOS or Windows build without owning a Mac or a Windows box.
  `.github/workflows/nightly.yml` comes with the fork and already builds
  Android, iOS, desktop, and web, and a public repository gets free minutes.
  Two edits before it works for you: the `--dart-define=SPECTRUM_APP_KEY=`
  lines carry our app key as a literal, so change every one of them, and the
  `sync` job pulls from our repository, so delete it. The Android job wants
  your `google-services.json`, base64 encoded, in the fork's own
  `GOOGLE_SERVICES_JSON` Actions secret.

## Keeping up with releases

Your fork will drift. Each of our releases lands here as one squashed commit,
so rebasing your changes onto it is usually clean, since your changes sit in a
handful of files: `firebase_options.dart`, `firebase_options_central.dart`,
and `firebase.json`. Watch this repository's releases and pull
when you want the newer version. Nothing is automatic.

## License

This mirror is [AGPL-3.0](../LICENSE). Running a modified copy for your own
team is fine. If you run one as a service other people use, or hand out
modified builds, you owe them the source under the same license.

## If you get stuck

Open an issue on this repository. Say which step you are on and paste the
error code the sign-in screen shows; it names the failure kind, which is
usually enough to tell a rules problem from a central-handshake one.
