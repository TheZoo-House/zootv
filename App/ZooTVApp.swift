import SwiftUI
import TVServices

@main struct ZooTVApp: App {
    var body: some Scene {
        WindowGroup { GuideView().preferredColorScheme(.dark) }
    }
}

@MainActor @Observable final class GuideStore {
    var guide: Guide?
    var error: String?
    var loading = false
    var detail: Programme?
    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            guide = try await GuideClient().load()
            error = nil
            TVTopShelfContentProvider.topShelfContentDidChange()
        } catch is CancellationError {
        } catch {
            self.error = "Cannot refresh ZooTV. Check your home network. \(error.localizedDescription)"
        }
    }
}

extension Date {
    var clock: String { formatted(date: .omitted, time: .shortened) }
}
