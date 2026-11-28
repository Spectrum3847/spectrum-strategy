# Running Spectrum Strategy for your own team

The app we host is wired to Spectrum 3847's Firebase project. You cannot point
it somewhere else from Settings, because there is no URL to change: the backend
is Firebase, and its identifiers are part of the build. To run this app on your
own data you fork the repository, put your own Firebase project into it, and
build and host it yourself.

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
- Node 26 and pnpm 12. If you have never installed them,
  [docs/setup-guide.md](setup-guide.md) walks through Windows, macOS, and Linux.
- The Firebase CLI (`npm install -g firebase-tools`).
- A team key from [The Blue Alliance](https://www.thebluealliance.com/account),
  free. Statbotics needs no key.

## 1. Fork this repository

Fork it, clone your fork, and run `pnpm install --frozen-lockfile` in `app/`.
That is the only repository you need; everything Spectrum-specific is either a
build flag or a config file you edit.

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

## 3. Put your Firebase config in the app

In the Firebase console, open Project settings > Your apps on **yourteam-app**
and add a web app. Copy its config object into `dataConfig` in
`app/src/firebase/config.ts`. These are public client identifiers, not secrets.

## 4. Deploy the rules

```
firebase use yourteam-app
firebase deploy --only firestore:rules,firestore:indexes
```

Do this before anyone signs in. The default Firestore rules either lock
everything out or leave your scouting data world-writable, and neither is what
you want at an event.

## 5. Point the central handshake at your project

On **yourteam-central**, add a web app the same way and copy its config object
into `centralConfig` in `app/src/firebase/config.ts`. In Authentication >
Settings > Authorized domains, add the domain you will serve the app from.

The callable is `getCustomToken` in `us-central1`, so the app finds it through
the central project's config without any further setting.

In `firebase.json`, the web site's `Content-Security-Policy-Report-Only` header
lists `https://us-central1-spectrumtasks-81c63.cloudfunctions.net` in
`connect-src`. Swap in your own.

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

## 7. Build and host

The app key is a build-time value, and a build with an empty key refuses to sign
in and says so. The default is Spectrum's key, so set your own:

```
cd app
echo "VITE_SPECTRUM_APP_KEY=yourapp" > .env
pnpm build
```

Use the same app-key string you wrote into `apps/{key}`. Then host `app/dist` on
Firebase Hosting for your app project, or on any static host that serves
`index.html` for every path and sends `Cache-Control: no-cache` for `/sw.js` and
`/index.html`. `firebase.json` has a working Hosting entry: change its `site` to
yours and run `firebase deploy --only hosting`.

Run `pnpm dev` to try it locally first. Phones and iPads install the app from
the hosted address: open it in the browser and add it to the Home Screen.

## 8. Make yourself an admin

A first sign-in creates `userProfiles/{uid}` with the `scouter` role. Scouters
do not open the Users page, so nobody can promote anybody and you are stuck.

Break the loop in the Firebase console: open `userProfiles/{your uid}` on the
app project and change `roles` to `["admin"]`. From then on the Users page
handles everyone else.

## 9. Add your API keys

Sign in as admin, then create `appConfig/apiKeys` on the app project with
whichever of these you have. All are string fields, all optional except `tba`:

| Field | What it is |
| --- | --- |
| `tba` | The Blue Alliance read key. Without it, rankings and the schedule fall back to what Statbotics has. |
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
app from.

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

## Optional: the cron Worker

Jobs that would otherwise need the app open, or a scheduled Node job, run as
one Cloudflare Worker, `scripts/cron-worker/`, each on its own route so it can
run on its own schedule. The Worker also serves Web Push reminders and the
private AI chat hub. The app works without it, so treat this as a later
afternoon, not part of the first one.

| Job | Route | What it does | Needs | Suggested cadence |
| --- | --- | --- | --- | --- |
| `shift` | `/run/shift` | Shift-start and shift-trade Slack DMs, and the Web Push shift reminder | `SPECTRUM_PLATFORM_SERVICE_ACCOUNT`, `SLACK_BOT_TOKEN`, `VAPID_PRIVATE_KEY` | Every 5 minutes |
| `accuracy` | `/run/accuracy` | Compares a scouter's entry against the match result and Slacks them when it is off | `SLACK_BOT_TOKEN` (optional; in-app alert only without it) | Every 5 minutes |
| `report` | `/run/report` | Turns in-app reports into GitHub issues, attaching any screenshot from the `PHOTOS` R2 bucket | `GH_TOKEN` | Every 5 minutes |
| `scheduleMirror` | `/run/scheduleMirror` | Mirrors the pit crew's schedule and the scouting rotation between this app and SpectrumPit | `PIT_FIREBASE_SERVICE_ACCOUNT` | Every 5 minutes |
| `usage` | `/run/usage` | Rolls up telemetry so the Usage page has numbers | Nothing extra | Once a day |
| `backup` | `/run/backup` | Copies the top-level collections to the R2 bucket | Nothing extra | Hourly |

Every job expects `FIREBASE_SERVICE_ACCOUNT` (a service account JSON for
your app project) and reads the rest of its configuration from Firestore
under `appConfig`, for example the accuracy mapping from
`appConfig/accuracyMapping`. There is no Node runtime underneath a Worker,
so Firestore is read and written over its REST API with an access token
minted from the service account, not `firebase-admin`.

Edit `wrangler.jsonc` with your own `account_id`, `FIREBASE_PROJECT`,
`PLATFORM_PROJECT`, `PIT_PROJECT`, `GITHUB_REPO`, and R2 bucket name, then
deploy the same way as the photo Worker:

```
cd scripts/cron-worker
pnpm dlx wrangler@latest deploy
```

Set `FIREBASE_SERVICE_ACCOUNT`, `PIT_FIREBASE_SERVICE_ACCOUNT`,
`SPECTRUM_PLATFORM_SERVICE_ACCOUNT`, `SLACK_BOT_TOKEN`, `GH_TOKEN`, and a
`RUN_TOKEN` you choose yourself, as Worker secrets with `wrangler secret
put`; the Worker skips any job whose secrets are missing rather than
failing.

Something has to call each job's route on a schedule; there is no cadence
inside the Worker. The Cloudflare account's five free cron triggers may
already be spoken for, so an external scheduler (for example cron-job.org)
works without needing one: create one entry per route, each a `POST` with
`RUN_TOKEN` in the `X-Run-Token` header, on the cadence from the table
above. A route also runs its job on demand, so `POST /run/<jobName>` by
hand is how you trigger one to test it.

The Slack jobs need a bot token from your own Slack workspace, and `shift`
and `accuracy` message a person by the `slackId` on their profile, so that
has to be filled in before either reaches anyone.

## What you do not get

- The `getCustomToken` function itself. It lives in another Spectrum app, not
  in this repository, which is why section 6 has you write your own.
- Our hosted app, its install base and its release cadence. You build, host and
  update your own.

## What you can also run

- **The MCP server**, which lets an AI agent read the database, is open source
  at [Project516/spectrum-mcp](https://github.com/Project516/spectrum-mcp). It
  holds no service account and acts as the signed-in user, so your
  `firestore.rules` governs it the same way it governs the app.
- **GitHub Actions** can test and deploy your fork. `.github/workflows/ci.yml`
  comes with the fork and runs the app's typecheck, tests and build on every
  pull request. A public repository gets free minutes. The nightly and relay
  workflows sync from our repository, so delete them from your fork.

## Keeping up with releases

Your fork will drift. Each of our releases lands here as one squashed commit,
so rebasing your changes onto it is usually clean, since your changes sit in a
handful of files: `app/src/firebase/config.ts`, `firebase.json` and your `.env`.
Watch this repository's releases and pull when you want the newer version.
Nothing is automatic.

## License

This mirror is [AGPL-3.0](../LICENSE). Running a modified copy for your own
team is fine. If you run one as a service other people use, or hand out
modified builds, you owe them the source under the same license.

## If you get stuck

Open an issue on this repository. Say which step you are on and paste the
error code the sign-in screen shows; it names the failure kind, which is
usually enough to tell a rules problem from a central-handshake one.
