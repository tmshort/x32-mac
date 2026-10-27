#!/bin/bash
# Stop hook: build once at the end of a turn if Swift files changed.
# On failure, print errors to stderr and exit 2 so Claude sees and fixes them.
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

input=$(cat)
# Avoid looping: if we already blocked this stop once, let it finish.
[ "$(echo "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

git status --porcelain | grep -q '\.swift$' || exit 0

out=$(xcodebuild -project x32-mac.xcodeproj -scheme x32-mac -destination 'platform=macOS' build 2>&1)
if echo "$out" | grep -q 'BUILD FAILED'; then
  echo "$out" | xcbeautify --quieter | tail -30 >&2
  exit 2
fi
exit 0
