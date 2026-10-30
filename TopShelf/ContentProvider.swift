@preconcurrency import TVServices

/// "On now" row: one poster per channel, opening ZooTV straight into that channel.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let guide = try? await GuideClient().load() else { return nil }
        let now = Date(), placeholder = Bundle.main.url(forResource: "Poster", withExtension: "png")
        let section = TVTopShelfItemCollection<TVTopShelfSectionedItem>(items: guide.channels.map { channel in
            let programme = guide.now(on: channel, at: now)
            let item = TVTopShelfSectionedItem(identifier: channel.id)
            item.title = "\(channel.number) · \(programme?.title ?? channel.name)"
            item.imageShape = .poster
            item.setImageURL(programme?.artworkURL ?? placeholder, for: [.screenScale1x, .screenScale2x])
            let action = TVTopShelfAction(url: DeepLink.play(channel: channel.id))
            item.playAction = action; item.displayAction = action
            return item
        })
        section.title = "On now"
        return TVTopShelfSectionedContent(sections: [section])
    }
}
