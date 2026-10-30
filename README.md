# ZooTV

A native SwiftUI client for Apple TV that browses a Tunarr program guide and
plays live channels. Tunarr owns scheduling and transcoding. ZooTV does not
require Plex credentials, modify the server, record programs, or include ads,
analytics, subscriptions, or third-party app dependencies.

The guide discovers channels from `/api/channels.m3u` and programs from
`/api/xmltv.xml`. Select a current program to watch live, or a future program
for its details. Playback supports channel switching, subtitles when available,
buffering/error recovery, and browsing the guide over the playing channel.
Top Shelf displays current programs and opens their channels.

## Build and configure

Requires Xcode 27.1, the tvOS SDK, and XcodeGen. The deployment target is tvOS 17.

```sh
cp Config/Private.example.xcconfig Config/Private.xcconfig
```

Edit `Config/Private.xcconfig` with your HTTPS Tunarr base URL and Apple developer
team. This file is ignored by Git. Its URL uses `https:/$()/` so the two slashes
are not interpreted as an xcconfig comment. Both the app and Top Shelf receive
the same installation settings.

```sh
xcodegen generate
open ZooTV.xcodeproj
```

Choose the ZooTV scheme and an Apple TV simulator or paired physical Apple TV.
The destination must be able to reach your Tunarr server. Without a configured
server, the app shows a configuration error instead of contacting a default host.

`project.yml` owns project configuration. The Xcode project and Info.plists are
generated and are not tracked. Regenerate them after changing the specification. Server URLs and developer-team values belong in private settings,
never in source or committed project overrides.

## Remote controls

Select or a direction reveals hidden player controls. Menu/Back hides visible
controls first; pressing it again stops playback and returns to the guide. The
Guide button opens the guide over playback. Selecting a channel returns to
full-screen video. Play/Pause toggles playback.

The app releases playback when leaving the player or backgrounding. Tunarr
controls server-side session cleanup. The guide refreshes while active and
retains its last successful load if a refresh fails.

## Validate

```sh
swift test
xcodebuild -project ZooTV.xcodeproj -scheme ZooTV \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

Core tests are deterministic and do not contact a server. The live integration
tests in `Tests/UITests` require a configured server, matching test channels, and
actual streams. Run them only on your own network and stop playback afterward.
Simulator results do not establish physical Apple TV validation.

For a read-only live feed check on your own network:

```sh
ZOOTV_SERVER_URL=https://tv.example.com swift run zootv-check
```

## Source layout

- `Core/`: models, feed client, parsers, playback state and configuration.
- `App/`: guide, program details, player and remote controls.
- `TopShelf/`: current-program previews and channel deep links.
- `Tests/`: deterministic Core tests and live tvOS integration tests.
- `Tools/`: read-only live feed check.
- `Config/`: shared build settings and a private-settings example.
- `Design/ZooTV.png`: approved icon source; asset catalogs contain its exports.

Playlist streams and artwork must use HTTPS on the configured server's host and
port. XML entity expansion and arbitrary ATS exceptions are not enabled.
