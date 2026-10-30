import Foundation

/// `zootv://play?channel=<id>` opens the app straight into a channel's live playback.
public enum DeepLink {
    public static func play(channel id: String) -> URL {
        var parts = URLComponents()
        parts.scheme = "zootv"; parts.host = "play"
        parts.queryItems = [URLQueryItem(name: "channel", value: id)]
        return parts.url!
    }
    public static func channelID(from url: URL) -> String? {
        guard url.scheme == "zootv", url.host == "play",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "channel" })?.value,
              !id.isEmpty else { return nil }
        return id
    }
}
