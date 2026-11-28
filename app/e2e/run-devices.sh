#!/usr/bin/env bash

status=0
for project in "$@"; do
  node seed.ts || exit 1
  E2E_DEVICE="$project" pnpm exec playwright test ${E2E_ARGS:-} --project "$project" || status=1
done
exit $status
