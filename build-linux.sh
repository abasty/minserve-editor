#!/usr/bin/env bash
#
# Build the Linux desktop app and pack it as build/minserve-editor-linux-x64.tar.gz
# (the whole "bundle" folder: executable, data/ and lib/ must stay together).
# Nothing is published or sent anywhere.
#
# Usage: ./build-linux.sh

set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

flutter test
flutter build linux --release

BUNDLE="build/linux/x64/release/bundle"
ARCHIVE="build/minserve-editor-linux-x64.tar.gz"
tar -czf "$ARCHIVE" -C "$BUNDLE" --transform 's,^\.,minserve-editor,' .
echo "==> $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"
