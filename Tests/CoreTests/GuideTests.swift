import XCTest
@testable import ZooTVCore

final class GuideTests: XCTestCase {
    let base = URL(string: "https://example.test")!
    func testPlaylistAttributesQuotedCommaAndOrdering() throws {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="b" tvg-chno="10" tvg-name="Comedy, etc",Fallback
        https://example.test/b?streamMode=hls
        #EXTINF:-1 tvg-id="a" tvg-chno="2",Cinema
        /a
        """
        let channels = try PlaylistParser.parse(text, baseURL: base)
        XCTAssertEqual(channels.map(\.number), ["2", "10"])
        XCTAssertEqual(channels[1].name, "Comedy, etc")
        XCTAssertEqual(channels[0].streamURL.absoluteString, "https://example.test/a")
    }
    func testUnsafeURLsAreRejectedAndDuplicatesCollapsed() throws {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="bad",Bad
        http://example.test/plaintext
        #EXTINF:-1 tvg-id="outside",Outside
        https://evil.test/movie
        #EXTINF:-1 tvg-id="ok",Good
        https://example.test/live
        #EXTINF:-1 tvg-id="ok",Duplicate
        https://example.test/live
        """
        XCTAssertEqual(try PlaylistParser.parse(text, baseURL: base).count, 1)
    }
    func testPlaylistMalformedAndEmpty() {
        XCTAssertThrowsError(try PlaylistParser.parse("garbage", baseURL: base))
        XCTAssertThrowsError(try PlaylistParser.parse("#EXTM3U", baseURL: base))
    }
    func testXMLTVUTCAndOffsetAgree() {
        XCTAssertEqual(XMLTVParser.date("20260926120000 -0400"), XMLTVParser.date("20260926160000 +0000"))
        XCTAssertNil(XMLTVParser.date("not a date"))
    }
    func testXMLTextEntitiesAndInvalidDurations() throws {
        let xml = """
        <tv><programme channel="a" start="20260926120000 +0000" stop="20260926130000 +0000"><title>Tom &amp; Jerry</title><desc>One &lt; two</desc></programme><programme channel="a" start="20260926130000 +0000" stop="20260926120000 +0000"><title>Invalid</title></programme></tv>
        """
        let p = try XMLTVParser.parse(Data(xml.utf8))
        XCTAssertEqual(p.count, 1); XCTAssertEqual(p[0].title, "Tom & Jerry"); XCTAssertEqual(p[0].summary, "One < two")
    }
    // Live Tunarr feed: one bare `&` inside an actor role attribute breaks the whole guide.
    let strayAmpersandXML = """
    <!DOCTYPE tv SYSTEM "xmltv.dtd"><?xmltv a & b?><tv><!-- Tom & Jerry --><programme channel="a" start="20260926120000 +0000" stop="20260926130000 +0000"><title>Tom & Jerry</title><sub-title><![CDATA[F & G]]></sub-title><desc>A &amp; B &lt; C &#38; D &#x26; E &amp</desc><credits><actor role="Deb (& Flo) (voice)">Someone</actor></credits></programme></tv>
    """
    func testXMLBareAmpersandsAreRepaired() throws {
        let p = try XMLTVParser.parse(Data(strayAmpersandXML.utf8))
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].title, "Tom & Jerry")
        XCTAssertEqual(p[0].summary, "A & B < C & D & E &amp")
    }
    func testRepairLeavesValidXMLAndSkipRegionsUntouched() {
        let valid = "<?pi & ?><tv><!-- a & b --><title>A &amp; &lt; &gt; &quot; &apos; &#38; &#x26;</title><![CDATA[c & d]]></tv>"
        XCTAssertNil(XMLTVParser.repairAmpersands(valid))
        let fixed = XMLTVParser.repairAmpersands(strayAmpersandXML) ?? ""
        for kept in ["<?xmltv a & b?>", "<!-- Tom & Jerry -->", "<![CDATA[F & G]]>", "&amp; B &lt; C &#38; D &#x26; E &amp;amp</desc>", #"role="Deb (&amp; Flo) (voice)""#, "Tom &amp; Jerry</title>"] {
            XCTAssertTrue(fixed.contains(kept), kept)
        }
        XCTAssertEqual(XMLTVParser.repairAmpersands("<tv>&#;&#xZZ;&"), "<tv>&amp;#;&amp;#xZZ;&amp;")
    }
    func testOversizedAfterRepairStillFails() {
        func feed(padding: Int) -> Data {
            Data(("<tv><programme channel=\"a\" start=\"20260926120000 +0000\" stop=\"20260926130000 +0000\"><title>" + String(repeating: "&", count: 500_000) + String(repeating: " ", count: padding) + "</title></programme></tv>").utf8)
        }
        XCTAssertEqual(try XMLTVParser.parse(feed(padding: 0)).count, 1)
        XCTAssertThrowsError(try XMLTVParser.parse(feed(padding: 7_400_000)))
    }
    func testGuideAssemblesAfterRepair() throws {
        let m3u = "#EXTM3U\n#EXTINF:-1 tvg-id=\"a\" tvg-chno=\"1\",Cartoons\nhttps://example.test/a\n"
        let guide = try GuideClient(baseURL: base).guide(playlist: Data(m3u.utf8), xml: Data(strayAmpersandXML.utf8))
        XCTAssertEqual(guide.channels.map(\.name), ["Cartoons"])
        XCTAssertEqual(guide.programmes.map(\.title), ["Tom & Jerry"])
    }
    func testTunarrStandardDTDIsNotResolved() throws {
        let xml = #"<!DOCTYPE tv SYSTEM "xmltv.dtd"><tv/>"#
        XCTAssertEqual(try XMLTVParser.parse(Data(xml.utf8)).count, 0)
    }
    func testXMLRejectsMalformedAndDTD() {
        for xml in ["<tv><programme></tv>", "<!DOCTYPE tv [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><tv/>", "<html/>",
                    "<tv><programme>a & b</tv>", "<!DOCTYPE tv [<!ENTITY x 'y'>]><tv>a & b</tv>", "<tv><!-- a & b <title>c & d</title></tv>", "<tv/>&", "<tv>&#0;</tv>"] {
            XCTAssertThrowsError(try XMLTVParser.parse(Data(xml.utf8)), xml) { XCTAssertEqual($0 as? GuideError, .invalidXML) }
        }
        XCTAssertThrowsError(try XMLTVParser.parse(Data([0xFF, 0xFE, 0x3C, 0x74, 0x76, 0x2F, 0x3E])))
    }
    func testNowBoundaryAndClipping() {
        let channel = Channel(id: "a", number: "1", name: "Test", streamURL: base)
        let start = Date(timeIntervalSince1970: 0)
        let a = Programme(channelID: "a", title: "A", summary: "", start: start, end: start.addingTimeInterval(60))
        let b = Programme(channelID: "a", title: "B", summary: "", start: a.end, end: a.end.addingTimeInterval(60))
        let guide = Guide(channels: [channel], programmes: [b,a])
        XCTAssertEqual(guide.now(on: channel, at: a.end)?.title, "B")
        XCTAssertEqual(guide.visible(on: channel, from: a.end, to: b.end).count, 1)
    }
    func testUnknownChannelHasNoSchedule() {
        let channel = Channel(id: "missing", number: "1", name: "Test", streamURL: base)
        XCTAssertNil(Guide(channels: [channel], programmes: []).now(on: channel, at: Date()))
    }
}
