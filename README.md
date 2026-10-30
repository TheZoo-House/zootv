# ZooTV

Native Apple TV client for Tunarr, with a program guide, live playback and Top Shelf.

## Build

Requires Xcode 27.1, the tvOS SDK and XcodeGen.

```sh
cp Config/Private.example.xcconfig Config/Private.xcconfig
```

Set your HTTPS Tunarr URL and Apple developer team in the ignored private config.

```sh
xcodegen generate
open ZooTV.xcodeproj
```

## Test

```sh
swift test
xcodebuild -project ZooTV.xcodeproj -scheme ZooTV \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

Live UI tests require your configured server and streams. Stop playback afterward.
