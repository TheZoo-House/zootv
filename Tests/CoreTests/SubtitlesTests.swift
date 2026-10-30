import XCTest
@testable import ZooTVCore

final class SubtitlesTests: XCTestCase {
    func testPicksPreferredLanguageElseFirstOption() {
        XCTAssertEqual(Subtitles.option(languages: ["spa", "eng"], preferred: ["en-US"], enabled: true), 1)
        XCTAssertEqual(Subtitles.option(languages: ["eng", "spa", nil], preferred: ["fr-CA", "es", "en"], enabled: true), 1)
        XCTAssertEqual(Subtitles.option(languages: [nil, "deu"], preferred: ["ja"], enabled: true), 0)
    }
    func testNothingWhenDisabledOrNoOptions() {
        XCTAssertNil(Subtitles.option(languages: [], preferred: ["en"], enabled: true))
        XCTAssertNil(Subtitles.option(languages: ["eng"], preferred: ["en"], enabled: false))
    }
}
