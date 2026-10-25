#!/usr/bin/env bash
# Builds the web preview (docs/PREVIEW.md) into build/web: same app, an
# in-memory unencrypted database, no server. For the owner's tests only.
set -euo pipefail
cd "$(dirname "$0")/.."

# sqlite3.wasm matching the sqlite3 package (pubspec.lock), pinned by hash.
SQLITE_TAG=sqlite3-3.7.0
SQLITE_SHA=fbcd2e8214f9231ea961e1b7706a22dd1194cfbfe6f26f13841b5aa7a0be1a1f

flutter build web --release -t lib/preview/main_preview.dart \
  --no-web-resources-cdn --no-tree-shake-icons
out=build/web
curl -fsSL -o "$out/sqlite3.wasm" \
  "https://github.com/simolus3/sqlite3.dart/releases/download/$SQLITE_TAG/sqlite3.wasm"
echo "$SQLITE_SHA  $out/sqlite3.wasm" | sha256sum -c -

# Only the CanvasKit "full" engine is loaded (web/flutter_bootstrap.js).
rm -rf "$out/canvaskit/chromium" "$out/canvaskit/webparagraph"
rm -f "$out"/canvaskit/skwasm* "$out"/canvaskit/wimp* "$out"/canvaskit/*.symbols
du -sh "$out"
