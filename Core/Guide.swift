import Foundation

public struct Channel: Identifiable, Hashable, Sendable {
    public let id: String
    public let number: String
    public let name: String
    public let streamURL: URL
    public init(id: String, number: String, name: String, streamURL: URL) {
        self.id = id; self.number = number; self.name = name; self.streamURL = streamURL
    }
}

public struct Programme: Identifiable, Hashable, Sendable {
    public var id: String { "\(channelID)|\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)" }
    public let channelID: String
    public let title: String
    public let summary: String
    public let start: Date
    public let end: Date
    public let artworkURL: URL?
    public init(channelID: String, title: String, summary: String, start: Date, end: Date, artworkURL: URL? = nil) {
        self.channelID = channelID; self.title = title; self.summary = summary
        self.start = start; self.end = end; self.artworkURL = artworkURL
    }
    public func timingLabel(at date: Date) -> String {
        if date >= end { return "AIRED EARLIER" }
        return date < start ? "COMING UP" : "ON NOW"
    }
    public func isLive(at date: Date) -> Bool { start <= date && date < end }
}

public struct Guide: Sendable {
    public let channels: [Channel]
    public let programmes: [Programme]
    public init(channels: [Channel], programmes: [Programme]) {
        self.channels = channels; self.programmes = programmes
    }
    public func schedule(for channel: Channel) -> [Programme] {
        programmes.filter { $0.channelID == channel.id }.sorted { $0.start < $1.start }
    }
    public func now(on channel: Channel, at date: Date) -> Programme? {
        schedule(for: channel).first { $0.isLive(at: date) }
    }
    public func visible(on channel: Channel, from start: Date, to end: Date) -> [Programme] {
        schedule(for: channel).filter { $0.end > start && $0.start < end }
    }
}

public enum GuideError: LocalizedError {
    case invalidPlaylist, invalidXML, emptyChannels, invalidResponse, oversizedFeed, missingServer
    public var errorDescription: String? {
        switch self {
        case .invalidPlaylist: return "The channel list is not a valid M3U playlist."
        case .invalidXML: return "The program guide could not be read."
        case .emptyChannels: return "ZooTV has no available channels yet."
        case .invalidResponse: return "The ZooTV server did not return a successful response."
        case .oversizedFeed: return "The guide exceeds the supported feed size."
        case .missingServer: return "No TV server is configured for this build."
        }
    }
}

public enum ZooTVConfiguration {
    public static var server: URL? {
        serverURL(ProcessInfo.processInfo.environment["ZOOTV_SERVER_URL"]
                  ?? Bundle.main.object(forInfoDictionaryKey: "ZooTVServerURL") as? String)
    }

    public static func serverURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        return url
    }
}
