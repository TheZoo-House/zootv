import XCTest
@testable import ZooTVCore

final class LifecycleTests: XCTestCase {
    func testRetuneRejectsQueuedPlayingFailureAndTimeout() {
        var state = PlaybackSession()
        state.begin(); let old = state.id
        state.begin(); let current = state.id
        XCTAssertFalse(state.receive(.failed, session: old))
        XCTAssertFalse(state.receive(.playing, session: old))
        XCTAssertNil(state.expire(session: old))
        XCTAssertTrue(state.buffering)
        XCTAssertTrue(state.receive(.playing, session: current))
        XCTAssertEqual(state.phase, .playing)
        state.stop()
        XCTAssertFalse(state.receive(.waiting, session: current))
    }
    func testStallRecoversOrExpiresAndPauseDoesNotTimeout() {
        var state = PlaybackSession()
        state.begin(); let id = state.id
        state.receive(.playing, session: id)
        state.receive(.waiting, session: id)
        XCTAssertTrue(state.buffering)
        state.receive(.playing, session: id)
        XCTAssertNil(state.expire(session: id))
        state.receive(.paused, session: id)
        XCTAssertNil(state.expire(session: id))
        state.receive(.waiting, session: id)
        XCTAssertNotNil(state.expire(session: id))
        XCTAssertEqual(state.phase, .failed)
        XCTAssertFalse(state.receive(.playing, session: id))
    }
    func testStallsRetuneTwiceThenFail() {
        var state = PlaybackSession()
        state.begin()
        XCTAssertFalse(state.reconnecting)
        XCTAssertEqual(state.expire(session: state.id), .retry)
        state.begin(automatic: true)
        XCTAssertTrue(state.reconnecting)
        XCTAssertEqual(state.expire(session: state.id), .retry)
        state.begin(automatic: true)
        XCTAssertEqual(state.expire(session: state.id), .fail)
        XCTAssertEqual(state.phase, .failed)
    }
    func testItemFailureSharesBudgetAndPlayingResetsIt() {
        var state = PlaybackSession()
        state.begin()
        XCTAssertEqual(state.fail(session: state.id), .retry)
        state.begin(automatic: true)
        XCTAssertEqual(state.expire(session: state.id), .retry)
        state.begin(automatic: true)
        state.receive(.playing, session: state.id)
        XCTAssertFalse(state.reconnecting)
        state.receive(.waiting, session: state.id)
        XCTAssertEqual(state.fail(session: state.id), .retry)
        state.begin(automatic: true)
        XCTAssertEqual(state.fail(session: state.id), .retry)
        state.begin(automatic: true)
        XCTAssertEqual(state.fail(session: state.id), .fail)
    }
    func testUserTuneResetsBudget() {
        var state = PlaybackSession()
        state.begin()
        XCTAssertEqual(state.expire(session: state.id), .retry)
        state.begin(automatic: true)
        XCTAssertEqual(state.expire(session: state.id), .retry)
        state.begin()
        XCTAssertFalse(state.reconnecting)
        XCTAssertEqual(state.expire(session: state.id), .retry)
    }
    func testRetryRejectsSupersededSessionAndPauseNeverRetries() {
        var state = PlaybackSession()
        state.begin(); let old = state.id
        XCTAssertEqual(state.expire(session: old), .retry)
        state.begin(automatic: true)
        XCTAssertNil(state.expire(session: old))
        XCTAssertNil(state.fail(session: old))
        XCTAssertTrue(state.buffering)
        state.receive(.paused, session: state.id)
        XCTAssertNil(state.expire(session: state.id))
        XCTAssertEqual(state.fail(session: state.id), .fail)
    }
    func testProgrammeTimingLabelsAtBoundaries() {
        let p = Programme(channelID: "a", title: "Test", summary: "", start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(p.timingLabel(at: Date(timeIntervalSince1970: 9)), "COMING UP")
        XCTAssertEqual(p.timingLabel(at: p.start), "ON NOW")
        XCTAssertEqual(p.timingLabel(at: p.end), "AIRED EARLIER")
    }
    func testBoundedFeedAcceptsExactLimit() async throws {
        let bytes = AsyncStream<UInt8> { continuation in
            for byte: UInt8 in [1, 2, 3] { continuation.yield(byte) }
            continuation.finish()
        }
        let data = try await BoundedFeed.read(bytes, limit: 3)
        XCTAssertEqual(Array(data), [1, 2, 3])
    }
    func testBoundedFeedRejectsDeclaredAndActualOversize() async {
        for length: Int64 in [-1, 100] {
            let bytes = AsyncStream<UInt8> { continuation in
                for byte: UInt8 in [1, 2, 3, 4] { continuation.yield(byte) }
                continuation.finish()
            }
            do {
                _ = try await BoundedFeed.read(bytes, declaredLength: length, limit: 3)
                XCTFail("Accepted oversized feed")
            } catch GuideError.oversizedFeed { } catch { XCTFail("Unexpected error: \(error)") }
        }
    }
}
