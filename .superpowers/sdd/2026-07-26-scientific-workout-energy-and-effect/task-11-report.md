# Task 11 Report: Restore App Icon and Integrate Sources in Xcode

## Status

Completed from base `6b2e85d`.

## Implementation

- Restored `AppIcon-1024.png` from the prescribed worktree and recreated the matching asset-catalog JSON.
- Preserved Task 9's existing production-engine project entries (`C...48` through `C...4A` / `B...45` through `B...47`) and used the next unused IDs for the three tests and asset catalog (`C...4B` through `C...4E` / `B...48` through `B...4B`).
- Added the test files to the `FitTuneTests` group and Sources phase; added `Assets.xcassets` to FitTune Resources and its Resources phase.
- Set FitTune Debug and Release to use `AppIcon`, and bumped the FitTune, FitTuneWatch, and FitTuneWidgets targets to `1.2.0 (13)`.

## Verification

```text
test -f FitTune/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
# pre-change exit: 1

sips -g pixelWidth -g pixelHeight -g hasAlpha -g space FitTune/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
pixelWidth: 1024
pixelHeight: 1024
hasAlpha: no
space: RGB

shasum -a 256 FitTune/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
7c9f22ee4f28402e1fa6fe7c103b52be6febb70ff763c084f4ccc020f99b5fc7

plutil -lint FitTune.xcodeproj/project.pbxproj
FitTune.xcodeproj/project.pbxproj: OK

PBX object-definition duplicate check
# no output

CURRENT_PROJECT_VERSION = 13
# 6 occurrences
MARKETING_VERSION = 1.2.0
# 6 occurrences
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon
# 2 occurrences

xcodebuild -project FitTune.xcodeproj -scheme FitTune -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
# exit 0

xcodebuild -project FitTune.xcodeproj -scheme FitTune -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
# exit 0

Release FitTune.app Info.plist
CFBundleShortVersionString: 1.2.0
CFBundleVersion: 13

git diff --check
# exit 0
```

## Concerns

None.
