# ZooTV

Native Apple TV client for Tunarr, with a program guide, live playback and Top Shelf.

## Seasonal icon artwork

The active icon source is [Design/ZooTV.png](Design/ZooTV.png), the approved flat
Christmas illustration. Its original is retained in
[Design/concepts/zootv-christmas-flat.png](Design/concepts/zootv-christmas-flat.png).
The previous Halloween artwork is preserved unchanged in
[Design/concepts/zootv-teal-halloween.png](Design/concepts/zootv-teal-halloween.png).

Home Screen artwork at 400×240 and 800×480, and App Store artwork at 1280×768,
are exported from the active source into `App/Assets.xcassets/AppIcon.brandassets`.
The existing opaque backing layers and Top Shelf images are retained.

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
