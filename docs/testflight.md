# TestFlight

CI tests Core and builds an unsigned generic tvOS Simulator target on pull
requests and main pushes. After successful main checks, publication runs only
when the repository variable `TESTFLIGHT_ENABLED` is `true`.

The workflow selects Xcode 27.1 on GitHub's hosted `xcode-27` runner. It builds the
checked main commit, gets the next build number from App Store Connect, and
uses `MARKETING_VERSION` from `project.yml`. App and Top Shelf versions must match.
An already approved App Store version cannot receive new beta builds; increase
`MARKETING_VERSION` when starting a new version.

## One-time setup

1. Register the app and Top Shelf bundle IDs from `project.yml` in your Apple
   developer team. Create a tvOS App Store distribution profile for each using
   your Apple Distribution certificate.
2. Create a tvOS app record in App Store Connect for the main app's bundle ID.
3. Create an internal TestFlight group, add testers, and enable automatic
   distribution. External testers require separate Beta App Review.
4. Create a GitHub environment named `testflight`, restricted to branch `main`.
   Configure these environment secrets:

   | Secret | Value |
   | --- | --- |
   | `APP_STORE_CONNECT_KEY_ID` | Release API key ID |
   | `APP_STORE_CONNECT_ISSUER_ID` | Matching issuer ID |
   | `APP_STORE_CONNECT_PRIVATE_KEY` | Matching private `.p8` contents |
   | `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` | Base64 distribution certificate/private-key export |
   | `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | P12 import password |
   | `APPLE_DEVELOPMENT_TEAM_ID` | Apple developer-team identifier |
   | `ZOOTV_SERVER_URL` | Private HTTPS Tunarr base URL |

   The `IOS_` names are conventional; an Apple Distribution certificate also
   signs tvOS. The API key must be able to read both profiles, read builds and
   upload builds for this app. Preserve newlines in the `.p8` secret.

## Activate

Set the repository variable `TESTFLIGHT_ENABLED=true`, then push a main commit
or rerun successful main CI. Keep it `false` while preparing or reviewing setup.
Changing it to `false` stops future publication but does not cancel a running
upload.

Publication is serialized from build-number selection through Apple processing.
Newer pending jobs can replace older pending publications; running uploads are
not cancelled. After an interrupted upload, inspect its Apple status before
rerunning. The archive and IPA must contain the app and Top Shelf with matching
versions, server settings and valid signatures. A final API read verifies the
exact build number, marketing version, tvOS platform, and `VALID` state.

Temporary signing material is cleaned from the hosted job. Signed IPA and dSYM
artifacts are retained only for private repositories. Public repositories send
the build directly to TestFlight without publishing these artifacts. A server
address inside an installable app is discoverable by anyone who receives it.

Before calling a release complete, verify internal tester availability and
install on a physical Apple TV. Simulator builds and signing checks do not prove
remote navigation, playback, or Top Shelf behavior on a physical device.
