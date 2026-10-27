---
description: Run the x32-mac unit tests and summarize failures
allowed-tools: Bash(xcodebuild:*), Bash(xcbeautify:*)
---

Run the unit tests (not the UI tests):

`xcodebuild -project x32-mac.xcodeproj -scheme x32-mac -destination 'platform=macOS' -only-testing:x32-macTests test 2>&1 | xcbeautify`

Report the pass/fail count. For any failure, show the test name and assertion message, find the cause in the source, and propose a fix. If `$ARGUMENTS` is given, pass it as an additional `-only-testing:x32-macTests/$ARGUMENTS` filter.
