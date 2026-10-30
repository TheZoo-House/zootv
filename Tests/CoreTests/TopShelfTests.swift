import XCTest
@testable import ZooTVCore

final class TopShelfTests: XCTestCase {
    let base = URL(string: "https://example.test")!
    func programme(icon: String?) throws -> Programme {
        let tag = icon.map { "<icon src=\"\($0)\"/>" } ?? ""
        let xml = "<tv><programme channel=\"a\" start=\"20260926120000 +0000\" stop=\"20260926130000 +0000\"><title>Show</title>\(tag)</programme></tv>"
        return try XCTUnwrap(XMLTVParser.parse(Data(xml.utf8), baseURL: base).first)
    }
    func testPosterIconParsed() throws {
        XCTAssertEqual(try programme(icon: "https://example.test/api/programs/1/artwork/poster").artworkURL?.absoluteString,
                       "https://example.test/api/programs/1/artwork/poster")
    }
    func testGenericTunarrIconRejected() throws {
        XCTAssertNil(try programme(icon: "https://example.test/images/tunarr.png").artworkURL)
    }
    func testOffHostOrInsecureIconRejected() throws {
        XCTAssertNil(try programme(icon: "http://example.test/api/programs/1/artwork/poster").artworkURL)
        XCTAssertNil(try programme(icon: "https://evil.test/api/programs/1/artwork/poster").artworkURL)
        XCTAssertNil(try programme(icon: "https://user:pw@example.test/api/programs/1/artwork/poster").artworkURL)
        XCTAssertNil(try programme(icon: "https://example.test:8443/api/programs/1/artwork/poster").artworkURL)
    }
    func testMissingIconIsNil() throws {
        XCTAssertNil(try programme(icon: nil).artworkURL)
    }
    func testDeepLinkRoundTrip() {
        XCTAssertEqual(DeepLink.channelID(from: DeepLink.play(channel: "C100.145.tunarr.com")), "C100.145.tunarr.com")
        XCTAssertEqual(DeepLink.channelID(from: URL(string: "zootv://play?channel=a%20b")!), "a b")
    }
    func testDeepLinkRejectsWrongSchemeHostOrMissingChannel() {
        for bad in ["https://play?channel=x", "zootv://guide?channel=x", "zootv://play", "zootv://play?channel="] {
            XCTAssertNil(DeepLink.channelID(from: URL(string: bad)!), bad)
        }
    }
}
