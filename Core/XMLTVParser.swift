import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public final class XMLTVParser: NSObject, XMLParserDelegate {
    private var programmes: [Programme] = []
    private var attributes: [String: String]?
    private var element = "", title = "", summary = "", icon: URL?
    private var sawTV = false
    private let baseURL: URL?
    private init(baseURL: URL?) { self.baseURL = baseURL }
    /// `baseURL` admits `<icon>` artwork only from the same HTTPS host; nil ignores artwork.
    public static func parse(_ data: Data, baseURL: URL? = nil) throws -> [Programme] {
        guard data.count <= 8_000_000 else { throw GuideError.oversizedFeed }
        // Tunarr declares xmltv.dtd. Strip that known declaration without resolving it;
        // reject every other DTD/entity declaration, including internal entity expansion.
        guard let raw = String(data: data, encoding: .utf8) else { throw GuideError.invalidXML }
        let text = raw.replacingOccurrences(of: "<!DOCTYPE tv SYSTEM \"xmltv.dtd\">", with: "")
        guard !text.uppercased().contains("<!DOCTYPE"), !text.uppercased().contains("<!ENTITY") else {
            throw GuideError.invalidXML
        }
        do { return try run(text, baseURL: baseURL) } catch {
            // Tunarr emits stray bare `&` (e.g. role="Deb (& Flo)"). Escape only those, retry once, else keep the original failure.
            guard let fixed = repairAmpersands(text), fixed.utf8.count <= 8_000_000, let programmes = try? run(fixed, baseURL: baseURL) else { throw error }
            return programmes
        }
    }
    private static func run(_ text: String, baseURL: URL?) throws -> [Programme] {
        let delegate = XMLTVParser(baseURL: baseURL), parser = XMLParser(data: Data(text.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.sawTV else { throw GuideError.invalidXML }
        return delegate.programmes.sorted { $0.start < $1.start }
    }
    /// Escapes `&` that is not a predefined or numeric entity reference, skipping comments, CDATA and PIs. Nil when nothing changed.
    static func repairAmpersands(_ text: String) -> String? {
        let b = Array(text.utf8), amp = UInt8(ascii: "&")
        var out = [UInt8](), i = 0, changed = false
        out.reserveCapacity(b.count)
        func starts(_ s: String, at j: Int) -> Bool { b[j...].starts(with: s.utf8) }
        while i < b.count {
            if b[i] == UInt8(ascii: "<"), let end = starts("<!--", at: i) ? "-->" : starts("<![CDATA[", at: i) ? "]]>" : starts("<?", at: i) ? "?>" : nil {
                var j = i + 2
                while j < b.count, !starts(end, at: j) { j += 1 }
                let stop = min(j + end.utf8.count, b.count)
                out.append(contentsOf: b[i..<stop]); i = stop; continue
            }
            if b[i] == amp, !isEntityReference(b, at: i) { out.append(contentsOf: "&amp;".utf8); changed = true }
            else { out.append(b[i]) }
            i += 1
        }
        return changed ? String(decoding: out, as: UTF8.self) : nil
    }
    private static let entities = ["amp;", "lt;", "gt;", "quot;", "apos;"].map { Array($0.utf8) }
    private static let decimal = Set("0123456789".utf8), hex = Set("0123456789abcdefABCDEF".utf8)
    private static func isEntityReference(_ b: [UInt8], at i: Int) -> Bool {
        var j = i + 1
        guard j < b.count else { return false }
        guard b[j] == UInt8(ascii: "#") else { return entities.contains { b[j...].starts(with: $0) } }
        j += 1
        let isHex = j < b.count && b[j] == UInt8(ascii: "x")
        if isHex { j += 1 }
        let start = j
        while j < b.count, (isHex ? hex : decimal).contains(b[j]) { j += 1 }
        return j > start && j < b.count && b[j] == UInt8(ascii: ";")
    }
    public static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyyMMddHHmmss Z", "yyyyMMddHHmmss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
    public func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String]) {
        element = name
        if name == "tv" { sawTV = true }
        if name == "programme" { attributes = attributeDict; title = ""; summary = ""; icon = nil }
        if name == "icon", attributes != nil, icon == nil, let src = attributeDict["src"] { icon = artwork(src) }
    }
    /// Same trust rule as the playlist's stream URLs; Tunarr's generic logo is not a poster.
    private func artwork(_ src: String) -> URL? {
        guard let base = baseURL, let url = URL(string: src, relativeTo: base)?.absoluteURL,
              url.scheme == "https", url.host == base.host, url.port == base.port,
              url.user == nil, url.password == nil, url.path != "/images/tunarr.png" else { return nil }
        return url
    }
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard attributes != nil else { return }
        if element == "title" { title += string }
        if element == "desc" { summary += string }
    }
    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "programme", let a = attributes,
           let id = a["channel"], let s = a["start"].flatMap(Self.date), let e = a["stop"].flatMap(Self.date), e > s {
            programmes.append(Programme(channelID: id, title: title.trimmingCharacters(in: .whitespacesAndNewlines), summary: summary.trimmingCharacters(in: .whitespacesAndNewlines), start: s, end: e, artworkURL: icon))
        }
        if name == "programme" { attributes = nil }
        element = ""
    }
}
