#!/usr/bin/env bash

set -euo pipefail

image="${FLUTTER_DOCKER_IMAGE:-ghcr.io/project516/flutter:3.47.2}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required to run tests without a local Flutter SDK." >&2
  exit 1
fi

common_git_dir=""
git_mount_args=()
if [ -f "$repo_root/.git" ]; then
  common_git_dir="$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir)"
  git_mount_args=(-v "$common_git_dir":"$common_git_dir":ro)
fi

echo "Using Flutter Docker image: $image"
docker pull "$image"

status=0
docker run --rm \
  -v "$repo_root":/repo \
  ${git_mount_args[@]+"${git_mount_args[@]}"} \
  -w /repo \
  -e COMMON_GIT_DIR="$common_git_dir" \
  "$image" \
  bash -lc "tmp_home=\"\$(mktemp -d)\" \
    && owner=\"\$(stat -c '%u:%g' /repo)\" \
    && restore() { rm -rf \"\$tmp_home\"; chown -R \"\$owner\" /repo || true; } \
    && trap restore EXIT \
    && export HOME=\"\$tmp_home\" \
    && export PUB_CACHE=\"\$tmp_home/.pub-cache\" \
    && git config --global --add safe.directory /repo \
    && git config --global --add safe.directory \"\${FLUTTER_ROOT:-/sdks/flutter}\" \
    && if [ -n \"\$COMMON_GIT_DIR\" ]; then git config --global --add safe.directory \"\$COMMON_GIT_DIR\"; fi \
    && tester=\"\$(find \"\${FLUTTER_ROOT:-/sdks/flutter}/bin/cache/artifacts/engine\" -name flutter_tester -type f | head -1)\" \
    && if [ -z \"\$tester\" ] || ! \"\$tester\" --help >/dev/null 2>&1; then \
         echo 'flutter_tester is missing or will not run; re-fetching engine artifacts'; \
         flutter precache --universal --force; \
       fi \
    && flutter pub get \
    && dart format --output=none --set-exit-if-changed . \
    && flutter analyze --fatal-infos \
    && flutter test" || status=$?

if [ "$status" -ge 128 ]; then
  echo "Container exited on a signal ($status); restoring file ownership." >&2
  docker run --rm -v "$repo_root":/repo "$image" \
    bash -lc 'chown -R "$(stat -c "%u:%g" /repo)" /repo' >/dev/null 2>&1 || true
fi

exit "$status"
