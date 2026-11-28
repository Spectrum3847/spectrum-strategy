#!/usr/bin/env bash

set -euo pipefail
: "${PLAYWRIGHT_BROWSERS_PATH:?set PLAYWRIGHT_BROWSERS_PATH to the Playwright browsers folder}"
dest=$(ls -d "$PLAYWRIGHT_BROWSERS_PATH"/webkit-*/minibrowser-wpe | head -1)/sys/lib
pool=http://archive.ubuntu.com/ubuntu/pool/main
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

jpeg=$(curl -s "$pool/libj/libjpeg-turbo/" | grep -oE 'libjpeg-turbo8_2\.1[^"]*amd64\.deb' | sort -u | tail -1)
curl -sfo "$work/icu.deb" "$pool/i/icu/libicu74_74.2-1ubuntu3.1_amd64.deb"
curl -sfo "$work/jpeg.deb" "$pool/libj/libjpeg-turbo/$jpeg"

for deb in icu jpeg; do
  mkdir -p "$work/$deb"
  (cd "$work/$deb" && ar x "../$deb.deb")
  tar -xf "$work/$deb"/data.tar.* -C "$work/$deb"
done

mkdir -p "$dest"
cp -a "$work"/icu/usr/lib/x86_64-linux-gnu/libicu*.so.74* "$dest"/
cp -a "$work"/jpeg/usr/lib/x86_64-linux-gnu/libjpeg.so.8* "$dest"/
echo "WebKit libraries copied to $dest"
