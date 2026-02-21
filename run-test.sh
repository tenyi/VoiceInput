#!/bin/sh
xcodebuild test \
  -project VoiceInput.xcodeproj \
  -scheme VoiceInput \
  -destination 'platform=macOS'
#!/bin/sh

rm -rf TestResults.xcresult && xcodebuild test -project VoiceInput.xcodeproj -scheme VoiceInput -destination 'platform=macOS' -enableCodeCoverage YES -resultBundlePath TestResults.xcresult

xcrun xccov view --report TestResults.xcresult

