#!/usr/bin/env bash
set -euo pipefail

# Always run from the repo root (so pubspec.yaml is found)
cd "$(dirname "$0")/.."

echo "PWD: $(pwd)"
echo "Files in repo root:"
ls -la

echo "Installing Flutter..."
git clone https://github.com/flutter/flutter.git --depth 1 -b stable /opt/build/flutter

export PATH="/opt/build/flutter/bin:/opt/build/flutter/bin/cache/dart-sdk/bin:$PATH"

flutter --version

echo "Enable web + precache..."
flutter config --enable-web
flutter precache --web

echo "Get packages..."
flutter pub get

echo "Build web..."
flutter build web --release --base-href /

echo "Show build output..."
ls -la build
ls -la build/web

# Hard fail if build/web doesn't exist (so we see it in logs)
test -d build/web
