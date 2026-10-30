import XCTest

final class ZooTVUITests: XCTestCase {
    @MainActor private func select(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<25 {
            if element.hasFocus { XCUIRemote.shared.press(.select); return }
            let focused = app.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
            guard focused.exists else { XCUIRemote.shared.press(.down); continue }
            print("FOCUS", focused.identifier, focused.label, focused.frame, "TARGET", element.identifier, element.frame)
            let from = focused.frame, to = element.frame
            if abs(to.midY - from.midY) > max(30, min(from.height, to.height) / 2) {
                XCUIRemote.shared.press(to.midY > from.midY ? .down : .up)
            } else {
                XCUIRemote.shared.press(to.midX > from.midX ? .right : .left)
            }
        }
        XCTFail("Could not focus \(element.identifier)")
    }
    @MainActor func testLiveGuideAndPlaybackNavigation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let cinema = app.buttons["channel-101"]
        XCTAssertTrue(cinema.waitForExistence(timeout: 30), "Live channel list must load")
        let guide = XCTAttachment(screenshot: app.screenshot())
        guide.name = "ZooTV live guide"; guide.lifetime = .keepAlways; add(guide)
        let future = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'future-'")).firstMatch
        XCTAssertTrue(future.waitForExistence(timeout: 5))
        select(future, in: app)
        XCTAssertTrue(app.staticTexts["COMING UP"].waitForExistence(timeout: 5))
        select(app.buttons["Back to guide"], in: app)
        select(cinema, in: app)
        XCTAssertTrue(app.buttons["nextChannel"].waitForExistence(timeout: 10))
        let video = app.otherElements["liveVideo"]
        let playing = NSPredicate(format: "value == 'playing-101'")
        expectation(for: playing, evaluatedWith: video)
        waitForExpectations(timeout: 35)
        let playback = XCTAttachment(screenshot: app.screenshot())
        playback.name = "ZooTV live playback"; playback.lifetime = .keepAlways; add(playback)
        XCTAssertTrue(app.buttons["showControls"].waitForExistence(timeout: 12), "Controls must auto-hide")
        let hidden = XCTAttachment(screenshot: app.screenshot())
        hidden.name = "ZooTV playback, controls hidden"; hidden.lifetime = .keepAlways; add(hidden)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["nextChannel"].waitForExistence(timeout: 5))
        select(app.buttons["nextChannel"], in: app)
        XCTAssertTrue(app.staticTexts["102"].waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == 'playing-102'"), evaluatedWith: video)
        waitForExpectations(timeout: 35)
        if app.buttons["showControls"].exists { XCUIRemote.shared.press(.select) }
        XCTAssertTrue(app.buttons["nextChannel"].waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["showControls"].waitForExistence(timeout: 3), "Back must hide visible controls first")
        XCUIRemote.shared.press(.select)
        select(app.buttons["backToGuide"], in: app)
        XCTAssertTrue(cinema.waitForExistence(timeout: 10), "Guide button must open the guide over the show")
        XCTAssertEqual(video.value as? String, "playing-102", "The show must keep playing behind the guide")
        select(cinema, in: app)
        expectation(for: NSPredicate(format: "value == 'playing-101'"), evaluatedWith: video)
        waitForExpectations(timeout: 35)
        XCTAssertFalse(cinema.exists, "Picking a channel must return to full-screen video")
        if !app.buttons["showControls"].exists { XCUIRemote.shared.press(.menu) }
        XCTAssertTrue(app.buttons["showControls"].waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(video.waitForNonExistence(timeout: 10), "Back must stop the show")
        XCTAssertTrue(cinema.waitForExistence(timeout: 10))
    }
    @MainActor private func stopPlayback(_ app: XCUIApplication) {
        let video = app.otherElements["liveVideo"]
        if !app.buttons["showControls"].exists { XCUIRemote.shared.press(.menu) }
        XCTAssertTrue(app.buttons["showControls"].waitForExistence(timeout: 12))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(video.waitForNonExistence(timeout: 10), "Back must stop the show")
    }
    /// Top Shelf items open `zootv://play?channel=<tvg-id>`; channel 102 is Tunarr's C102.147.tunarr.com.
    @MainActor func testDeepLinkOpensChannelPlayback() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.terminate()
        app.open(URL(string: "zootv://play?channel=C102.147.tunarr.com")!)
        sleep(3)
        if app.state != .runningForeground { XCUIRemote.shared.press(.select) }  // The system's "Open in ZooTV?" prompt.
        let video = app.otherElements["liveVideo"]
        expectation(for: NSPredicate(format: "value == 'playing-102'"), evaluatedWith: video)
        waitForExpectations(timeout: 45)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Deep link into 102"; shot.lifetime = .keepAlways; add(shot)
        stopPlayback(app)
    }
    /// Needs ZooTV second in the Home Screen's top row, as on a fresh simulator (Settings, ZooTV).
    @MainActor func testTopShelfPosterOpensChannel() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()  // Refreshing the guide asks tvOS to reload the Top Shelf.
        XCTAssertTrue(app.buttons["channel-101"].waitForExistence(timeout: 30))
        XCUIRemote.shared.press(.home)
        sleep(2)
        for _ in 0..<4 { XCUIRemote.shared.press(.left) }
        XCUIRemote.shared.press(.right)
        sleep(10)
        let shelf = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shelf.name = "Top Shelf On now"; shelf.lifetime = .keepAlways; add(shelf)
        XCUIRemote.shared.press(.up)
        sleep(2)
        let focused = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); focused.name = "Top Shelf poster focused"; focused.lifetime = .keepAlways; add(focused)
        XCUIRemote.shared.press(.select)
        let video = app.otherElements["liveVideo"]
        expectation(for: NSPredicate(format: "value BEGINSWITH 'playing-'"), evaluatedWith: video)
        waitForExpectations(timeout: 45)
        let playing = XCTAttachment(screenshot: app.screenshot()); playing.name = "Opened from Top Shelf"; playing.lifetime = .keepAlways; add(playing)
        stopPlayback(app)
    }
    /// Needs channels 107 and 108 to carry a WebVTT rendition and 100 to carry none.
    @MainActor func testLiveSubtitlesToggleAndPersist() throws {
        continueAfterFailure = false
        var app = XCUIApplication()
        let video = app.otherElements["liveVideo"]
        let subtitles = app.buttons["subtitles"]
        func play(_ number: String) {
            let channel = app.buttons["channel-\(number)"]
            XCTAssertTrue(channel.waitForExistence(timeout: 30))
            select(channel, in: app)
            expectation(for: NSPredicate(format: "value == 'playing-\(number)'"), evaluatedWith: video)
            waitForExpectations(timeout: 35)
            if app.buttons["showControls"].exists { XCUIRemote.shared.press(.select) }
        }
        func waitEnabled() {
            expectation(for: NSPredicate(format: "exists == true AND isEnabled == true"), evaluatedWith: subtitles)
            waitForExpectations(timeout: 15)
        }
        func shot(_ name: String) {
            XCTAssertTrue(app.buttons["showControls"].waitForExistence(timeout: 12))
            // Several frames, so at least one is likely to land on a spoken line.
            for frame in 1...4 {
                sleep(4)
                let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "\(name) \(frame)"; shot.lifetime = .keepAlways; add(shot)
            }
        }
        app.launch()
        play("107")
        XCTAssertTrue(subtitles.exists, "The Subtitles control must be in the row from the start")
        XCTAssertTrue(app.staticTexts["Guide"].waitForExistence(timeout: 3), "Resting focus must show the control's name")
        let tip = XCTAttachment(screenshot: app.screenshot()); tip.name = "Icon controls with tooltip"; tip.lifetime = .keepAlways; add(tip)
        waitEnabled()
        if subtitles.label == "Subtitles On" { select(subtitles, in: app) }
        XCTAssertEqual(subtitles.label, "Subtitles Off")
        shot("Subtitles off, channel 107")
        XCUIRemote.shared.press(.select)
        select(subtitles, in: app)
        XCTAssertEqual(subtitles.label, "Subtitles On")
        shot("Subtitles on, channel 107")
        app.terminate()
        app = XCUIApplication(); app.launch()
        play("107")
        waitEnabled()
        XCTAssertEqual(subtitles.label, "Subtitles On", "The choice must survive relaunch")
        select(app.buttons["nextChannel"], in: app)
        expectation(for: NSPredicate(format: "value == 'playing-108'"), evaluatedWith: video)
        waitForExpectations(timeout: 35)
        if app.buttons["showControls"].exists { XCUIRemote.shared.press(.select) }
        waitEnabled()
        XCTAssertEqual(subtitles.label, "Subtitles On", "The choice must survive channel changes")
        select(subtitles, in: app)
        XCTAssertEqual(subtitles.label, "Subtitles Off")
        select(app.buttons["backToGuide"], in: app)
        play("100")
        XCTAssertTrue(app.buttons["nextChannel"].exists)
        sleep(5)  // Long enough for the track list to load if there were one.
        if app.buttons["showControls"].exists { XCUIRemote.shared.press(.select) }
        XCTAssertTrue(subtitles.waitForExistence(timeout: 3))
        XCTAssertFalse(subtitles.isEnabled, "A channel without subtitles must disable the control")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["showControls"].waitForExistence(timeout: 3), "Back must hide visible controls first")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(video.waitForNonExistence(timeout: 10), "Back must stop the show")
    }
}
