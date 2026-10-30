import Foundation

public enum PlaylistParser {
    public static func parse(_ text: String, baseURL: URL) throws -> [Channel] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
        guard cleaned.hasPrefix("#EXTM3U") else { throw GuideError.invalidPlaylist }
        let regex = try NSRegularExpression(pattern: #"([\w-]+)="([^"]*)""#)
        var pending: (id: String, number: String, name: String)?
        var channels: [Channel] = [], seen = Set<String>()
        for raw in cleaned.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF:") {
                var attributes: [String: String] = [:]
                for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                    if let key = Range(match.range(at: 1), in: line), let value = Range(match.range(at: 2), in: line) {
                        attributes[String(line[key])] = String(line[value])
                    }
                }
                // Find the display-name separator outside quoted attributes.
                var quoted = false, separator: String.Index?
                for i in line.indices {
                    if line[i] == "\"" { quoted.toggle() }
                    if line[i] == "," && !quoted { separator = i; break }
                }
                let title = separator.map { String(line[line.index(after: $0)...]) } ?? ""
                let id = attributes["tvg-id"] ?? attributes["channel-id"] ?? ""
                pending = id.isEmpty ? nil : (id, attributes["tvg-chno"] ?? "", attributes["tvg-name"] ?? title)
            } else if !line.isEmpty && !line.hasPrefix("#"), let item = pending {
                pending = nil
                guard let url = URL(string: line, relativeTo: baseURL)?.absoluteURL,
                      url.scheme == "https", url.host == baseURL.host, url.port == baseURL.port,
                      url.user == nil, url.password == nil, !item.name.isEmpty,
                      seen.insert(item.id).inserted else { continue }
                channels.append(Channel(id: item.id, number: item.number, name: item.name, streamURL: url))
            }
        }
        guard !channels.isEmpty else { throw GuideError.emptyChannels }
        return channels.sorted { $0.number.localizedStandardCompare($1.number) == .orderedAscending }
    }
}
