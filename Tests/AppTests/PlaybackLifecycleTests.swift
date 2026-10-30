import XCTest
import AVFoundation
@testable import ZooTV

final class PlaybackLifecycleTests: XCTestCase {
    @MainActor private func makeModel() -> PlaybackModel {
        // A missing local file exercises the real player lifecycle without starting a live stream.
        let channel = Channel(id: "test", number: "1", name: "Test",
                              streamURL: URL(fileURLWithPath: "/zootv-test-missing.m3u8"))
        let model = PlaybackModel(channel: channel)
        model.tune(channel)
        return model
    }

    @MainActor func testTemporaryInactivityKeepsPlayerItemAndPicture() {
        let model = makeModel()
        defer { model.stop() }
        let item = model.player.currentItem
        let session = model.session.id
        model.hasPicture = true

        model.scenePhaseChanged(.inactive)
        XCTAssertTrue(model.player.currentItem === item, "An overlay must not remove the stream")
        XCTAssertEqual(model.session.id, session)
        XCTAssertTrue(model.hasPicture, "An overlay must not blank the picture")

        model.scenePhaseChanged(.active)
        XCTAssertTrue(model.player.currentItem === item, "Dismissing an overlay must not re-tune")
        XCTAssertEqual(model.session.id, session)
        XCTAssertTrue(model.hasPicture)
    }

    @MainActor func testTemporaryInactivityPreservesViewerPause() {
        let model = makeModel()
        defer { model.stop() }
        model.togglePause()
        let item = model.player.currentItem
        let session = model.session.id

        model.scenePhaseChanged(.inactive)
        model.scenePhaseChanged(.active)

        XCTAssertTrue(model.player.currentItem === item)
        XCTAssertEqual(model.session.id, session)
        XCTAssertEqual(model.session.phase, .paused)
        XCTAssertEqual(model.player.rate, 0)
    }

    @MainActor func testBackgroundReleasesItemAndReturnRetunesOnce() {
        let model = makeModel()
        defer { model.stop() }
        let oldSession = model.session.id
        model.hasPicture = true

        model.scenePhaseChanged(.inactive)
        model.scenePhaseChanged(.background)
        XCTAssertNil(model.player.currentItem)
        XCTAssertEqual(model.session.phase, .stopped)
        XCTAssertNotEqual(model.session.id, oldSession)
        XCTAssertFalse(model.hasPicture)

        model.scenePhaseChanged(.inactive)
        XCTAssertNil(model.player.currentItem, "Returning through inactive must not start a stream")
        model.scenePhaseChanged(.active)
        XCTAssertNotNil(model.player.currentItem)
        XCTAssertEqual(model.session.phase, .waiting)
        let resumedSession = model.session.id
        model.scenePhaseChanged(.active)
        XCTAssertEqual(model.session.id, resumedSession)
    }

    @MainActor func testTemporaryInactivityPreservesPlaybackError() {
        let model = makeModel()
        defer { model.stop() }
        model.stop()
        model.error = "Playback failed"
        let session = model.session.id

        model.scenePhaseChanged(.inactive)
        model.scenePhaseChanged(.active)

        XCTAssertNil(model.player.currentItem)
        XCTAssertEqual(model.session.id, session)
        XCTAssertEqual(model.error, "Playback failed")
    }
}
