import Foundation

public struct GuideClient: Sendable {
    public let baseURL: URL
    public init(baseURL: URL? = ZooTVConfiguration.server) throws {
        guard let baseURL = ZooTVConfiguration.serverURL(baseURL?.absoluteString) else { throw GuideError.missingServer }
        self.baseURL = baseURL
    }
    public func load() async throws -> Guide {
        async let playlist = fetch("api/channels.m3u")
        async let xml = fetch("api/xmltv.xml")
        let (playlistData, xmlData) = try await (playlist, xml)
        return try guide(playlist: playlistData, xml: xmlData)
    }
    func guide(playlist playlistData: Data, xml xmlData: Data) throws -> Guide {
        guard let text = String(data: playlistData, encoding: .utf8) else { throw GuideError.invalidPlaylist }
        let channels = try PlaylistParser.parse(text, baseURL: baseURL)
        let ids = Set(channels.map(\.id))
        let programmes = try XMLTVParser.parse(xmlData, baseURL: baseURL).filter { ids.contains($0.channelID) }
        return Guide(channels: channels, programmes: programmes)
    }
    private func fetch(_ path: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https", http.url?.host == baseURL.host,
              http.url?.port == baseURL.port else { throw GuideError.invalidResponse }
        return try await BoundedFeed.read(bytes, declaredLength: response.expectedContentLength)
    }
}
