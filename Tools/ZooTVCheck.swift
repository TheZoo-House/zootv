import Foundation
import ZooTVCore

@main struct Check {
    static func main() async throws {
        let guide = try await GuideClient().load()
        print("Live guide: \(guide.channels.count) channels, \(guide.programmes.count) programmes")
        for channel in guide.channels {
            print("\(channel.number) \(channel.name): \(guide.now(on: channel, at: Date())?.title ?? "No current listing")")
        }
        guard !guide.channels.isEmpty, !guide.programmes.isEmpty else { throw GuideError.emptyChannels }
    }
}
