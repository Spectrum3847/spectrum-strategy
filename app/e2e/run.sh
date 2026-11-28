#!/usr/bin/env bash

set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
app=$(dirname "$here")
projects=${E2E_PROJECTS:-ipad iphone pixel laptop}
export E2E_OUT=${E2E_OUT:-$here/out}
mkdir -p "$E2E_OUT"

cd "$app"
pnpm install --frozen-lockfile
(cd e2e && pnpm install --frozen-lockfile --ignore-workspace)

VITE_FIREBASE_EMULATORS=true pnpm exec vite build --outDir dist-check --emptyOutDir
node e2e/check-build.mjs dist-check absent
rm -rf dist-check

VITE_FIREBASE_EMULATORS=true pnpm exec vite build --mode e2e --outDir dist-e2e --emptyOutDir
node e2e/check-build.mjs dist-e2e present

cp "$app/../firestore.rules" "$here/firestore.rules"
cd "$here"
"${FIREBASE_BIN:-firebase}" emulators:exec --project demo-spectrum-e2e \
  --only auth,firestore "bash ./run-devices.sh $projects"
