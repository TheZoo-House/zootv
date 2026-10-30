import XCTest
@testable import ZooTVCore

final class ConfigurationTests: XCTestCase {
    func testAcceptsHTTPSInstallationURL() throws {
        let url = try XCTUnwrap(ZooTVConfiguration.serverURL("https://tv.example.test:8443/tunarr"))
        XCTAssertEqual(try GuideClient(baseURL: url).baseURL, url)
    }

    func testRejectsMissingInsecureAndCredentialBearingConfiguration() {
        for value in [nil, "", "$(ZOOTV_SERVER_URL)", "http://tv.example.test", "https://user:pass@tv.example.test",
                      "https://tv.example.test?token=private", "https://tv.example.test#fragment"] as [String?] {
            XCTAssertNil(ZooTVConfiguration.serverURL(value))
        }
        XCTAssertThrowsError(try GuideClient(baseURL: nil)) {
            XCTAssertEqual($0 as? GuideError, .missingServer)
        }
    }
}
