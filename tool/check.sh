#!/usr/bin/env bash
# Everything a contributor runs before a commit: format, analysis, content
# pack and the full test suite. Exit 1 on any failure; logs in build/check/.
cd "$(dirname "$0")/.." || exit 1
out=build/check
mkdir -p "$out"
dart format --output=none --set-exit-if-changed $(git ls-files '*.dart') \
  $(git ls-files --others --exclude-standard '*.dart') > "$out/format.txt" 2>&1; f=$?
flutter analyze > "$out/analyze.txt" 2>&1; a=$?
dart run tool/content_build.dart --check > "$out/content.txt" 2>&1; c=$?
flutter test > "$out/test.txt" 2>&1; t=$?
echo "format=$f analyze=$a content=$c test=$t | $(tail -1 "$out/test.txt")"
grep "•" "$out/analyze.txt" | head -5
[ $f -eq 0 ] && [ $a -eq 0 ] && [ $c -eq 0 ] && [ $t -eq 0 ]
