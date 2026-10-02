## Summary

<!-- What does this PR change and why? Link any related issues with "Closes #123". -->

## Test plan

<!-- How did you verify this works? Check what applies. -->

- [ ] `xcodegen generate && xcodebuild -project Plainfile.xcodeproj -scheme Plainfile -destination 'platform=macOS' build` succeeds
- [ ] `xcodebuild -project Plainfile.xcodeproj -scheme Plainfile -destination 'platform=macOS' test` passes
- [ ] Tested manually on macOS (note version: ____)
- [ ] No new compiler warnings
- [ ] If user-facing, the README features list and CHANGELOG are updated

## Notes for reviewer

<!-- Anything subtle a reviewer should know? Tradeoffs, follow-ups, screenshots of UI changes. -->
